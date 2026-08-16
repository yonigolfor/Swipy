package com.swipy.core.notifications

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.random.Random

/** Resolves the title/body text for each [NotificationTrigger] from string resources — kept
 * separate from [SwipyNotificationManager] so [AlarmReceiver] (synchronous, no Compose context)
 * and [SwipyNotificationWorker] (suspend, has repository data) can both build content without
 * needing `stringResource()`'s @Composable requirement. */
@Singleton
class NotificationContentBuilder @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    fun forSwipeLimitReset(): Pair<String, String> =
        context.getString(R.string.notif_swipe_limit_title) to context.getString(R.string.notif_swipe_limit_body)

    /** Random 2-variant pool, mirrors iOS's `Bool.random()` pick — re-rolled every time the
     * weekly alarm fires, not just at initial scheduling. */
    fun forWeeklyCleanup(): Pair<String, String> {
        val useVariantA = Random.nextBoolean()
        val titleRes = if (useVariantA) R.string.notif_weekly_title_a else R.string.notif_weekly_title_b
        val bodyRes = if (useVariantA) R.string.notif_weekly_body_a else R.string.notif_weekly_body_b
        return context.getString(titleRes) to context.getString(bodyRes)
    }

    fun forInactivityReminder(): Pair<String, String> =
        context.getString(R.string.notif_inactivity_title) to context.getString(R.string.notif_inactivity_body)

    fun forReviewBinReminder(itemCount: Int): Pair<String, String> =
        context.getString(R.string.notif_reviewbin_title) to
            context.resources.getQuantityString(R.plurals.notif_reviewbin_body, itemCount, itemCount)

    fun forMilestone(gbSaved: Int): Pair<String, String> =
        context.getString(R.string.notif_milestone_title) to
            context.getString(R.string.notif_milestone_body, gbSaved)

    fun forPhotoBurst(newPhotoCount: Int): Pair<String, String> =
        context.getString(R.string.notif_burst_title) to
            context.getString(R.string.notif_burst_body, newPhotoCount)
}
