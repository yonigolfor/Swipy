package com.swipy.core.notifications

import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
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
    }
}
