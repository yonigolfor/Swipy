//
//  PhotoStackViewModel.swift
//  CleanSwipe
//
//  ViewModel עבור מסך ה-Swipe הראשי
//

import SwiftUI
import Photos
import Combine

@MainActor
class PhotoStackViewModel: NSObject, ObservableObject, @preconcurrency PHPhotoLibraryChangeObserver {
    // MARK: - Published Properties

    @Published var photoStack: [PhotoItem] = []
    @Published var reviewBin: [PhotoItem] = []
    @Published var currentFilter: FilterCategory = .all
    @Published var totalSpaceSaved: Int64 = 0
    @Published var isLoading = false
    /// Set to true after scanLocalUniverse completes with an empty photoStack,
    /// meaning the device has no locally-available photos (all on iCloud).
    /// Drives the "no offline items" empty state in VictoryView. Reset on deactivation.
    @Published private(set) var offlineFoundNoLocalItems: Bool = false
    @Published var categoryCounts: [FilterCategory: Int] = [:]
    @Published var hasPendingCountUpdate = false
    /// True while the expensive Phase 2 large video scan is running.
    @Published var isCountingLargeVideos = false

    /// IDs of assets whose full-res card image is currently stored in `imageCache`.
    /// @Published so views can react when a card becomes ready — used by the
    /// thumbnail-gate in Layer 3 and for observability in general.
    @Published var loadedImageIDs: Set<String> = []

    // MARK: - Offline Mode State

    enum OfflinePromptReason { case offline, constrained, slowNetwork }

    /// True when the stack is filtered to locally-available assets only.
    @Published var isOfflineMode: Bool = false
    /// Shown once per session when connectivity drops while offline mode is inactive.
    @Published var showOfflinePrompt: Bool = false
    /// Tells the banner which copy to render.
    @Published var offlinePromptReason: OfflinePromptReason = .offline

    private var hasPromptedOfflineThisSession = false
    private var hasPromptedSlowNetworkThisSession = false

    // Lie-fi detection: count iCloud timeouts; trigger prompt at 2 within 60 s.
    private var networkFailureCount = 0
    private var lastNetworkFailureDate: Date? = nil

    /// Background pre-fetch task. Cancelled on drag start, restarted on drag end.
    private var prefetchTask: Task<Void, Never>?
    /// Long-lived task that observes NetworkMonitorService.$isOnline.
    private var networkObserverTask: Task<Void, Never>?
    /// Long-lived task that observes NetworkMonitorService.$isConstrained.
    private var networkConstrainedObserverTask: Task<Void, Never>?
    /// Snapshot of photoStack taken the moment offline mode is activated.
    /// Restored on deactivation so the user returns to exact chronological position.
    private var preOfflineModeStack: [PhotoItem]? = nil
    /// fetchCursor saved at offline activation — restored alongside the stack snapshot
    /// so pagination picks up exactly where the user was before going offline.
    private var preOfflineFetchCursor: Int = 0

    // MARK: - Paywall State

    @Published var shouldShowPaywall = false

    var canSwipe: Bool {
        DailyLimitService.shared.canSwipe(isPremium: PremiumManager.shared.isPremium)
    }

    // MARK: - Shuffle Mode State

    /// True when the user has jumped to a random point in the timeline.
    @Published var isShuffleModeActive = false

    /// Bumped each time a shuffle, return-home, or offline-mode batch lands —
    /// the view observes this to trigger the card landing animation.
    @Published var shuffleBatchID = UUID()

    // MARK: - Onboarding Scan State
    @Published var onboardingPhotoCount = 0
    @Published var onboardingVideoCount = 0
    @Published var onboardingLargeVideoCount = 0
    @Published var onboardingScanComplete = false

    /// Count of snoozed items that match the current filter — drives the VictoryView CTA.
    @Published private(set) var pendingSnoozedCount: Int = 0

    /// In-memory cache for the expensive large video count.
    /// Persisted to Documents/largeVideoCount.json between app launches.
    private var cachedLargeVideoCount: Int? = nil

