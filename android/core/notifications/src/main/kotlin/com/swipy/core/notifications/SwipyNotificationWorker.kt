package com.swipy.core.notifications

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.swipy.domain.repository.PhotoStateRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.first

private const val GB_IN_BYTES = 1_073_741_824L

/**
 * Periodic background checks for the review-bin-reminder and milestone triggers — the Android
 * analogue of iOS's `BGAppRefreshTask`-driven `checkReviewBinTrigger()`/`checkMilestoneTrigger()`
 * (best-effort timing either way; iOS doesn't guarantee exact delivery for these either).
 *
 * [NotificationTrigger.PhotoBurst] is deliberately NOT checked here yet — it needs a persisted
 * photo-count baseline tracked via a `MediaStore` `ContentObserver`, which doesn't exist on
 * Android yet (see `android/CLAUDE.md`'s "MediaStore Querying" section and `android/TODO.md`
 * item 7's explicit scope note). Wire it in once that observer exists — do not add a naive
 * "count photos every worker run" check in the meantime, since that reintroduces exactly the
 * baseline-drift bug class iOS's own `NOTIFICATIONS.md` documents having already fixed once.
 */
@HiltWorker
class SwipyNotificationWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val photoStateRepository: PhotoStateRepository,
    private val notificationManager: SwipyNotificationManager,
    private val contentBuilder: NotificationContentBuilder,
    private val stateStore: NotificationStateStore,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        checkReviewBinReminder()
        checkMilestone()
        return Result.success()
    }

    private suspend fun checkReviewBinReminder() {
        val binIds = photoStateRepository.reviewBinIds.first()
        if (binIds.isEmpty()) return
        // Coarser than iOS's real "24h since the bin first became non-empty" condition — this
        // repository only persists a bare id list, no per-item "added at" timestamp (see
        // PhotoStateRepository's doc comment). Firing on every periodic run while the bin is
        // non-empty is debounced by NotificationManagerCompat's own id-based replace-not-stack
        // behavior (same notification id updates in place) and the daily quota below, not by a
        // real elapsed-time check — revisit if a per-item timestamp is ever added to the bin.
        if (!stateStore.tryConsumeDailyQuota()) return
        val (title, body) = contentBuilder.forReviewBinReminder(binIds.size)
        notificationManager.post(NotificationTrigger.ReviewBinReminder, title, body)
    }

    private suspend fun checkMilestone() {
        val gbSaved = (photoStateRepository.totalSpaceSavedLifetime.first() / GB_IN_BYTES).toInt()
        val lastNotified = stateStore.lastMilestoneNotifiedGb.first()
        if (gbSaved <= lastNotified) return
        if (!stateStore.tryConsumeDailyQuota()) return
        val (title, body) = contentBuilder.forMilestone(gbSaved)
        notificationManager.post(NotificationTrigger.Milestone, title, body)
        stateStore.setLastMilestoneNotifiedGb(gbSaved)
    }

    companion object {
        private const val WORK_NAME = "swipy_notification_check"

        /** ~6h, matching iOS's own requested (not guaranteed) `BGAppRefreshTask` cadence —
         * comfortably above WorkManager's 15-minute periodic floor. Call once from
         * `SwipyApplication.onCreate()`; `ExistingPeriodicWorkPolicy.KEEP` (the enqueueUniquePeriodicWork
         * default via this helper) makes repeated calls across app restarts safe/idempotent. */
        fun enqueue(workManager: WorkManager) {
            val request = PeriodicWorkRequestBuilder<SwipyNotificationWorker>(6, TimeUnit.HOURS).build()
            workManager.enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }
}
