package com.swipy.core.notifications

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.swipy.domain.model.FilterCategory
import com.swipy.domain.repository.PhotoRepository
import com.swipy.domain.repository.PhotoStateRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.first

private const val GB_IN_BYTES = 1_073_741_824L

/**
 * Periodic background checks for the review-bin-reminder, milestone, and photo-burst triggers —
 * the Android analogue of iOS's `BGAppRefreshTask`-driven `checkReviewBinTrigger()`/
 * `checkMilestoneTrigger()`/`checkPhotoBurstTrigger()` (best-effort timing either way; iOS
 * doesn't guarantee exact delivery for these either). See [PhotoBurstMonitor] for the
 * independent, real-time foreground path to the same [NotificationTrigger.PhotoBurst] trigger —
 * the two intentionally use separate baselines (this worker's is persisted and only advances on
 * send; the monitor's is in-memory and resets every foreground).
 */
@HiltWorker
class SwipyNotificationWorker @AssistedInject constructor(
    @Assisted private val appContext: Context,
    @Assisted params: WorkerParameters,
    private val photoStateRepository: PhotoStateRepository,
    private val photoRepository: PhotoRepository,
    private val notificationManager: SwipyNotificationManager,
    private val contentBuilder: NotificationContentBuilder,
    private val stateStore: NotificationStateStore,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        checkReviewBinReminder()
        checkMilestone()
        checkPhotoBurstTrigger()
        return Result.success()
    }

    private suspend fun checkReviewBinReminder() {
        val addedAt = photoStateRepository.reviewBinAddedAt.first()
        val oldest = addedAt.values.minOrNull() ?: return
        if (System.currentTimeMillis() - oldest < REVIEW_BIN_REMINDER_DELAY_MILLIS) return
        if (!stateStore.tryConsumeDailyQuota()) return
        val binSize = photoStateRepository.reviewBinIds.first().size
        val (title, body) = contentBuilder.forReviewBinReminder(binSize)
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

    /**
     * Background path for the photo-burst trigger — mirrors iOS's `checkPhotoBurstTrigger()`
     * exactly, including its documented first-run/permission-race fix: the very first baseline
     * must only be captured once media permission is actually granted, or a cold-start race
     * (this worker's first run landing before onboarding has requested access) would read a `0`
     * count and persist it forever as the baseline — later reading as a false "N-photo burst"
     * the moment access is granted.
     */
    private suspend fun checkPhotoBurstTrigger() {
        val currentCount = photoRepository.totalCount(FilterCategory.All)
        val baseline = stateStore.lastKnownPhotoCount.first()
        if (baseline == null) {
            if (hasMediaPermission(appContext)) stateStore.setLastKnownPhotoCount(currentCount)
            return
        }
        if (currentCount - baseline < PHOTO_BURST_THRESHOLD) return
        if (System.currentTimeMillis() - stateStore.lastBurstNotifiedAt.first() < PHOTO_BURST_COOLDOWN_MILLIS) return
        if (!stateStore.tryConsumeDailyQuota()) return

        val (title, body) = contentBuilder.forPhotoBurst(currentCount - baseline)
        notificationManager.post(NotificationTrigger.PhotoBurst, title, body)
        stateStore.setLastBurstNotifiedAt(System.currentTimeMillis())
        stateStore.setLastKnownPhotoCount(currentCount)
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

/** Duplicated (deliberately) from `:feature:onboarding`'s file-local equivalent — that module
 * can't be depended on here without inverting `:core:notifications`' dependency direction, and
 * `:domain` can't host it (no Android SDK imports allowed there). Same any-of/SDK-branch logic. */
private fun hasMediaPermission(context: Context): Boolean {
    val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
    } else {
        arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }
    return permissions.any { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
}