    /// Path to the small JSON cache file for large video count.
    private var cacheFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("largeVideoCount.json")
    }

    // MARK: - Image Cache

    /// App-level UIImage cache — allows PhotoCardView to receive images synchronously
    /// at init time, preventing any ProgressView flash on cards we've already seen.
    /// NSCache evicts automatically under memory pressure.
    let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8          // top-5 stack + early-precache buffer + 1 undo slot
        cache.totalCostLimit = 8 * 1024 * 1024  // ~8 MB ceiling
        return cache
    }()

    /// The target pixel size used when pre-loading images into the cache.
    /// Matches the approximate card size on screen — avoids decoding full-res assets.
    static let cacheTargetSize = CGSize(
        width: UIScreen.main.bounds.width - 40,
        height: UIScreen.main.bounds.height * 0.65
    )

    // MARK: - Snooze Queue

    private struct SnoozedPhoto {
        let item: PhotoItem
        let targetMilestone: Int
        let stagingMilestone: Int  // absolute counter at which item is inserted at index 2
        let snoozeCount: Int
    }

    /// Insertion depth for staged snooze items — equals SwipeStackView.cardStackSize - 1.
    /// The card enters at the bottom of the visible 3-card ZStack and naturally
    /// surfaces to index 0 after snoozeStageDepth more swipes, with no pop or teleport.
    private let snoozeStageDepth = 2

    private var snoozeQueue: [SnoozedPhoto] = []

    // MARK: - Private State

    /// IDs of every asset the user has already acted on (keep / delete / snooze).
    /// Persists across tab switches and filter changes within one app session.
    /// Cleared only when emptyTrash() is called for permanently-deleted items
    /// (their IDs can never come back anyway), or when the user explicitly
    /// undoes an action via restoreFromBin.
    private(set) var processedAssetIDs: Set<String> = []
    private var lastAction: (item: PhotoItem, action: SwipeAction)?
    /// Holds the cached image of the last swiped item so undo (shake) can
    /// restore it to the top card without a reload flash.
    private var lastSwipedImage: UIImage?

    // MARK: - Pagination State

    /// The index in the PHFetchResult where the next page load will resume.
    /// Reset to 0 whenever the filter changes or the library is refreshed.
    private var fetchCursor: Int = 0

    /// True while a background page-fetch is in flight — prevents concurrent fetches.
    private var isFetchingNextPage = false

    /// True while scanLocalUniverse is executing — prevents a second concurrent scan
    /// from corrupting offlineFetchCursor at the await Task.yield() suspension points.
    @Published private(set) var isScanning = false

    /// The index in the PHFetchResult where the next offline-mode local scan resumes.
    /// Separate from fetchCursor — the two universes (full library vs. local-only) are
    /// tracked independently so switching between modes never corrupts either cursor.
    private var offlineFetchCursor: Int = 0

    /// Saved cursor before a shuffle jump.
    /// In normal mode stores fetchCursor; in offline mode stores offlineFetchCursor.
    private var savedLinearCursor: Int = 0

    /// Snapshot of the photoStack taken at the moment the user entered shuffle mode.
    /// Restored on exit so the user returns to the exact card they left — no fetch needed.
    private var preShuffleStack: [PhotoItem]? = nil

    /// Number of PhotoItems to materialize in the initial load.
    private let initialPageSize = 50

    /// Number of PhotoItems to add per subsequent page.
    private let nextPageSize = 30

    /// When the stack drops to this many items, prefetch the next page.
    private let lowWatermark = 12

    // MARK: - Services

    private let photoService = PhotoLibraryService.shared
    private let hapticService = HapticService.shared
    private let persistence = PersistenceService.shared

    // MARK: - Computed Properties

    var topCard: PhotoItem? { photoStack.first }
    var remainingCount: Int { photoStack.count }

    var spaceSavedText: String {
        formatBytes(totalSpaceSaved)
    }

    /// Session MB for the gamified top bar. Uses the same 1 MiB = 1_048_576 bytes
    /// divisor as formatBytes so the displayed value stays consistent with spaceSavedText.
    var sessionSpaceSavedMB: Double {
        Double(totalSpaceSaved) / 1_048_576
    }

    var lifetimeSpaceSavedText: String {
        formatBytes(persistence.totalSpaceSavedLifetime)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 1024 {
            return String(format: "%.1f MB", megabytes)
        } else {
            return String(format: "%.2f GB", megabytes / 1024)
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        // Migration must run before any snooze data is read.
        persistence.migrateSnoozeDataIfNeeded()
        persistence.resetIfOld()

        // Only block IDs whose snooze is still active (milestone not yet reached).
        // Items that are already ripe are intentionally left out of processedAssetIDs
        // so they surface naturally via pagination — restoreSnoozedItems() will clean
        // up their persistence records and skip them from the in-memory queue.
        let counter = persistence.globalActionCounter
        let activeSnoozeIDs = Set(
            persistence.snoozedPhotos
                .filter { counter < $0.value.targetMilestone }
                .keys
        )
        self.processedAssetIDs = persistence.keptPhotoIDs.union(activeSnoozeIDs)

        // Offline mode is intentionally NOT restored across launches.
        // It's a session-level "I'm boarding a flight now" action, not a persistent setting.
        restoreBinFromDisk()
        restoreSnoozedItems()
        updatePendingSnoozedCount()
        loadPhotos()
        PHPhotoLibrary.shared().register(self)
        loadCachedLargeVideoCount()
        startNetworkObserver()
        // NOTE: refreshCategoryCounts() is NOT called here.
        // It is triggered lazily by SmartFiltersView.onAppear via .task.
    }

    /// Loads the cached large video count from disk if available.
    /// Called once at init so the count is available immediately.
    private func loadCachedLargeVideoCount() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let count = try? JSONDecoder().decode(Int.self, from: data) else { return }
        cachedLargeVideoCount = count
        categoryCounts[.largeVideos] = count
    }

    /// Saves the accurate large video count to disk for next launch.
    private func saveLargeVideoCountToCache(_ count: Int) {
        cachedLargeVideoCount = count
        if let data = try? JSONEncoder().encode(count) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    func refreshCategoryCounts() {
        Task.detached(priority: .userInitiated) {
            let service = PhotoLibraryService.shared

            if service.fetchResult == nil {
                service.fetchAllPhotos()
            }

            let processed = await self.processedAssetIDs

            // ── Phase 1: All categories in parallel (milliseconds) ────────
            // withTaskGroup runs each countFast() on a separate thread,
            // so total time = slowest single call instead of their sum.
            var fastCounts: [FilterCategory: Int] = await withTaskGroup(
                of: (FilterCategory, Int).self
            ) { group in
                for category in FilterCategory.allCases {
                    group.addTask {
                        (category, service.countFast(for: category, excluding: processed))
                    }
                }
                var results: [FilterCategory: Int] = [:]
                for await (category, count) in group {
                    results[category] = count
                }
                return results
            }

            // Overlay cached large-video count so the user never waits for Phase 2.
            let cached = await self.cachedLargeVideoCount
            if let cached {
                fastCounts[.largeVideos] = cached
            }

            await MainActor.run {
                withAnimation { self.categoryCounts = fastCounts }
                // Show smart-shimmer indicator while Phase 2 verifies the count.
                // If there is no cached value (first launch) the badge itself is nil
                // → the view falls back to the full shimmer placeholder.
                self.isCountingLargeVideos = true
            }

            // ── Phase 2: Accurate large-video count in background ─────────
            let accurateLargeVideoCount = await Task.detached(priority: .background) {
                service.count(for: .largeVideos, excluding: processed)
            }.value

            await self.saveLargeVideoCountToCache(accurateLargeVideoCount)

            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    self.categoryCounts[.largeVideos] = accurateLargeVideoCount
                    self.isCountingLargeVideos = false
                }
            }
        }
    }

    // MARK: - Onboarding Scan

    func startOnboardingScan() {
        onboardingPhotoCount = 0
        onboardingVideoCount = 0
        onboardingLargeVideoCount = 0
        onboardingScanComplete = false

        Task.detached(priority: .utility) {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run { withAnimation { self.onboardingScanComplete = true } }
                return
            }

            let allPhotos = PHAsset.fetchAssets(with: .image, options: PHFetchOptions())
            let allVideos = PHAsset.fetchAssets(with: .video, options: PHFetchOptions())

            let pCount = allPhotos.count
            let vCount = allVideos.count

            // Set counts immediately — animation is triggered by the Scan screen on appear.
            await MainActor.run {
                self.onboardingPhotoCount = pCount
                self.onboardingVideoCount = vCount
            }

            // Phase 1 — instant estimate: NSPredicate on Photos DB, completes in <100ms.
            // Videos > 10s are very likely to exceed 50 MB at typical iPhone quality.
            // Stops the spinner immediately so the user sees a number right away.
            let quickOptions = PHFetchOptions()
            quickOptions.predicate = NSPredicate(
                format: "mediaType == %d AND duration > 10",
                PHAssetMediaType.video.rawValue
            )
            let quickEstimate = PHAsset.fetchAssets(with: quickOptions).count
            await MainActor.run { withAnimation { self.onboardingLargeVideoCount = quickEstimate } }

            // Phase 2 — accurate fileSize scan: concurrent, duration >= 3 s to skip tiny clips.
            // PHFetchResult is documented thread-safe; each iteration writes to a distinct index.
            let candidateOptions = PHFetchOptions()
            candidateOptions.predicate = NSPredicate(
                format: "mediaType == %d AND duration >= 3",
                PHAssetMediaType.video.rawValue
            )
            let candidates = PHAsset.fetchAssets(with: candidateOptions)
            let n = candidates.count

            var hits = [UInt8](repeating: 0, count: max(1, n))
            DispatchQueue.concurrentPerform(iterations: n) { i in
                let size = PHAssetResource.assetResources(for: candidates.object(at: i))
                    .first.flatMap { $0.value(forKey: "fileSize") as? Int64 } ?? 0
                if size > PhotoLibraryService.largeVideoThresholdBytes { hits[i] = 1 }
            }
            let finalLarge = hits.reduce(0) { $0 + Int($1) }

            await MainActor.run {
                withAnimation(.spring(response: 0.6)) { self.onboardingLargeVideoCount = finalLarge }
                withAnimation { self.onboardingScanComplete = true }
            }
        }
    }

    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            // Library changed — invalidate large video cache so Phase 2
            // runs fresh and the user sees accurate counts.
            self.cachedLargeVideoCount = nil
            try? FileManager.default.removeItem(at: self.cacheFileURL)

            guard let oldResult = self.photoService.fetchResult else {
                // No prior fetch — do a full initial load.
                self.photoService.fetchAllPhotos()
                self.resetAndLoad(filter: self.currentFilter)
                return
            }

            // Refresh the fetch result (no enumeration — O(1) index update).
            let newResult = self.photoService.fetchAllPhotos()

            guard let details = changeInstance.changeDetails(for: oldResult) else { return }

            // Only act on insertions.
            guard details.hasIncrementalChanges,
                  let insertedIndexes = details.insertedIndexes,
                  !insertedIndexes.isEmpty else { return }

            // Newly inserted assets arrive at the top (newest-first sort).
            // Collect only those not already seen.
            let existingIDs = Set(self.photoStack.map { $0.id })
            var newItems: [PhotoItem] = []

            insertedIndexes.forEach { idx in
                let asset = newResult.object(at: idx)
                guard !self.processedAssetIDs.contains(asset.localIdentifier),
                      !existingIDs.contains(asset.localIdentifier) else { return }
                newItems.append(PhotoItem(asset: asset))
            }

            guard !newItems.isEmpty else { return }
            self.photoStack.insert(contentsOf: newItems, at: 0)

            // Burst detection — fires only when app is in foreground
            NotificationScheduler.shared.checkBurstFromLibraryChange(insertedCount: insertedIndexes.count)
        }
    }

    // MARK: - Bin Restoration

    private func restoreBinFromDisk() {
        let savedIDs = persistence.reviewBinIDs
        guard !savedIDs.isEmpty else { return }
        // Targeted fetch — only the IDs we actually need, not the full library.
        let assetMap = photoService.fetchAssets(forIDs: savedIDs)
        let items = savedIDs.compactMap { id -> PhotoItem? in
            guard let asset = assetMap[id] else { return nil }
            return PhotoItem(asset: asset)
        }
        self.reviewBin = items
        self.totalSpaceSaved = persistence.reviewBinSpaceSaved
        items.forEach { processedAssetIDs.insert($0.id) }
    }

    /// Reconstructs the in-memory snooze queue from persisted SnoozedPhotoRecords.
    /// Called once at init, after processedAssetIDs is built.
    ///
    /// - Ready items (globalActionCounter >= targetMilestone): cleared from persistence
    ///   so they surface naturally via normal pagination on this launch.
    /// - Active items (globalActionCounter < targetMilestone): added to snoozeQueue
    ///   so stageSnoozedItemsIfReady() can stage them when their milestone is reached.
    /// - Missing assets (deleted from library): cleared from persistence silently.
    private func restoreSnoozedItems() {
        let snoozedDict = persistence.snoozedPhotos
        guard !snoozedDict.isEmpty else { return }
        let counter = persistence.globalActionCounter
        let assetMap = photoService.fetchAssets(forIDs: Array(snoozedDict.keys))

        for (id, record) in snoozedDict {
            guard let asset = assetMap[id] else {
                // Asset was deleted from the library while the app was closed.
                persistence.clearSnoozedID(id)
                processedAssetIDs.remove(id)
                continue
            }
            if counter >= record.targetMilestone {
                // Milestone already passed — let normal pagination surface this item.
                // The ID was never added to processedAssetIDs in init (see above).
                persistence.clearSnoozedID(id)
            } else {
                // Still active — keep in queue; ID is already in processedAssetIDs.
                snoozeQueue.append(SnoozedPhoto(
                    item: PhotoItem(asset: asset),
                    targetMilestone: record.targetMilestone,
                    stagingMilestone: record.stagingMilestone,
                    snoozeCount: record.snoozeCount
                ))
            }
        }
    }

    // MARK: - Data Loading

    /// Loads photos for the given filter, always excluding already-processed assets.
    /// Only the first `initialPageSize` items are materialised up front; more are
    /// fetched lazily as the user swipes (see `loadNextPageIfNeeded`).
    func loadPhotos(filter: FilterCategory = .all) {
        resetAndLoad(filter: filter)
    }

    /// Resets the cursor and kicks off an initial page fetch for `filter`.
    private func resetAndLoad(filter: FilterCategory) {
        isLoading = true
        currentFilter = filter
        updatePendingSnoozedCount()
        fetchCursor = 0
        offlineFetchCursor = 0
        isFetchingNextPage = false
        loadedImageIDs = []
        // Reset shuffle so stale state doesn't leak across filter changes or tab refreshes.
        isShuffleModeActive = false
        savedLinearCursor = 0
        preShuffleStack = nil

        Task {
            if photoService.fetchResult == nil { photoService.fetchAllPhotos() }

            // Offline mode owns its own universe — scan locally-available assets
            // from the start of the library regardless of filter.
            if isOfflineMode {
                photoStack = []
                await scanLocalUniverse(targetCount: initialPageSize, batchSize: 150)
                stageSnoozedItemsIfReady()
                isLoading = false
                if categoryCounts.isEmpty { refreshCategoryCounts() }
                return
            }

            // largeVideos: no pre-fetch needed — fetchPageOfAssets already does the
            // fileSize check inline, so a wasted initial scan would discard real results.
            // Stream directly from cursor 0 via scanUntilFull.
            if filter == .largeVideos {
                await MainActor.run { self.photoStack = []; self.isLoading = true }
                await scanUntilFull(filter: .largeVideos, targetCount: 15, batchSize: 300)
                await MainActor.run {
                    self.stageSnoozedItemsIfReady()
                    self.isLoading = false
                }
                if self.categoryCounts.isEmpty { self.refreshCategoryCounts() }
                return
            }

            let pageSize: Int
            switch filter {
            case .burstPhotos:  pageSize = 500
            case .blurryPhotos: pageSize = 200
            default:            pageSize = initialPageSize
            }

            let (rawItems, nextIdx) = photoService.fetchPageOfAssets(
                for: filter,
                startIndex: 0,
                pageSize: pageSize,
                excluding: processedAssetIDs
            )

            self.fetchCursor = nextIdx ?? photoService.totalAssetCount

            if filter == .blurryPhotos || filter == .burstPhotos {
                await MainActor.run {
                    self.photoStack = []
                    self.isLoading = true
                }
                await scanUntilFull(filter: filter, targetCount: 15, batchSize: 300)
                await MainActor.run {
                    self.stageSnoozedItemsIfReady()
                    self.isLoading = false
                }
                if self.categoryCounts.isEmpty { self.refreshCategoryCounts() }
                return
            }

            print("📸 initial page: \(rawItems.count) items, cursor: \(self.fetchCursor)/\(self.photoService.totalAssetCount)")

            await MainActor.run {
                // Kick off pool warm-up BEFORE publishing photoStack so the pool
                // gets a head start over PhotoCardView.onAppear — eliminates the
                // first-video freeze on initial load.
                let firstVideoAssets = rawItems.prefix(3)
                    .filter { $0.isVideo }
                    .map { $0.asset }
                if !firstVideoAssets.isEmpty {
                    VideoPlayerPool.shared.warmUp(for: firstVideoAssets)
                }

                self.photoStack = rawItems
                self.stageSnoozedItemsIfReady()
                self.isLoading = false
                if !self.photoStack.isEmpty { self.precacheNextImages() }
                if self.categoryCounts.isEmpty { self.refreshCategoryCounts() }
            }
        }
    }

    // MARK: - Shuffle Mode

    /// User-triggered: jump to a random point in the timeline.
    /// In offline mode, jumps to a random position within the local-only universe.
    func activateShuffle() {
        guard photoService.totalAssetCount > 0 else { return }
        // Save cursor and snapshot only on first activation — re-shuffling must not
        // overwrite the original linear position the user will return to on reset.
        if !isShuffleModeActive {
            savedLinearCursor = isOfflineMode ? offlineFetchCursor : fetchCursor
            preShuffleStack = photoStack
        }
        isShuffleModeActive = true
        isLoading = true
        isFetchingNextPage = false

        let total = photoService.totalAssetCount
        let randomStart = Int.random(in: 0..<total)

        Task {
            if isOfflineMode {
                // Jump to a random position in the full library but scan forward
                // collecting only locally-available assets — no iCloud downloads.
                offlineFetchCursor = randomStart
                photoStack = []
                await scanLocalUniverse(targetCount: initialPageSize, batchSize: 200, wrapAround: true)
                stageSnoozedItemsIfReady()
                isLoading = false
                shuffleBatchID = UUID()
                if !photoStack.isEmpty { precacheNextImages() }
            } else {
                let (items, nextIdx) = photoService.fetchPageOfAssets(
                    for: currentFilter,
                    startIndex: randomStart,
                    pageSize: initialPageSize,
                    excluding: processedAssetIDs
                )
                await MainActor.run {
                    self.fetchCursor = nextIdx ?? self.photoService.totalAssetCount
                    self.photoStack = items
                    self.stageSnoozedItemsIfReady()
                    self.isLoading = false
                    self.shuffleBatchID = UUID()
                    if !self.photoStack.isEmpty { self.precacheNextImages() }
                }
            }
        }
    }

    /// User-triggered: exit shuffle and return to the exact stack the user left.
    func deactivateShuffle() {
        isShuffleModeActive = false
        isFetchingNextPage = false

        let restored = restoreLinearStack()
        photoStack = restored
        stageSnoozedItemsIfReady()
        preShuffleStack = nil
        shuffleBatchID = UUID()

        if isOfflineMode {
            // Restore the offline universe cursor to where it was before the shuffle.
            offlineFetchCursor = savedLinearCursor
            // Keep preOfflineModeStack in sync: it now points to the current
            // (post-shuffle-deactivation) stack, so deactivating offline later
            // restores to this correct chronological position, not a stale shuffle batch.
            preOfflineModeStack = photoStack
            if !photoStack.isEmpty { precacheNextImages() }
            // Refill from the restored offline cursor if the snapshot was depleted.
            Task { await scanLocalUniverse() }
        } else {
            fetchCursor = savedLinearCursor
            if !photoStack.isEmpty { precacheNextImages() }
        }
    }

    /// Returns the stack to restore after exiting shuffle mode.
    /// Uses the pre-shuffle snapshot when available, filtered through processedAssetIDs
    /// to drop any items the user actioned during the shuffle session.
    /// Falls back to an empty array (loadNextPageIfNeeded will refill from fetchCursor).
    private func restoreLinearStack() -> [PhotoItem] {
        guard let snapshot = preShuffleStack else { return [] }
        return snapshot.filter { !processedAssetIDs.contains($0.id) }
    }

    /// Auto-triggered: the shuffle segment reached the end of the library.
    /// Restores the pre-shuffle stack so the user lands back where they left off.
    private func shuffleExhausted() {
        isShuffleModeActive = false
        isFetchingNextPage = false

        let restored = restoreLinearStack()
        photoStack = restored
        stageSnoozedItemsIfReady()
        preShuffleStack = nil

        if isOfflineMode {
            offlineFetchCursor = savedLinearCursor
            preOfflineModeStack = photoStack
        } else {
            fetchCursor = savedLinearCursor
        }

        if !photoStack.isEmpty { precacheNextImages() }
    }

    /// Appends the next page of assets to `photoStack` when the stack is running low.
    private func loadNextPageIfNeeded() {
        guard !isFetchingNextPage,
              photoStack.count <= lowWatermark else { return }

        // Offline mode: continue scanning the local universe from where we left off.
        // Guard against empty stack — once the user has swiped everything, we show
        // the offline VictoryView rather than silently refilling behind it.
        if isOfflineMode {
            guard offlineFetchCursor < photoService.totalAssetCount,
                  !photoStack.isEmpty else { return }
            Task { await scanLocalUniverse(targetCount: photoStack.count + nextPageSize) }
            return
        }

        // Shuffle segment exhausted — silently return to the linear stream.
        if isShuffleModeActive && fetchCursor >= photoService.totalAssetCount {
            shuffleExhausted()
            return
        }

        guard fetchCursor < photoService.totalAssetCount else { return }

        if currentFilter == .blurryPhotos || currentFilter == .burstPhotos || currentFilter == .largeVideos {
            Task { await scanUntilFull(filter: currentFilter) }
            return
        }

        isFetchingNextPage = true

        Task {
            let (rawItems, nextIdx) = photoService.fetchPageOfAssets(
                for: currentFilter,
                startIndex: fetchCursor,
                pageSize: nextPageSize,
                excluding: processedAssetIDs
            )

            let newFetchCursor = nextIdx ?? photoService.totalAssetCount

            print("📸 next page: \(rawItems.count) items, cursor: \(newFetchCursor)/\(self.photoService.totalAssetCount)")

            await MainActor.run {
                if !rawItems.isEmpty {
                    self.photoStack.append(contentsOf: rawItems)
                    self.photoService.startCaching(
                        for: rawItems,
                        targetSize: CGSize(width: 400, height: 600)
                    )
                }
                self.fetchCursor = newFetchCursor
                self.isFetchingNextPage = false
            }
        }
    }

    /// Called on SwipeStackView.onAppear — re-fetches from library but keeps
    /// the processed-IDs set intact so swiped photos never reappear.
    func refreshPhotos() {
        photoService.fetchAllPhotos()
        loadPhotos(filter: currentFilter)
    }

    /// Pauses all pooled video players. Call when the user leaves the Swipe tab.
    func pauseVideoPool() {
        AudioSessionManager.shared.deactivate()
        Task { await VideoPlayerPool.shared.pauseAll() }
    }

    func count(for category: FilterCategory) -> Int {
        photoService.count(for: category, excluding: processedAssetIDs)
    }

    // MARK: - Swipe Actions

    /// Swipe Right — Keep
    func keepPhoto() {
        guard let topCard = photoStack.first else { return }
        lastSwipedImage = imageCache.object(forKey: topCard.id as NSString)
        processedAssetIDs.insert(topCard.id)
        persistence.saveKeptID(topCard.id)
        persistence.clearSnoozedID(topCard.id)
        self.lastAction = (topCard, .keep)
        photoStack.removeFirst()
        hasPendingCountUpdate = true
        OfflineCacheService.shared.evict(for: topCard.id)
        DailyLimitService.shared.recordSwipe()
        hapticService.keep()
        persistence.globalActionCounter += 1  // increment before milestone check
        stageSnoozedItemsIfReady()
        precacheNextImages()
        loadNextPageIfNeeded()
    }

    /// Swipe Left — Delete (moves to Review Bin)
    func deletePhoto() {
        guard let topCard = photoStack.first else { return }
        lastSwipedImage = imageCache.object(forKey: topCard.id as NSString)
        processedAssetIDs.insert(topCard.id)
        persistence.clearSnoozedID(topCard.id)
        self.lastAction = (topCard, .delete)
        photoStack.removeFirst()
        hasPendingCountUpdate = true
        reviewBin.append(topCard)
        totalSpaceSaved += topCard.fileSize
        OfflineCacheService.shared.evict(for: topCard.id)
        DailyLimitService.shared.recordSwipe()
        hapticService.delete()
        persistence.globalActionCounter += 1  // increment before milestone check
        stageSnoozedItemsIfReady()
        precacheNextImages()
        saveBinToDisk()
        loadNextPageIfNeeded()
    }

    /// Swipe Up — Snooze (re-inserts into stack after N keep/delete swipes, exponential backoff).
    /// Uses an absolute targetMilestone so the delay survives force-quit and app relaunches.
    func snoozePhoto() {
        guard let topCard = photoStack.first else { return }
        lastSwipedImage = imageCache.object(forKey: topCard.id as NSString)
        // Block from pagination until the staging milestone is reached (removed by
        // stageSnoozedItemsIfReady on staging, or by undoLastAction on undo).
        processedAssetIDs.insert(topCard.id)
        self.lastAction = (topCard, .snooze)
        photoStack.removeFirst()
        hasPendingCountUpdate = true
        OfflineCacheService.shared.evict(for: topCard.id)

        let existingRecord = persistence.snoozedPhotos[topCard.id]
        let newCount = (existingRecord?.snoozeCount ?? 0) + 1
        let backoff: Int = switch newCount {
        case 1:  50
        case 2:  100
        default: 150
        }
        let milestone = persistence.globalActionCounter + backoff
        let staging = milestone - snoozeStageDepth

        persistence.snoozedPhotos[topCard.id] = PersistenceService.SnoozedPhotoRecord(
            snoozeCount: newCount,
            targetMilestone: milestone,
            stagingMilestone: staging
        )
        snoozeQueue.append(SnoozedPhoto(
            item: topCard,
            targetMilestone: milestone,
            stagingMilestone: staging,
            snoozeCount: newCount
        ))
        updatePendingSnoozedCount()

        hapticService.snooze()
        precacheNextImages()
        loadNextPageIfNeeded()
    }

    /// Undo — restores the last deleted photo back to the top of the stack
    func undoLastAction() {
        guard let last = lastAction else { return }
        lastAction = nil
        let item = last.item

        // Restore the cached image so the undo card appears instantly.
        if let img = lastSwipedImage {
            imageCache.setObject(img, forKey: item.id as NSString,
                                 cost: Int(PhotoStackViewModel.cacheTargetSize.width *
                                           PhotoStackViewModel.cacheTargetSize.height * 4))
            activeCacheIDs.insert(item.id)
            loadedImageIDs.insert(item.id)
            lastSwipedImage = nil
        }

        processedAssetIDs.remove(item.id)
        persistence.removeKeptID(item.id)
        photoStack.insert(item, at: 0)
        hasPendingCountUpdate = true

        if last.action == .delete {
            reviewBin.removeAll { $0.id == item.id }
            totalSpaceSaved -= item.fileSize
            saveBinToDisk()
        }

        if last.action == .snooze {
            // Remove entirely — item is back in the active stack and no longer snoozed.
            // Keeping a stale record with a future targetMilestone would re-block it on
            // the next launch. snoozeCount resets to 0 so the next snooze starts fresh.
            snoozeQueue.removeAll { $0.item.id == item.id }
            persistence.clearSnoozedID(item.id)
            updatePendingSnoozedCount()
        }

        hapticService.undo()
    }

    // MARK: - Review Bin Actions

    /// Restore a single item from the bin back to the swipe stack
    func restoreFromBin(_ item: PhotoItem) {
        guard let index = reviewBin.firstIndex(of: item) else { return }
        reviewBin.remove(at: index)
        processedAssetIDs.remove(item.id)
        persistence.removeKeptID(item.id)
        totalSpaceSaved -= item.fileSize
        hapticService.selection()
        saveBinToDisk()
    }

    /// Permanently delete everything in the Review Bin
    func emptyTrash() async throws {
        let assetsToDelete = reviewBin.map { $0.asset }
        let currentSaved = totalSpaceSaved

        // Drain the video pool BEFORE deleting assets — AVPlayerItems hold
        // strong references to PHAssets and will crash if accessed after deletion.
        VideoPlayerPool.shared.drainAll()
        hapticService.emptyTrash()
        try await photoService.deleteAssets(assetsToDelete)

        // Permanently-deleted IDs stay in processedAssetIDs — they can never
        // come back from the library anyway.
        await MainActor.run {
            persistence.totalSpaceSavedLifetime += currentSaved
            reviewBin.removeAll()
            totalSpaceSaved = 0
            saveBinToDisk()
        }
    }

    /// Resets all decisions (kept, snoozed) to start over
    func resetProgress() {
        persistence.keptPhotoIDs = []
        persistence.snoozedPhotos = [:]
        snoozeQueue = []
        processedAssetIDs = []
        updatePendingSnoozedCount()
        loadPhotos(filter: currentFilter)
    }

    // MARK: - Dispatch Helper

    func performAction(_ action: SwipeAction) {
        switch action {
        case .keep:   keepPhoto()
        case .delete: deletePhoto()
        case .snooze: snoozePhoto()
        case .undo:   undoLastAction()
        }
    }

    // MARK: - Offline Mode

    func activateOfflineMode() {
        networkFailureCount = 0
        lastNetworkFailureDate = nil
        preOfflineModeStack = photoStack   // snapshot for instant restoration on exit
        preOfflineFetchCursor = fetchCursor
        isOfflineMode = true
        offlineFetchCursor = 0
        PhotoLibraryService.shared.isOfflineMode = true
        cancelPrefetch()
        // If shuffle was active, reset it cleanly — shuffle and offline are mutually exclusive.
        isShuffleModeActive = false
        preShuffleStack = nil
        // Scan the full library for locally-available assets — owns its own universe.
        Task {
            photoStack = []
            isLoading = true
            await scanLocalUniverse(targetCount: initialPageSize, batchSize: 150)
            offlineFoundNoLocalItems = photoStack.isEmpty
            stageSnoozedItemsIfReady()
            isLoading = false
            // Landing animation is triggered in SwipeStackView by onChange(of: isLoading)
        }
    }

    func deactivateOfflineMode() {
        networkFailureCount = 0
        lastNetworkFailureDate = nil
        isOfflineMode = false
        PhotoLibraryService.shared.isOfflineMode = false

        // Shared reset state.
        offlineFoundNoLocalItems = false
        currentFilter = .all
        offlineFetchCursor = 0
        isFetchingNextPage = false
        loadedImageIDs = []
        isShuffleModeActive = false
        savedLinearCursor = 0
        preShuffleStack = nil
        isLoading = true

        // Try to restore the pre-offline snapshot first — instant, no PHFetchResult scan.
        let snapshot = preOfflineModeStack?.filter { !processedAssetIDs.contains($0.id) } ?? []
        preOfflineModeStack = nil

        Task {
            if !snapshot.isEmpty {
                // Fast path: show the exact cards the user had queued before going offline.
                // Wrapped in Task so isLoading true→false crosses a run-loop boundary,
                // allowing onChange(of: isLoading) in SwipeStackView to fire.
                fetchCursor = preOfflineFetchCursor
                let firstVideoAssets = snapshot.prefix(3).filter { $0.isVideo }.map { $0.asset }
                if !firstVideoAssets.isEmpty { VideoPlayerPool.shared.warmUp(for: firstVideoAssets) }
                photoStack = snapshot
                stageSnoozedItemsIfReady()
                isLoading = false
                precacheNextImages()
                startBackgroundPrefetch()
                if categoryCounts.isEmpty { refreshCategoryCounts() }
            } else {
                // Slow path: snapshot exhausted (user swiped everything before going offline).
                // Fresh fetch from index 0 — shows newest items, same as first app launch.
                fetchCursor = 0
                if photoService.fetchResult == nil { photoService.fetchAllPhotos() }
                let (rawItems, nextIdx) = photoService.fetchPageOfAssets(
                    for: .all,
                    startIndex: 0,
                    pageSize: initialPageSize,
                    excluding: processedAssetIDs
                )
                fetchCursor = nextIdx ?? photoService.totalAssetCount
                let firstVideoAssets = rawItems.prefix(3).filter { $0.isVideo }.map { $0.asset }
                if !firstVideoAssets.isEmpty { VideoPlayerPool.shared.warmUp(for: firstVideoAssets) }
                photoStack = rawItems
                stageSnoozedItemsIfReady()
                isLoading = false
                if !photoStack.isEmpty { precacheNextImages() }
                if categoryCounts.isEmpty { refreshCategoryCounts() }
                startBackgroundPrefetch()
            }
        }
        // Landing animation is triggered in SwipeStackView by onChange(of: isLoading).
    }

    func dismissOfflinePrompt() {
        showOfflinePrompt = false
    }

    // MARK: - Background Pre-fetch

    /// Starts silently downloading the next 20 images to disk while on WiFi.
    /// Runs at .utility priority — swipe gestures (.userInteractive) always win CPU.
    /// No-op on cellular, Low Data Mode, or when offline mode is already active.
    func startBackgroundPrefetch() {
        cancelPrefetch()
        guard !isOfflineMode else { return }
        let network = NetworkMonitorService.shared
        guard network.isOnline && !network.isExpensive && !network.isConstrained else { return }

        let items = Array(photoStack.dropFirst().prefix(20)).filter { !$0.isVideo }
        guard !items.isEmpty else { return }
        let targetSize = PhotoStackViewModel.cacheTargetSize

        prefetchTask = Task.detached(priority: .utility) { [weak self] in
            for item in items {
                guard !Task.isCancelled else { break }
                // Skip if already in NSCache
                let inMemory = await MainActor.run { [weak self] in
                    self?.imageCache.object(forKey: item.id as NSString) != nil
                } ?? false
                if inMemory { continue }
                // Skip if already on disk
                if OfflineCacheService.shared.retrieve(for: item.id) != nil { continue }

                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    PhotoLibraryService.shared.loadImage(
                        for: item.asset,
                        targetSize: targetSize,
                        forceNetworkAccess: true   // always allow download during pre-fetch
                    ) { image in
                        if let image {
                            OfflineCacheService.shared.store(image: image, for: item.id)
                        }
                        cont.resume()
                    }
                }
                // Yield between each fetch so swipe gestures are never starved
                await Task.yield()
            }
        }
    }

    func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    func resumePrefetch() {
        startBackgroundPrefetch()
    }

    // MARK: - Network Observer

    /// Observes connectivity and auto-prompts once per session when going offline.
    private func startNetworkObserver() {
        // ── isOnline observer ────────────────────────────────────────────────
        networkObserverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var isFirst = true
            for await isOnline in NetworkMonitorService.shared.$isOnline.values {
                if isFirst { isFirst = false; continue }
                if !isOnline {
                    cancelPrefetch()
                    if !isOfflineMode && !hasPromptedOfflineThisSession {
                        offlinePromptReason = .offline
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                            showOfflinePrompt = true
                        }
                        hasPromptedOfflineThisSession = true
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 8_000_000_000)
                            withAnimation(.easeOut(duration: 0.3)) { self?.showOfflinePrompt = false }
                        }
                    }
                } else if !isOfflineMode {
                    startBackgroundPrefetch()
                }
            }
        }

        // ── isConstrained observer (Low Data Mode) ───────────────────────────
        networkConstrainedObserverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var isFirst = true
            for await isConstrained in NetworkMonitorService.shared.$isConstrained.values {
                if isFirst { isFirst = false; continue }
                guard isConstrained && !isOfflineMode && !hasPromptedOfflineThisSession else { continue }
                offlinePromptReason = .constrained
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    showOfflinePrompt = true
                }
                hasPromptedOfflineThisSession = true
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    withAnimation(.easeOut(duration: 0.3)) { self?.showOfflinePrompt = false }
                }
            }
        }
    }

    /// Called each time an iCloud image request times out (Lie-fi detection).
    /// Triggers the slow-network prompt after 2 failures within a 60-second window.
    func recordNetworkFailure() {
        let now = Date()
        if let last = lastNetworkFailureDate, now.timeIntervalSince(last) > 60 {
            networkFailureCount = 0
        }
        lastNetworkFailureDate = now
        networkFailureCount += 1

        guard networkFailureCount >= 2,
              !isOfflineMode,
              !hasPromptedSlowNetworkThisSession else { return }

        hasPromptedSlowNetworkThisSession = true
        offlinePromptReason = .slowNetwork
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            showOfflinePrompt = true
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            withAnimation(.easeOut(duration: 0.3)) { self?.showOfflinePrompt = false }
        }
    }

    // MARK: - Private Helpers

    // MARK: - Local Universe Scanner

    /// Scans the full PHFetchResult for locally-available assets, streaming results
    /// to photoStack as they are found. Used exclusively when isOfflineMode == true.
    ///
    /// wrapAround: when true (shuffle) — if the scan reaches the end of the library
    /// without finding enough local photos, it wraps to index 0 and continues up to
    /// the original start position. Prevents the empty-screen bug when a random
    /// shuffle start lands near the end of a mostly-iCloud library.
    private func scanLocalUniverse(
        targetCount: Int = 15,
        batchSize: Int = 150,
        wrapAround: Bool = false
    ) async {
        guard !isScanning else { isLoading = false; return }
        isScanning = true
        defer { isScanning = false }
        guard let fetchResult = photoService.fetchResult else { isLoading = false; return }
        let service = PhotoLibraryService.shared
        let diskCache = OfflineCacheService.shared
        let total = fetchResult.count
        guard total > 0 else { isLoading = false; return }

        let initialCursor = offlineFetchCursor
        var hasWrapped = false

        // Absolute stop: counts every library index visited across all iterations.
        // When totalScanned == total we've seen every asset exactly once —
        // no local photos exist in the library, exit unconditionally.
        var totalScanned = 0

        // Deduplication set built once and grown incrementally.
        // Avoids recomputing Set(photoStack.map{$0.id}) inside every iteration
        // and stays correct across the wrap-around boundary.
        var seenIDs: Set<String> = Set(photoStack.map { $0.id })

        // Disk cache index — built once via a single directory listing.
        // Replaces the previous per-item diskCache.retrieve() which issued a
        // Data(contentsOf:) syscall for every non-local asset (~20-40s on 20k items).
        // The Set is a value type: captured by CoW reference inside Task.detached,
        // no copies occur as long as we never mutate it. Freed when the scan returns.
        let cachedIDs = diskCache.cachedAssetIDSet()

        while photoStack.count < targetCount {
            guard isOfflineMode else { break }

            // Absolute termination guard — full library scanned, nothing local found
            guard totalScanned < total else { break }

            if offlineFetchCursor >= total {
                if wrapAround && !hasWrapped && initialCursor > 0 {
                    hasWrapped = true
                    offlineFetchCursor = 0
                } else {
                    break
                }
            }

            // Wrap-around stop: back to original start position
            if hasWrapped && offlineFetchCursor >= initialCursor { break }

            let start = offlineFetchCursor
            let upperBound = hasWrapped ? initialCursor : total
            let end = min(start + batchSize, upperBound)
            let processed = processedAssetIDs
            let snapshot = seenIDs  // value-copy for the detached task

            let batch = await Task.detached(priority: .userInitiated) {
                var result: [PhotoItem] = []
                for i in start..<end {
                    let asset = fetchResult.object(at: i)
                    guard !processed.contains(asset.localIdentifier),
                          !snapshot.contains(asset.localIdentifier) else { continue }
                    // Sanitization must match fileURL(for:) in OfflineCacheService:
                    // both replace "/" with "_". No disk I/O — O(1) Set lookup.
                    let sanitizedID = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
                    let isLocal = service.isLocallyAvailable(asset) || cachedIDs.contains(sanitizedID)
                    if isLocal { result.append(PhotoItem(asset: asset)) }
                }
                return result
            }.value

            totalScanned += end - start
            offlineFetchCursor = end

            if !batch.isEmpty {
                for item in batch { seenIDs.insert(item.id) }
                photoStack.append(contentsOf: batch)
                if isLoading { isLoading = false }
                precacheNextImages()
            }

            await Task.yield()
        }

        isLoading = false
    }

    /// Scans items for blur and returns only blurry ones.
    /// Processes images concurrently for maximum speed.
    private func filterBlurry(_ items: [PhotoItem]) async -> [PhotoItem] {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                var result: [PhotoItem] = []
                let group = DispatchGroup()
                let lock = NSLock()

                for item in items {
                    guard !item.isVideo else { continue }
                    group.enter()
                    PhotoLibraryService.shared.loadImage(
                        for: item.asset,
                        targetSize: CGSize(width: 200, height: 200)
                    ) { image in
                        defer { group.leave() }
                        guard let image else { return }
                        if BlurDetector.shared.isBlurry(image) {
                            lock.lock()
                            result.append(item)
                            lock.unlock()
                        }
                    }
                }

                group.notify(queue: .main) {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Continuously scans the library until it finds at least `targetCount`
    /// items matching the filter, or exhausts the entire library.
    /// This powers the "refill mechanism" — the user never sees an empty
    /// stack while there are still unscanned assets in the library.
    /// Continuously scans the library and streams results to the UI
    /// one asset at a time as they are found — no waiting for full batches.
    /// The user sees the first card appear immediately after it is found.
    private func scanUntilFull(
        filter: FilterCategory,
        targetCount: Int = 15,
        batchSize: Int = 100
    ) async {
        guard filter == .blurryPhotos || filter == .burstPhotos || filter == .largeVideos else { return }

        while photoStack.count < targetCount,
              fetchCursor < photoService.totalAssetCount {

            let cursor = fetchCursor
            let processed = processedAssetIDs

            let (rawItems, nextIdx) = photoService.fetchPageOfAssets(
                for: filter,
                startIndex: cursor,
                pageSize: batchSize,
                excluding: processed
            )

            let newCursor = nextIdx ?? photoService.totalAssetCount
            await MainActor.run { self.fetchCursor = newCursor }

            if filter == .blurryPhotos {
                // Stream: push each blurry image to UI as soon as it is found.
                // User sees cards appear one by one instead of waiting for batch.
                for item in rawItems {
                    guard !item.isVideo else { continue }
                    let result = await withCheckedContinuation { (cont: CheckedContinuation<PhotoItem?, Never>) in
                        PhotoLibraryService.shared.loadImage(
                            for: item.asset,
                            targetSize: CGSize(width: 200, height: 200)
                        ) { image in
                            guard let image else { cont.resume(returning: nil); return }
                            let isBlurry = BlurDetector.shared.isBlurry(image)
                            cont.resume(returning: isBlurry ? item : nil)
                        }
                    }
                    if let found = result {
                        await MainActor.run {
                            self.photoStack.append(found)
                            self.photoService.startCaching(
                                for: [found],
                                targetSize: CGSize(width: 400, height: 600)
                            )
                            // Hide loading indicator as soon as first result arrives
                            if self.isLoading { self.isLoading = false }
                        }
                    }
                }
            } else if filter == .burstPhotos {
                // Burst needs grouping — analyze full batch then stream results
                let analyzed = await BurstAnalyzer.shared.analyze(rawItems)
                if !analyzed.isEmpty {
                    await MainActor.run {
                        self.photoStack.append(contentsOf: analyzed)
                        self.photoService.startCaching(
                            for: analyzed,
                            targetSize: CGSize(width: 400, height: 600)
                        )
                        if self.isLoading { self.isLoading = false }
                    }
                }
            } else if filter == .largeVideos {
                // fetchPageOfAssets already filtered and sorted by size; stream batch directly.
                if !rawItems.isEmpty {
                    await MainActor.run {
                        self.photoStack.append(contentsOf: rawItems)
                        self.photoService.startCaching(
                            for: rawItems,
                            targetSize: CGSize(width: 400, height: 600)
                        )
                        if self.isLoading { self.isLoading = false }
                    }
                }
            }

            if nextIdx == nil { break }
        }

        // Ensure loading indicator is hidden even if nothing was found
        await MainActor.run { self.isLoading = false }
    }

    private func saveBinToDisk() {
        persistence.reviewBinIDs = reviewBin.map { $0.id }
        persistence.reviewBinSpaceSaved = totalSpaceSaved
    }

    // MARK: - Snooze Helpers

    /// Called after every keep/delete swipe and after rebuilding photoStack.
    /// Inserts any snooze-ready items at snoozeStageDepth (index 2) — the bottom
    /// of the visible ZStack. The item naturally bubbles to index 0 as the user
    /// swipes, with no pop or teleport.
    ///
    /// Only items whose milestone is reached AND that belong to the active category
    /// are staged — others remain in the queue until the user returns to a compatible
    /// category. processedAssetIDs is cleared at staging so pagination cannot add a
    /// duplicate. The persistence record is intentionally kept until the user makes a
    /// final decision (keep/delete/undo) — this preserves snoozeCount for the ×2/×3
    /// badge and for correct backoff on subsequent snoozes. O(n) over snoozeQueue
    /// (typically < 10 items).
    private func stageSnoozedItemsIfReady() {
        guard !snoozeQueue.isEmpty else { return }
        let counter = persistence.globalActionCounter
        var indicesToRemove: [Int] = []
        var toStage: [(PhotoItem, Int)] = []
        for i in snoozeQueue.indices {
            guard counter >= snoozeQueue[i].stagingMilestone else { continue }
            if matchesCurrentFilter(snoozeQueue[i].item) {
                indicesToRemove.append(i)
                toStage.append((snoozeQueue[i].item, snoozeQueue[i].snoozeCount))
            }
            // Milestone reached but wrong category — leave in queue until the user
            // returns to a compatible context.
        }
        guard !indicesToRemove.isEmpty else { return }
        for i in indicesToRemove.reversed() { snoozeQueue.remove(at: i) }
        for (item, count) in toStage {
            processedAssetIDs.remove(item.id)
            var tagged = item
            tagged.snoozeCount = count
            photoStack.insert(tagged, at: min(snoozeStageDepth, photoStack.count))
        }
        updatePendingSnoozedCount()
    }

    /// Immediately injects all snoozed items matching the current filter back into the stack,
    /// bypassing the milestone counter. Used when the stack is empty and the user taps "Review Now".
    /// In offline mode, iCloud-only items are left in the queue — only locally available items are injected.
    func flushSnoozedItemsNow() {
        let candidates = flushableSnoozedItems()
        guard !candidates.isEmpty else { return }
        let flushIDs = Set(candidates.map { $0.item.id })
        snoozeQueue.removeAll { flushIDs.contains($0.item.id) }
        for snoozed in candidates {
            processedAssetIDs.remove(snoozed.item.id)
            var tagged = snoozed.item
            tagged.snoozeCount = snoozed.snoozeCount
            photoStack.insert(tagged, at: min(snoozeStageDepth, photoStack.count))
        }
        updatePendingSnoozedCount()
        hapticService.success()
        precacheNextImages()
    }

    private func updatePendingSnoozedCount() {
        pendingSnoozedCount = flushableSnoozedItems().count
    }

    /// Items eligible for an immediate flush: match the active filter, and in offline mode
    /// are also locally available (not iCloud-only). snoozeQueue is typically < 10 items so
    /// the isLocallyAvailable check (Photos DB metadata read, no I/O) is negligible.
    private func flushableSnoozedItems() -> [SnoozedPhoto] {
        let matching = snoozeQueue.filter { matchesCurrentFilter($0.item) }
        guard isOfflineMode else { return matching }
        return matching.filter {
            photoService.isLocallyAvailable($0.item.asset) ||
            OfflineCacheService.shared.isCached(for: $0.item.id)
        }
    }

    /// Returns true when `item` is a valid member of the currently active filter category.
    /// Mirrors the inclusion logic in PhotoLibraryService.fetchPageOfAssets so that snooze
    /// re-injection honours strict category boundaries.
    private func matchesCurrentFilter(_ item: PhotoItem) -> Bool {
        switch currentFilter {
        case .all:             return true
        case .screenshots:     return item.isScreenshot
        case .screenRecordings: return item.isScreenRecording
        case .largeVideos:     return item.isVideo && item.fileSize > PhotoLibraryService.largeVideoThresholdBytes
        case .blurryPhotos:    return item.asset.mediaType == .image && !item.isScreenshot
        case .burstPhotos:     return item.asset.mediaType == .image && !item.isScreenshot && !item.isScreenRecording
        }
    }

    /// Early warm-up called at the 80 pt drag threshold in SwipeStackView.
    /// Starts loading the *next* cards (index 1…5) into NSCache while the user
    /// is still mid-drag, giving us the full remaining gesture duration as
    /// headstart before the new top card hits the screen.
    func prepareUpcomingCards() {
        // index 0 is the card being dragged away — skip it.
        let upcomingItems = Array(photoStack.dropFirst().prefix(5))
        guard !upcomingItems.isEmpty else { return }

        let targetSize = PhotoStackViewModel.cacheTargetSize
        photoService.startCaching(for: upcomingItems, targetSize: targetSize)

        // Pass the top card's ID as protected so its AVPlayer is never evicted
        // while the gesture is still in flight (user may drag back to centre).
        let topCardID = photoStack.first?.asset.localIdentifier
        let upcomingAssets = upcomingItems.map { $0.asset }
        Task { await VideoPlayerPool.shared.warmUp(for: upcomingAssets, protectedID: topCardID) }

        for item in upcomingItems where !item.isVideo {
            let key = item.id as NSString
            if imageCache.object(forKey: key) != nil {
                loadedImageIDs.insert(item.id)
                continue
            }
            PhotoLibraryService.shared.loadImage(
                for: item.asset, targetSize: targetSize,
                onSlowNetwork: { [weak self] in
                    Task { @MainActor [weak self] in self?.recordNetworkFailure() }
                }
            ) { [weak self] img in
                guard let self, let img else { return }
                self.imageCache.setObject(img, forKey: key, cost: Int(targetSize.width * targetSize.height * 4))
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Remove then insert: if a quality upgrade just landed (second call),
                    // the toggle forces SwiftUI to re-render and pick up the better image.
                    self.loadedImageIDs.remove(item.id)
                    self.loadedImageIDs.insert(item.id)
                }
            }
        }
    }

    private func precacheNextImages() {
        let nextItems = Array(photoStack.prefix(5))
        guard !nextItems.isEmpty else { return }
        let targetSize = PhotoStackViewModel.cacheTargetSize
        photoService.startCaching(for: nextItems, targetSize: targetSize)

        let nextAssets = nextItems.map { $0.asset }
        Task { await VideoPlayerPool.shared.warmUp(for: nextAssets) }

        // Pull all top-5 non-video images into NSCache (was top-3).
        // countLimit is now 8 so there is room for 5 cards + undo slot.
        for item in nextItems where !item.isVideo {
            let key = item.id as NSString
            if imageCache.object(forKey: key) != nil {
                loadedImageIDs.insert(item.id)
                continue
            }
            PhotoLibraryService.shared.loadImage(
                for: item.asset, targetSize: targetSize,
                onSlowNetwork: { [weak self] in
                    Task { @MainActor [weak self] in self?.recordNetworkFailure() }
                }
            ) { [weak self] img in
                guard let self, let img else { return }
                self.imageCache.setObject(img, forKey: key, cost: Int(targetSize.width * targetSize.height * 4))
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.loadedImageIDs.remove(item.id)
                    self.loadedImageIDs.insert(item.id)
                }
            }
        }

        evictStaleCacheEntries(keeping: nextItems)
    }

    private func evictStaleCacheEntries(keeping items: [PhotoItem]) {
        var keepIDs = Set(items.map { $0.id })
        // Index-0 immunity: never evict the card currently on screen,
        // even if called unexpectedly while a drag is in progress.
        if let topID = photoStack.first?.id { keepIDs.insert(topID) }
        var evictedItems: [PhotoItem] = []
        for id in activeCacheIDs where !keepIDs.contains(id) && id != lastAction?.item.id {
            imageCache.removeObject(forKey: id as NSString)
            loadedImageIDs.remove(id)
            // Collect the PhotoItem so we can tell PHCachingImageManager to stop
            // pre-fetching assets that have left the visible window (Bug #3 fix).
            if let item = photoStack.first(where: { $0.id == id }) {
                evictedItems.append(item)
            }
        }
        if !evictedItems.isEmpty {
            photoService.stopCaching(for: evictedItems)
        }
        activeCacheIDs = keepIDs
        if let lastID = lastAction?.item.id { activeCacheIDs.insert(lastID) }
    }

    /// Tracks which asset IDs currently have entries in `imageCache` so we can
    /// perform targeted eviction without enumerating the NSCache.
    private var activeCacheIDs: Set<String> = []
}
