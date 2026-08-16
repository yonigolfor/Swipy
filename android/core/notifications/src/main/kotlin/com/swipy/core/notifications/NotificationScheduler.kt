package com.swipy.core.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Exact-alarm scheduling for the 3 non-quota-limited triggers (swipe-limit-reset, weekly
 * cleanup, inactivity reminder) — the Android analogue of iOS's `UNCalendarNotificationTrigger`/
 * `UNTimeIntervalNotificationTrigger`. Deliberately `AlarmManager`, not `WorkManager`: these
 * three need real exact-time delivery (00:01 sharp, Sunday 21:30 sharp), which WorkManager's
 * batched/inexact scheduling can't guarantee the way `setExactAndAllowWhileIdle` can. See
 * [SwipyNotificationWorker] for the periodic/best-effort checks (review bin, milestone), which
 * *are* a good fit for WorkManager.
 */
@Singleton
class NotificationScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val alarmManager: AlarmManager
        get() = context.getSystemService(AlarmManager::class.java)

    /** No-ops silently if exact-alarm scheduling permission was revoked (API 31+, user can
     * disable per-app in Settings) — the caller has no in-app recovery path to offer yet; see
     * `android/TODO.md` item 7's permission-request follow-up note. */
    fun scheduleExact(trigger: NotificationTrigger, triggerAtMillis: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) return
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, alarmPendingIntent(trigger))
    }

    fun cancel(trigger: NotificationTrigger) {
        alarmManager.cancel(alarmPendingIntent(trigger))
    }

    /** Arms the two "OS-guaranteed forever" recurring reminders — call once at cold start
     * (`SwipyApplication.onCreate()`) and again after a device reboot ([BootReceiver]), since
     * exact alarms don't survive either. Safe to call repeatedly: [scheduleExact] replaces the
     * existing alarm for the same [NotificationTrigger.notificationId] rather than duplicating. */
    fun armPersistentReminders() {
        scheduleExact(NotificationTrigger.WeeklyCleanup, nextSundayAt2130Millis())
        scheduleExact(NotificationTrigger.InactivityReminder, System.currentTimeMillis() + INACTIVITY_WINDOW_MILLIS)
    }

    private fun alarmPendingIntent(trigger: NotificationTrigger): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(AlarmReceiver.EXTRA_TRIGGER, trigger.name)
        }
        return PendingIntent.getBroadcast(
            context,
            trigger.notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
