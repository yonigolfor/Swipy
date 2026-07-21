//
//  VideoPlayerPool.swift
//  CleanSwipe
//
//  A singleton pool that pre-loads AVPlayerItems for upcoming video assets.
//  This eliminates the black-screen delay when a video card reaches the top
//  of the swipe stack by preparing AVPlayer instances in the background
//  before they are needed.
//
//  Design:
//  - Holds up to `maxPoolSize` (5) prepared AVPlayer instances keyed by asset localIdentifier.
//  - PhotoStackViewModel calls `warmUp(for:)` whenever the stack changes, passing a
//    wider look-ahead window (12-15 assets) than maxPoolSize so a true 2-video
//    look-ahead beyond the visible stack is possible even in mixed photo/video runs.
//  - Loads are bounded to `maxConcurrentLoads` (2) simultaneous PHImageManager calls via
//    a simple queue (enqueue/startLoad/finishLoad) so a wide window doesn't starve the
//    item the user needs soonest. evict() frees a held slot immediately on cancellation
//    rather than waiting for the (now-cancelled) PHImageManager callback to fire — which
//    it may still do anyway, since Swift Task cancellation doesn't stop an already-fired
//    PHImageManager call. `loadGeneration` guards finishLoad against exactly that: a
//    stale completion from an evicted-then-re-enqueued asset's old attempt.
//  - PhotoCardView calls `awaitPlayer(for:)` which waits for an in-flight load rather
//    than firing a competing PHImageManager request — eliminates the first-video race.
//  - When a card is swiped away, PhotoCardView calls `release(for:)` so the pool
//    can evict that player and reclaim memory.
//  - All PHImageManager calls happen on a background queue; only the final
//    dictionary writes are dispatched to the main actor.
//

import AVFoundation
import Photos

@MainActor
final class VideoPlayerPool {

    // MARK: - Singleton

    static let shared = VideoPlayerPool()
    private init() {}

    // MARK: - Constants

    /// Maximum number of AVPlayer instances kept alive simultaneously.
    /// 5 covers: top card + up to 2 back cards + a 2-video true look-ahead
    /// buffer beyond what's visible. Provisional — validate against a memory/
    /// thermal profile on the oldest supported device before locking this in.
    private let maxPoolSize = 5

    /// Maximum number of PHImageManager.requestPlayerItem calls allowed to run
    /// concurrently during warm-up. Bounds I/O/decoder-session contention when
    /// the wider look-ahead window (see warmUp's caller) fires several loads at
    /// once — without this, a far-ahead item's load competes for bandwidth with
    /// the one the user needs next. Provisional, same caveat as maxPoolSize.
    private let maxConcurrentLoads = 2

    // MARK: - State

    /// Prepared players keyed by PHAsset.localIdentifier.
    /// Access only on the main actor.
    private var pool: [String: AVPlayer] = [:]

    /// Tracks which asset IDs are currently being loaded OR queued waiting for a
    /// concurrency slot, to prevent duplicate PHImageManager requests for the
    /// same asset. A superset of `activeLoadIDs`.
    private var inFlight: Set<String> = []

    /// Subset of `inFlight` currently holding one of the `maxConcurrentLoads` slots
    /// (their PHImageManager.requestPlayerItem call is actually running).
    private var activeLoadIDs: Set<String> = []

    /// Assets in `inFlight` waiting for a concurrency slot, in start order.
    private var pendingLoadQueue: [PHAsset] = []

    /// In-flight PHImageRequestIDs, keyed by asset ID, so evict() can actually
    /// cancel the underlying Photos request instead of only detaching our Task
    /// from its result.
    private var requestIDs: [String: PHImageRequestID] = [:]

    /// Monotonic per-asset attempt counter. `startLoad` stamps the generation it
    /// was started with; `finishLoad` only accepts a completion whose stamp still
    /// matches the current value. Without this, an asset that gets evicted and then
    /// re-enqueued (e.g. swiped away, then shake-undo brings it right back) could
    /// have its *new* load's result clobbered by a stale completion from the *old*,
    /// cancelled-but-still-in-flight request racing in afterward — cancelling the
    /// Swift Task doesn't guarantee the underlying PHImageManager call stops.
    private var loadGeneration: [String: Int] = [:]

