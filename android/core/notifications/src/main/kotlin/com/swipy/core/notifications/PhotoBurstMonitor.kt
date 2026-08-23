package com.swipy.core.notifications

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.repository.MediaChangeNotifier
import com.swipy.domain.repository.PhotoRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * Foreground, real-time path for the photo-burst trigger — the Android analogue of iOS's
 * `PHPhotoLibraryChangeObserver`-driven `checkBurstFromLibraryChange`. See
 * `SwipyNotificationWorker.checkPhotoBurstTrigger` for the independent background/periodic path;
 * the two intentionally use separate baselines ([burstSessionBaseCount] here is in-memory and
 * resets every foreground, `NotificationStateStore.lastKnownPhotoCount` there is persisted and
 * only advances on send), exactly mirroring `NOTIFICATIONS.md`'s two-path design.
 */
@Singleton
class PhotoBurstMonitor @Inject constructor(
    private val mediaChangeNotifier: MediaChangeNotifier,
    private val photoRepository: PhotoRepository,
    private val notificationManager: SwipyNotificationManager,
    private val contentBuilder: NotificationContentBuilder,
    private val stateStore: NotificationStateStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Volatile
    private var burstSessionBaseCount: Int? = null

    /** Call once at process start ([SwipyApplication.onCreate]). Debounces rapid-fire
     * `ContentObserver` events (a bulk import can touch MediaStore dozens of times) into a
     * single count check per burst of activity. */
    @OptIn(FlowPreview::class)
    fun start() {
        mediaChangeNotifier.observeChanges()
            .debounce(3.seconds)
            .onEach { checkForBurst() }
            .launchIn(scope)
    }

    /** Re-baselines to the current library size — call on every app foreground (mirrors iOS's
     * `resetBurstBaseline()`, invoked from `scenePhase == .active`). */
    fun resetSessionBaseline() {
        scope.launch {
            burstSessionBaseCount = photoRepository.totalCount(FilterCategory.All)
        }
    }

    private suspend fun checkForBurst() {
        val baseline = burstSessionBaseCount ?: return
        val currentCount = photoRepository.totalCount(FilterCategory.All)
        if (currentCount - baseline < PHOTO_BURST_THRESHOLD) return
        if (System.currentTimeMillis() - stateStore.lastBurstNotifiedAt.first() < PHOTO_BURST_COOLDOWN_MILLIS) return
        if (!stateStore.tryConsumeDailyQuota()) return

        val (title, body) = contentBuilder.forPhotoBurst(currentCount - baseline)
        notificationManager.post(NotificationTrigger.PhotoBurst, title, body)
        stateStore.setLastBurstNotifiedAt(System.currentTimeMillis())
        burstSessionBaseCount = currentCount
    }
}
