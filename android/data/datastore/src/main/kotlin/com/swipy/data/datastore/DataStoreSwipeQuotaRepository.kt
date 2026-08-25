package com.swipy.data.datastore

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import com.swipy.domain.repository.SwipeQuotaRepository
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/**
 * Port of iOS `DailyLimitService`. Each field checks its own "epoch day" marker independently
 * (rather than a single shared reset flag) so a share-bonus grant and a swipe-count reset never
 * cross-contaminate each other's staleness check — both still ultimately compare against
 * [today], the exact analogue of iOS's `Calendar.startOfDay` comparison.
 *
 * Every public [StateFlow] is eagerly collected (`SharingStarted.Eagerly`) into a
 * repository-owned [scope] so [canSwipe] can read `.value` synchronously — see
 * `SwipeQuotaRepository`'s own doc comment for why this must never be a suspend/cold read.
 * Deliberately does *not* re-evaluate [today] on a timer: like iOS's own `hasReachedLimit`
 * (a plain computed property `DailyLimitService` never re-derives outside of `recordSwipe`/
 * `init`), a value only refreshes on the next DataStore write — an app left foregrounded across
 * midnight with no successful swipe stays blocked until the next cold start, matching iOS's own
 * documented behavior rather than a gap introduced here.
 */
@Singleton
class DataStoreSwipeQuotaRepository @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) : SwipeQuotaRepository {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override val dailyLimit: Int = 120

    private val today: Long get() = LocalDate.now().toEpochDay()

    override val swipesUsedToday: StateFlow<Int> = dataStore.data
        .map { prefs -> if ((prefs[SWIPE_DATE] ?: 0L) >= today) prefs[SWIPE_COUNT] ?: 0 else 0 }
        .stateIn(scope, SharingStarted.Eagerly, 0)

    override val bonusSwipesGranted: StateFlow<Int> = dataStore.data
        .map { prefs -> if ((prefs[BONUS_DATE] ?: 0L) >= today) prefs[BONUS_COUNT] ?: 0 else 0 }
        .stateIn(scope, SharingStarted.Eagerly, 0)

    override val hasSharedToday: StateFlow<Boolean> = dataStore.data
        .map { prefs -> (prefs[BONUS_DATE] ?: 0L) >= today }
        .stateIn(scope, SharingStarted.Eagerly, false)

    override val remainingSwipes: StateFlow<Int> = combine(swipesUsedToday, bonusSwipesGranted) { used, bonus ->
        (dailyLimit + bonus - used).coerceAtLeast(0)
    }.stateIn(scope, SharingStarted.Eagerly, dailyLimit)

    override val hasReachedLimit: StateFlow<Boolean> = combine(swipesUsedToday, bonusSwipesGranted) { used, bonus ->
        used >= dailyLimit + bonus
    }.stateIn(scope, SharingStarted.Eagerly, false)

    override fun canSwipe(isPremium: Boolean): Boolean = isPremium || !hasReachedLimit.value

    override suspend fun recordSwipe() {
        dataStore.edit { prefs ->
            val current = if ((prefs[SWIPE_DATE] ?: 0L) >= today) prefs[SWIPE_COUNT] ?: 0 else 0
            prefs[SWIPE_COUNT] = current + 1
            prefs[SWIPE_DATE] = today
        }
    }

    override suspend fun applyShareBonus() {
        dataStore.edit { prefs ->
            prefs[BONUS_COUNT] = 50
            prefs[BONUS_DATE] = today
        }
    }

    private companion object {
        val SWIPE_COUNT = intPreferencesKey("swipe_quota_used_today")
        val SWIPE_DATE = longPreferencesKey("swipe_quota_date_epoch_day")
        val BONUS_COUNT = intPreferencesKey("swipe_quota_bonus")
        val BONUS_DATE = longPreferencesKey("swipe_quota_bonus_date_epoch_day")
    }
}
