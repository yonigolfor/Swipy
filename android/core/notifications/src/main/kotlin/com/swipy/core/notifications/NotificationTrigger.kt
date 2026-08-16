package com.swipy.core.notifications

/**
 * The 6 trigger types ported from iOS's `NOTIFICATIONS.md` — see `android/TODO.md` item 7 for
 * the full trigger map. [notificationId] doubles as the id passed to
 * `NotificationManagerCompat.notify`/the `PendingIntent` request code for its alarm, so posting
 * the same trigger twice replaces the existing notification/alarm rather than stacking a
 * duplicate (mirrors iOS's "same identifier -> atomic replace" behavior for the Review Bin and
 * weekly-cleanup notifications).
 *
 * [deepLinkRoute] must match one of `MainActivity`'s `ROUTE_FILTERS`/`ROUTE_SWIPE`/
 * `ROUTE_REVIEW_BIN` string constants exactly — this module can't reference `:app`'s
 * `MainActivity` directly (wrong dependency direction), so the route name is duplicated here as
 * a plain string and must be kept in sync manually if those constants ever change.
 */
enum class NotificationTrigger(val notificationId: Int, val deepLinkRoute: String) {
    ReviewBinReminder(1001, "reviewbin"),
    PhotoBurst(1002, "swipe"),
    Milestone(1003, "swipe"),
    SwipeLimitReset(1004, "swipe"),
    WeeklyCleanup(1005, "swipe"),
    InactivityReminder(1006, "swipe"),
}
