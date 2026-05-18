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
//  - Holds up to `maxPoolSize` (3) prepared AVPlayer instances keyed by asset localIdentifier.
//  - PhotoStackViewModel calls `warmUp(for:)` whenever the stack changes.
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
    /// 3 covers: top card + next 2 upcoming videos.
    private let maxPoolSize = 3

    // MARK: - State

    /// Prepared players keyed by PHAsset.localIdentifier.
    /// Access only on the main actor.
    private var pool: [String: AVPlayer] = [:]

    /// Tracks which asset IDs are currently being loaded in the background
    /// to prevent duplicate PHImageManager requests for the same asset.
    private var inFlight: Set<String> = []

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
    ///   - assets: Ordered list of upcoming PHAssets (videos only).
    ///     Pass at most `maxPoolSize` items; extras are ignored.
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
            load(asset: asset)
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
        // Cancel in-flight tasks before evicting pool entries so their completions
        // see the cleared inFlight set and discard players they were about to store.
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        let ids = Array(pool.keys)
        ids.forEach { evict(id: $0) }
        inFlight.removeAll()
        // Resume all pending waiters with nil so they fall back to their own load path.
        for (_, waiters) in pendingContinuations {
            for cont in waiters.values { cont.resume(returning: nil) }
        }
        pendingContinuations.removeAll()
    }

    // MARK: - Private Helpers

    /// Loads an AVPlayerItem for `asset` on a background queue and stores
    /// the resulting AVPlayer in the pool on the main actor, then wakes
    /// any callers suspended in `awaitPlayer`.
    private func load(asset: PHAsset) {
        let id = asset.localIdentifier
        inFlight.insert(id)

        let options = PHVideoRequestOptions()
        // .fastFormat: prioritises speed over quality for instant playback start.
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true

        // PHImageManager must be called from a background thread to avoid
        // blocking the main thread during the network/disk fetch.
        let task = Task.detached(priority: .userInitiated) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                PHImageManager.default().requestPlayerItem(
                    forVideo: asset,
                    options: options
                ) { playerItem, _ in
                    guard let playerItem else {
                        Task { @MainActor in
                            self.inFlight.remove(id)
                            self.inFlightTasks.removeValue(forKey: id)
                            self.wakeWaiters(for: id, player: nil)
                        }
                        continuation.resume()
                        return
                    }

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

                    Task { @MainActor in
                        self.inFlightTasks.removeValue(forKey: id)
                        // Guard: evict() clears inFlight when an asset leaves the visible
                        // window. If that happened while this request was in-flight,
                        // discard the freshly-built player — it is no longer needed.
                        guard self.inFlight.contains(id) else {
                            player.pause()
                            player.replaceCurrentItem(with: nil)
                            return
                        }
                        if self.pool.count < self.maxPoolSize {
                            self.pool[id] = player
                        }
                        self.inFlight.remove(id)
                        // Wake waiters with the player (pool[id]) or directly with
                        // `player` when the pool was full — either way they get playback.
                        self.wakeWaiters(for: id, player: self.pool[id] ?? player)
                    }
                    continuation.resume()
                }
            }
        }
        inFlightTasks[id] = task
    }

    /// Resumes all continuations waiting for `id` and clears the waiter list.
    private func wakeWaiters(for id: String, player: AVPlayer?) {
        guard let waiters = pendingContinuations.removeValue(forKey: id) else { return }
        for cont in waiters.values { cont.resume(returning: player) }
    }

    /// Removes a player from the pool and cleans up its resources.
    private func evict(id: String) {
        // Cancel the loading task and clear the "wanted" signal so that the
        // PHImageManager callback discards its result if it fires after eviction.
        inFlightTasks[id]?.cancel()
        inFlightTasks.removeValue(forKey: id)
        inFlight.remove(id)
        // Wake any callers suspended in awaitPlayer so they fall back to their
        // own slow path instead of waiting indefinitely for a cancelled load.
        wakeWaiters(for: id, player: nil)
        guard let player = pool.removeValue(forKey: id) else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