    /// Continuations waiting for a specific asset to finish loading.
    /// Keyed by asset ID → (waiter UUID → continuation) so each waiter
    /// can be individually timed out and removed without affecting others.
    private var pendingContinuations: [String: [UUID: CheckedContinuation<AVPlayer?, Never>]] = [:]

    /// Tasks driving each in-flight PHImageManager load, keyed by asset localIdentifier.
    /// Cancelled in evict() so stale loads don't corrupt the pool after the asset
    /// leaves the visible window on fast swipes or mode switches.
    private var inFlightTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Public API

    /// Returns an already-prepared AVPlayer for `asset` if one exists in the pool,
    /// or nil if it is not in the pool (may still be in-flight — use awaitPlayer instead).
    func player(for asset: PHAsset) -> AVPlayer? {
        pool[asset.localIdentifier]
    }

    /// Returns true if the pool is currently loading a player for `assetID`.
    /// Useful for displaying loading indicators before awaitPlayer is called.
    func isLoading(for assetID: String) -> Bool {
        inFlight.contains(assetID)
    }

    /// Returns a prepared AVPlayer for `asset`, waiting up to `timeout` seconds
    /// if the asset is currently being loaded by the pool (in-flight).
    ///
    /// - Returns: the pooled player when ready, or nil if not in-flight or timeout expires.
    ///
    /// Prefer this over `player(for:)` + slow-path fallback in callers that run
    /// concurrently with `warmUp` — it eliminates the duplicate PHImageManager request
    /// that causes the first-video freeze.
    func awaitPlayer(for asset: PHAsset, timeout: TimeInterval = 0.5) async -> AVPlayer? {
        let id = asset.localIdentifier

        // Already ready — instant return.
        if let existing = pool[id] { return existing }

        // Not in the pool and not being loaded — caller must use its own slow path.
        guard inFlight.contains(id) else { return nil }

        // Suspend until the in-flight load completes or the timeout fires.
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            pendingContinuations[id, default: [:]][waiterID] = continuation

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                // If our continuation is still registered after the timeout, resume with nil.
                if pendingContinuations[id]?[waiterID] != nil {
                    pendingContinuations[id]?.removeValue(forKey: waiterID)
                    if pendingContinuations[id]?.isEmpty == true {
                        pendingContinuations.removeValue(forKey: id)
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Pre-loads AVPlayerItems for the given assets in priority order.
    /// Call this every time the visible stack changes (after each swipe).
    /// Assets that are already in the pool or currently loading are skipped.
    ///
    /// - Parameters:
    ///   - assets: Ordered list of upcoming PHAssets (mixed media types are fine —
    ///     non-video entries are filtered out here). Callers should pass a window
    ///     *wider* than `maxPoolSize` (the ViewModel passes ~15) so that as closer
    ///     videos get pooled or evicted across successive calls, there are always
    ///     further candidates to fill the freed slots with — a single call still
    ///     only ever acts on the first `maxPoolSize` video entries it finds.
    ///   - protectedID: Asset localIdentifier that must NOT be evicted.
    ///     Pass the top card's ID during an early (mid-drag) warm-up so the
    ///     active player is never killed before the gesture completes.
    func warmUp(for assets: [PHAsset], protectedID: String? = nil) {
        // Only warm up video assets we do not already have.
        let needed = assets
            .filter { $0.mediaType == .video }
            .prefix(maxPoolSize)
            .filter { pool[$0.localIdentifier] == nil && !inFlight.contains($0.localIdentifier) }

        for asset in needed {
            enqueue(asset: asset)
        }

        // Evict pool entries AND cancel in-flight loads for assets that are no longer
        // in the upcoming window — prevents pool pollution on fast swipes where
        // stale loads would otherwise complete and occupy a slot the new assets need.
        // The protected ID (currently displayed player) is never touched.
        let upcomingIDs = Set(assets.map { $0.localIdentifier })
        let stalePoolIDs = pool.keys.filter { !upcomingIDs.contains($0) && $0 != protectedID }
        let staleInFlightIDs = inFlight.filter { !upcomingIDs.contains($0) && $0 != protectedID }
        for id in Set(stalePoolIDs).union(staleInFlightIDs) {
            evict(id: id)
        }
    }

    /// Releases the player for `asset` from the pool.
    /// Call this when a card is swiped away and the asset will never be shown again.
    func release(for asset: PHAsset) {
        evict(id: asset.localIdentifier)
    }

    /// Pauses all players in the pool.
    /// Call this when the user navigates away from the Swipe tab.
    func pauseAll() {
        pool.values.forEach { $0.pause() }
    }

    /// Clears the entire pool and releases all AVPlayer instances.
    /// MUST be called before permanently deleting assets from the photo library,
    /// otherwise AVPlayerItems holding references to deleted assets will cause
    /// EXC_BAD_ACCESS crashes.
    func drainAll() {
        // Cancel in-flight tasks and the underlying Photos requests before evicting
        // pool entries so their completions see the cleared state and discard
        // players they were about to store.
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        requestIDs.values.forEach { PHImageManager.default().cancelImageRequest($0) }
        requestIDs.removeAll()
        activeLoadIDs.removeAll()
        pendingLoadQueue.removeAll()
        let ids = Array(pool.keys)
        ids.forEach { evict(id: $0) }
        inFlight.removeAll()
        // Resume all pending waiters with nil so they fall back to their own load path.
        for (_, waiters) in pendingContinuations {
            for cont in waiters.values { cont.resume(returning: nil) }
        }
        pendingContinuations.removeAll()
    }

    // MARK: - Private Helpers — Bounded-Concurrency Load Queue

    /// Marks `asset` as wanted and either starts loading it immediately (a
    /// concurrency slot is free) or defers it behind whatever is already loading.
    private func enqueue(asset: PHAsset) {
        let id = asset.localIdentifier
        inFlight.insert(id)
        if activeLoadIDs.count < maxConcurrentLoads {
            startLoad(asset: asset)
        } else {
            pendingLoadQueue.append(asset)
        }
    }

    /// Starts the next queued asset, if any and a slot is free. Called whenever
    /// a load finishes — success, miss, or eviction — so the queue keeps draining.
    private func startNextQueuedLoad() {
        guard activeLoadIDs.count < maxConcurrentLoads, !pendingLoadQueue.isEmpty else { return }
        let next = pendingLoadQueue.removeFirst()
        // May have been evicted while still queued (id no longer wanted) — skip it.
        guard inFlight.contains(next.localIdentifier) else {
            startNextQueuedLoad()
            return
        }
        startLoad(asset: next)
    }

    /// Loads an AVPlayerItem for `asset` on a background queue and stores
    /// the resulting AVPlayer in the pool on the main actor, then wakes
    /// any callers suspended in `awaitPlayer`. Assumes a concurrency slot
    /// is already accounted for by the caller (enqueue/startNextQueuedLoad).
    private func startLoad(asset: PHAsset) {
        let id = asset.localIdentifier
        activeLoadIDs.insert(id)
        let generation = (loadGeneration[id] ?? 0) + 1
        loadGeneration[id] = generation

        let options = PHVideoRequestOptions()
        let offline = PhotoLibraryService.shared.isOfflineMode
        // Offline: highQualityFormat ensures the full-size local original, never a proxy.
        // Online: fastFormat for instant playback start.
        options.deliveryMode = offline ? .highQualityFormat : .fastFormat
        // In offline mode every asset has passed isLocallyAvailable — no iCloud fetch.
        options.isNetworkAccessAllowed = !offline

        // PHImageManager must be called from a background thread to avoid
        // blocking the main thread during the network/disk fetch.
        let task = Task.detached(priority: .userInitiated) {
            // If evict() already cancelled this Task before we got here (e.g. a fast
            // swipe passed this asset before its turn in the concurrency queue came
            // up), skip the PHImageManager call entirely — evict() already released
            // this slot and cleaned up, there's nothing left for us to do.
            guard !Task.isCancelled else { return }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let requestID = PHImageManager.default().requestPlayerItem(
                    forVideo: asset,
                    options: options
                ) { playerItem, _ in
                    guard let playerItem else {
                        Task { @MainActor in self.finishLoad(id: id, player: nil, generation: generation) }
                        continuation.resume()
                        return
                    }

                    // Reduced read-ahead buffer for pool-only (not yet visible) items —
                    // trims memory for the assets furthest from being watched. Reset to
                    // automatic (0) in PhotoCardView.activatePlayer() before playback
                    // starts, so this never affects what the user actually watches.
                    playerItem.preferredForwardBufferDuration = Self.pooledBufferDuration

                    // Build the AVPlayer and register the loop observer
                    // before hopping to the main actor so the player is
                    // fully configured when the View receives it.
                    let player = AVPlayer(playerItem: playerItem)
                    player.isMuted = PhotoCardView.globalMute

                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: playerItem,
                        queue: .main
                    ) { [weak player] _ in
                        guard let player, player.currentItem != nil else { return }
                        player.seek(to: .zero)
                        player.play()
                    }

                    Task { @MainActor in self.finishLoad(id: id, player: player, generation: generation) }
                    continuation.resume()
                }
                Task { @MainActor in self.requestIDs[id] = requestID }
            }
        }
        inFlightTasks[id] = task
    }

    /// Common completion path for a load — success or miss. Frees this asset's
    /// concurrency slot, stores/discards the player, wakes waiters, and starts
    /// whatever is next in the queue.
    ///
    /// `generation` must match the current value in `loadGeneration[id]` — see
    /// that property's doc for why a stale completion can otherwise clobber a
    /// newer load for the same asset.
    private func finishLoad(id: String, player: AVPlayer?, generation: Int) {
        guard loadGeneration[id] == generation else {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            return
        }

        inFlightTasks.removeValue(forKey: id)
        requestIDs.removeValue(forKey: id)
        activeLoadIDs.remove(id)
        defer { startNextQueuedLoad() }

        guard let player else {
            inFlight.remove(id)
            wakeWaiters(for: id, player: nil)
            return
        }
        // Guard: evict() clears inFlight when an asset leaves the visible
        // window. If that happened while this request was in-flight,
        // discard the freshly-built player — it is no longer needed.
        guard inFlight.contains(id) else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }
        if pool.count < maxPoolSize {
            pool[id] = player
        }
        inFlight.remove(id)
        // Wake waiters with the player (pool[id]) or directly with
        // `player` when the pool was full — either way they get playback.
        wakeWaiters(for: id, player: pool[id] ?? player)
    }

