package com.swipy.core.notifications

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Notification-specific persisted state — the Android analogue of iOS `PersistenceService`'s
 * `notifCapCount`/`notifCapDate`/`lastMilestoneNotifiedGB` keys. Shares the app's single
 * Preferences DataStore file (the `DataStore<Preferences>` singleton bound in
 * `:data:datastore`'s `DataStoreProvidesModule`, injected here by type only — see this module's
 * build.gradle.kts) rather than opening a second competing DataStore file, matching the
 * "one file per app" guidance and this repo's existing `PhotoStateRepository` convention of
 * namespacing distinct keys within that one file.
 */
@Singleton
class NotificationStateStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    val lastMilestoneNotifiedGb: Flow<Int> = dataStore.data.map { it[LAST_MILESTONE_GB] ?: 0 }

    suspend fun setLastMilestoneNotifiedGb(gb: Int) {
        dataStore.edit { it[LAST_MILESTONE_GB] = gb }
    }

    /**
     * Max 2 quota-limited notifications/day — gates [NotificationTrigger.ReviewBinReminder],
     * [NotificationTrigger.Milestone], and [NotificationTrigger.PhotoBurst] only.
     * [NotificationTrigger.SwipeLimitReset]/[NotificationTrigger.WeeklyCleanup]/
     * [NotificationTrigger.InactivityReminder] are NOT quota-limited, matching
     * `NOTIFICATIONS.md`'s exact rule (self-initiated/functional or persistent-reminder
     * notifications don't compete with the engagement-nudge quota). Returns `true` and consumes
     * one unit of quota if the caller may proceed; `false` if today's quota is already spent.
     */
    suspend fun tryConsumeDailyQuota(): Boolean {
        val today = LocalDate.now().toString()
        var consumed = false
        dataStore.edit { prefs ->
            val count = if (prefs[NOTIF_CAP_DATE] == today) prefs[NOTIF_CAP_COUNT] ?: 0 else 0
            if (count < DAILY_QUOTA) {
                prefs[NOTIF_CAP_DATE] = today
                prefs[NOTIF_CAP_COUNT] = count + 1
                consumed = true
            }
        }
        return consumed
    }

    private companion object {
        val LAST_MILESTONE_GB = intPreferencesKey("notif_last_milestone_gb")
        val NOTIF_CAP_DATE = stringPreferencesKey("notif_cap_date")
        val NOTIF_CAP_COUNT = intPreferencesKey("notif_cap_count")
        const val DAILY_QUOTA = 2
    }
}
