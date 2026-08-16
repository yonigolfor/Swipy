package com.swipy.core.notifications

import java.util.Calendar

/** 72h since last foreground — mirrors iOS's `UNTimeIntervalNotificationTrigger(timeInterval:
 * 72*3600, repeats: false)` for the inactivity reminder. */
internal const val INACTIVITY_WINDOW_MILLIS = 72L * 60 * 60 * 1000

/** Next Sunday 21:30 (local time), always strictly in the future — mirrors iOS's
 * `UNCalendarNotificationTrigger` for the weekly cleanup reminder. Recomputed fresh each call
 * rather than cached, since [AlarmReceiver] calls this again after every fire to self-reschedule
 * the following week (AlarmManager has no `repeats: true` equivalent for exact alarms). */
internal fun nextSundayAt2130Millis(): Long {
    val calendar = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 21)
        set(Calendar.MINUTE, 30)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    val now = System.currentTimeMillis()
    while (calendar.get(Calendar.DAY_OF_WEEK) != Calendar.SUNDAY || calendar.timeInMillis <= now) {
        calendar.add(Calendar.DAY_OF_YEAR, 1)
    }
    return calendar.timeInMillis
}
