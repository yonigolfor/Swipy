package com.swipy.core.notifications

import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.swipy.domain.repository.SwipeQuotaRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The Android analogue of iOS's `scenePhase == .active` handler, which bundles several
 * foreground-triggered notification resets together (`resetBurstBaseline()`,
 * `rescheduleInactivityReminder()`, `rescheduleWeeklyCleanup()`). [ProcessLifecycleOwner] is the
 * app-wide (not per-Activity) foreground/background signal — the correct native analogue of
 * `scenePhase`, since a per-`Activity` `onResume` would also fire on internal navigation, not
 * just on the app actually returning to the foreground.
 */
@Singleton
class NotificationForegroundCoordinator @Inject constructor(
    private val photoBurstMonitor: PhotoBurstMonitor,
    private val scheduler: NotificationScheduler,
    private val swipeQuotaRepository: SwipeQuotaRepository,
) : DefaultLifecycleObserver {

    /** Call once from `SwipyApplication.onCreate()`. */
    fun start() {
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        photoBurstMonitor.resetSessionBaseline()
        // armPersistentReminders() replaces (by notificationId), never duplicates, the existing
        // weekly-cleanup/inactivity alarms — safe to call on every foreground, matching iOS's
        // own "re-arm on every scenePhase == .active" behavior for both.
        scheduler.armPersistentReminders()
        // Opportunistic cleanup for the swipe-limit-reset alarm — mirrors iOS's own
        // resetIfNewDay() cancellation (also only ever runs when some other call happens to
        // trigger it, not a dedicated day-boundary watcher). If the quota is no longer
        // exhausted (a new calendar day rolled over since the alarm was scheduled), a stale
        // "you can swipe again!" notification would otherwise still fire at the original time.
        if (!swipeQuotaRepository.hasReachedLimit.value) {
            scheduler.cancel(NotificationTrigger.SwipeLimitReset)
        }
    }
}
