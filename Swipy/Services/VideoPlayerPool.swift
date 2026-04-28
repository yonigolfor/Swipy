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
//  - PhotoCardView calls `player(for:)` instead of requesting a new AVPlayerItem itself.
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

    // MARK: - Public API

    /// Returns an already-prepared AVPlayer for `asset` if one exists in the pool,
    /// or nil if it is still loading (the caller should show a placeholder).
    ///
    /// Always call `warmUp(for:)` first so the pool has time to prepare.
    func player(for asset: PHAsset) -> AVPlayer? {
        pool[asset.localIdentifier]
    }

    /// Pre-loads AVPlayerItems for the given assets in priority order.
    /// Call this every time the visible stack changes (after each swipe).
    /// Assets that are already in the pool or currently loading are skipped.
    ///
    /// - Parameter assets: Ordered list of upcoming PHAssets (videos only).
    ///   Pass at most `maxPoolSize` items; extras are ignored.
    func warmUp(for assets: [PHAsset]) {
        // Only warm up video assets we do not already have.
        let needed = assets
            .filter { $0.mediaType == .video }
            .prefix(maxPoolSize)
            .filter { pool[$0.localIdentifier] == nil && !inFlight.contains($0.localIdentifier) }

        for asset in needed {
            load(asset: asset)
        }

        // Evict players for assets that are no longer in the upcoming window
        // to keep memory usage bounded.
        let upcomingIDs = Set(assets.map { $0.localIdentifier })
        let staleIDs = pool.keys.filter { !upcomingIDs.contains($0) }
        for id in staleIDs {
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
            let ids = Array(pool.keys)
            ids.forEach { evict(id: $0) }
            inFlight.removeAll()
        }

    // MARK: - Private Helpers

    /// Loads an AVPlayerItem for `asset` on a background queue and stores
    /// the resulting AVPlayer in the pool on the main actor.
    private func load(asset: PHAsset) {
        let id = asset.localIdentifier
        inFlight.insert(id)

        let options = PHVideoRequestOptions()
        // .fastFormat: prioritises speed over quality for instant playback start.
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true

        // PHImageManager must be called from a background thread to avoid
        // blocking the main thread during the network/disk fetch.
        Task.detached(priority: .userInitiated) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                PHImageManager.default().requestPlayerItem(
                    forVideo: asset,
                    options: options
                ) { playerItem, _ in
                    guard let playerItem else {
                        Task { @MainActor in
                            self.inFlight.remove(id)
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
                        // Only store if pool is not already full with other assets.
                        if self.pool.count < self.maxPoolSize {
                            self.pool[id] = player
                        }
                        self.inFlight.remove(id)
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Removes a player from the pool and cleans up its resources.
    private func evict(id: String) {
        guard let player = pool.removeValue(forKey: id) else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
