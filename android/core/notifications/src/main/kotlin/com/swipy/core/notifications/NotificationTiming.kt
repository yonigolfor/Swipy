package com.swipy.core.notifications

import java.util.Calendar

/** 72h since last foreground — mirrors iOS's `UNTimeIntervalNotificationTrigger(timeInterval:
 * 72*3600, repeats: false)` for the inactivity reminder. */
internal const val INACTIVITY_WINDOW_MILLIS = 72L * 60 * 60 * 1000

/** Minimum photo-count threshold and re-fire cooldown for the photo-burst trigger, and the
 * Review Bin reminder's "sat unresolved for 24h" window — all three mirror `NOTIFICATIONS.md`'s
 * exact iOS constants (50 new photos, 24h burst cooldown, 24h bin-reminder delay). */
internal const val PHOTO_BURST_THRESHOLD = 50
internal const val PHOTO_BURST_COOLDOWN_MILLIS = 24L * 60 * 60 * 1000
internal const val REVIEW_BIN_REMINDER_DELAY_MILLIS = 24L * 60 * 60 * 1000

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

/**
 * 00:01 (local time) on the next calendar day — mirrors iOS `DailyLimitService`'s swipe-limit-
 * reset notification timing exactly. Public (unlike the other helpers in this file) since
 * `:feature:swipe`'s `PhotoStackViewModel` is the caller, scheduling this the moment a swipe
 * exhausts the daily quota — see `SwipeQuotaRepository`/android/TODO.md item 9.
 */
fun nextMidnightPlusOneMinuteMillis(): Long {
    val calendar = Calendar.getInstance().apply {
        add(Calendar.DAY_OF_YEAR, 1)
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 1)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    return calendar.timeInMillis
}
