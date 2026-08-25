package com.swipy.domain.repository

import kotlinx.coroutines.flow.StateFlow

/**
 * Daily free-swipe cap — port of iOS `DailyLimitService`. Has zero premium/billing knowledge of
 * its own, mirroring iOS exactly: [canSwipe] only ever *receives* premium status as a parameter,
 * it never reads [PremiumRepository] itself.
 *
 * All state is exposed as [StateFlow] (eagerly collected by the implementation, never a cold
 * suspend read) so [canSwipe] can be called synchronously from `PhotoStackViewModel.handleSwipe`'s
 * perf-critical swipe-commit path — the direct analogue of iOS's `@Published` properties being
 * readable without an `await`.
 */
interface SwipeQuotaRepository {

    /** 120 — the base daily allowance, before any bonus. Matches iOS `DailyLimitService.dailyLimit`. */
    val dailyLimit: Int

    val swipesUsedToday: StateFlow<Int>
    val bonusSwipesGranted: StateFlow<Int>

    /** `max(0, dailyLimit + bonusSwipesGranted - swipesUsedToday)`. */
    val remainingSwipes: StateFlow<Int>

    /** `swipesUsedToday >= dailyLimit + bonusSwipesGranted`. */
    val hasReachedLimit: StateFlow<Boolean>

    /** True once the user has already claimed today's share bonus — hides the share button. */
    val hasSharedToday: StateFlow<Boolean>

    /** `isPremium || !hasReachedLimit`. Synchronous — reads current [StateFlow] values only. */
    fun canSwipe(isPremium: Boolean): Boolean

    /** Increments today's swipe count (resetting first if the calendar day has rolled over). */
    suspend fun recordSwipe()

    /** Grants the one-time +50 daily bonus. Callers must guard with [hasSharedToday] first. */
    suspend fun applyShareBonus()
}
