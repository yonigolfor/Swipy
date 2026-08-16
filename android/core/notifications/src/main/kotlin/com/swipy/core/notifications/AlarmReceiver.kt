package com.swipy.core.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Fires when one of [NotificationTrigger]'s 3 exact-alarm triggers
 * ([NotificationTrigger.SwipeLimitReset]/[NotificationTrigger.WeeklyCleanup]/
 * [NotificationTrigger.InactivityReminder]) is due — scheduled by [NotificationScheduler].
 * [NotificationTrigger.ReviewBinReminder]/[NotificationTrigger.Milestone]/
 * [NotificationTrigger.PhotoBurst] are posted from [SwipyNotificationWorker] instead, never
 * from here.
 *
 * None of the 3 triggers this handles need repository data to build their notification text
 * (unlike the Worker's checks) — a plain synchronous `onReceive` is sufficient, no `goAsync()`
 * needed.
 */
@AndroidEntryPoint
class AlarmReceiver : BroadcastReceiver() {

    @Inject lateinit var notificationManager: SwipyNotificationManager

    @Inject lateinit var scheduler: NotificationScheduler

    @Inject lateinit var contentBuilder: NotificationContentBuilder

    override fun onReceive(context: Context, intent: Intent) {
        val trigger = NotificationTrigger.entries.find { it.name == intent.getStringExtra(EXTRA_TRIGGER) } ?: return
        val (title, body) = when (trigger) {
            NotificationTrigger.SwipeLimitReset -> contentBuilder.forSwipeLimitReset()
            NotificationTrigger.WeeklyCleanup -> contentBuilder.forWeeklyCleanup()
            NotificationTrigger.InactivityReminder -> contentBuilder.forInactivityReminder()
            NotificationTrigger.ReviewBinReminder, NotificationTrigger.Milestone, NotificationTrigger.PhotoBurst -> return
        }
        notificationManager.post(trigger, title, body)

        // AlarmManager has no `repeats: true` equivalent for exact alarms — the weekly
        // reminder re-arms itself for next Sunday right after firing, mirroring iOS's
        // OS-guaranteed recurrence. Inactivity is deliberately NOT re-armed here — iOS only
        // resets that countdown on the next foreground, not immediately after it fires.
        if (trigger == NotificationTrigger.WeeklyCleanup) {
            scheduler.scheduleExact(trigger, nextSundayAt2130Millis())
        }
    }

    companion object {
        const val EXTRA_TRIGGER = "com.swipy.notifications.EXTRA_TRIGGER"
    }
}