    /// Resumes all continuations waiting for `id` and clears the waiter list.
    private func wakeWaiters(for id: String, player: AVPlayer?) {
        guard let waiters = pendingContinuations.removeValue(forKey: id) else { return }
        for cont in waiters.values { cont.resume(returning: player) }
    }

    /// Removes a player (or a queued/in-flight request) from the pool and cleans
    /// up its resources.
    private func evict(id: String) {
        // Cancel the loading task and the underlying Photos request so the
        // PHImageManager callback stops promptly instead of finishing unseen.
        inFlightTasks[id]?.cancel()
        inFlightTasks.removeValue(forKey: id)
        if let requestID = requestIDs.removeValue(forKey: id) {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        inFlight.remove(id)
        pendingLoadQueue.removeAll { $0.localIdentifier == id }
        // If this asset held a concurrency slot, free it immediately for the next
        // queued item rather than waiting for its now-cancelled PHImageManager
        // callback to eventually fire (which may be delayed or never arrive).
        if activeLoadIDs.remove(id) != nil {
            startNextQueuedLoad()
        }
        // Wake any callers suspended in awaitPlayer so they fall back to their
        // own slow path instead of waiting indefinitely for a cancelled load.
        wakeWaiters(for: id, player: nil)
        guard let player = pool.removeValue(forKey: id) else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    /// Read-ahead buffer duration (seconds) for pooled players not yet on screen.
    /// Provisional — validate against a memory profile before finalizing.
    private static let pooledBufferDuration: TimeInterval = 2.0
}
