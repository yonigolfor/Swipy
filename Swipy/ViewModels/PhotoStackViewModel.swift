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
    @Published var categoryCounts: [FilterCategory: Int] = [:]
    /// True while the expensive Phase 2 large video scan is running.
    @Published var isCountingLargeVideos = false

    /// IDs of assets whose full-res card image is currently stored in `imageCache`.
    /// @Published so views can react when a card becomes ready — used by the
    /// thumbnail-gate in Layer 3 and for observability in general.
    @Published var loadedImageIDs: Set<String> = []

    // MARK: - Paywall State

    @Published var shouldShowPaywall = false

    var canSwipe: Bool {
        DailyLimitService.shared.canSwipe(isPremium: PremiumManager.shared.isPremium)
    }

    // MARK: - Shuffle Mode State

    /// True when the user has jumped to a random point in the timeline.
    @Published var isShuffleModeActive = false

    /// Bumped each time a new shuffle (or linear-return) batch lands —
    /// the view observes this to trigger the landing animation.
    @Published var shuffleBatchID = UUID()

    // MARK: - Onboarding Scan State
    @Published var onboardingPhotoCount = 0
    @Published var onboardingVideoCount = 0
    @Published var onboardingLargeVideoCount = 0
    @Published var onboardingScanComplete = false

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

    // MARK: - Private State

    /// IDs of every asset the user has already acted on (keep / delete / star).
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

    /// Saved linear cursor position before a shuffle jump.
    /// Restored when the user exits shuffle mode.
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
        persistence.resetIfOld()
        self.processedAssetIDs = persistence.keptPhotoIDs
        loadPhotos()
        restoreBinFromDisk()
        PHPhotoLibrary.shared().register(self)
        // Load cached large video count immediately so Filters screen
        // shows last known value without any scanning on launch.
        loadCachedLargeVideoCount()
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
        fetchCursor = 0
        isFetchingNextPage = false
        loadedImageIDs = []
        // Reset shuffle so stale state doesn't leak across filter changes or tab refreshes.
        isShuffleModeActive = false
        savedLinearCursor = 0
        preShuffleStack = nil

        Task {
            // Ensure we have an up-to-date fetch result (no-op if already fresh).
            if photoService.fetchResult == nil {
                photoService.fetchAllPhotos()
            }

            let pageSize: Int
            switch filter {
            case .burstPhotos:  pageSize = 500  // BurstAnalyzer needs a pool
            case .blurryPhotos: pageSize = 200  // Enough to find blurry images
            default:            pageSize = initialPageSize
            }

            let (rawItems, nextIdx) = photoService.fetchPageOfAssets(
                for: filter,
                startIndex: 0,
                pageSize: pageSize,
                excluding: processedAssetIDs
            )

            self.fetchCursor = nextIdx ?? photoService.totalAssetCount

            // For blurry and burst — skip the standard initial load entirely.
            // scanUntilFull handles everything: it scans continuously until
            // it finds results, never showing an empty stack mid-scan.
            if filter == .blurryPhotos || filter == .burstPhotos {
                await MainActor.run {
                    self.photoStack = []
                    self.isLoading = true  // Keep loading indicator visible
                }
                await scanUntilFull(filter: filter, targetCount: 15, batchSize: 300)
                await MainActor.run { self.isLoading = false }
                if self.categoryCounts.isEmpty {
                    self.refreshCategoryCounts()
                }
                return
            }

            var items = rawItems

            print("📸 initial page: \(items.count) items, cursor: \(self.fetchCursor)/\(self.photoService.totalAssetCount)")

            await MainActor.run {
                self.photoStack = items
                self.isLoading = false

                if !items.isEmpty {
                    // precacheNextImages pulls top-5 into NSCache and warms the video
                    // pool — covers the initial load gap noted in the architecture doc
                    // (previously only startCaching hints were sent, not NSCache fills).
                    self.precacheNextImages()
                }

                if self.categoryCounts.isEmpty {
                    self.refreshCategoryCounts()
                }
            }
        }
    }

    // MARK: - Shuffle Mode

    /// User-triggered: jump to a random point in the timeline.
    /// Saves the current linear cursor so the user can return later.
    func activateShuffle() {
        guard photoService.totalAssetCount > 0 else { return }
        savedLinearCursor = fetchCursor
        preShuffleStack = photoStack          // snapshot for instant restoration on exit
        isShuffleModeActive = true
        isLoading = true
        isFetchingNextPage = false

        let total = photoService.totalAssetCount
        let randomStart = Int.random(in: 0..<total)

        Task {
            let (items, nextIdx) = photoService.fetchPageOfAssets(
                for: currentFilter,
                startIndex: randomStart,
                pageSize: initialPageSize,
                excluding: processedAssetIDs
            )
            await MainActor.run {
                self.fetchCursor = nextIdx ?? self.photoService.totalAssetCount
                self.photoStack = items
                self.isLoading = false
                self.shuffleBatchID = UUID()
                if !items.isEmpty { self.precacheNextImages() }
            }
        }
    }

    /// User-triggered: exit shuffle mode and return to the exact stack the user left.
    func deactivateShuffle() {
        isShuffleModeActive = false
        isFetchingNextPage = false
        fetchCursor = savedLinearCursor

        let restored = restoreLinearStack()
        photoStack = restored
        preShuffleStack = nil
        shuffleBatchID = UUID()
        if !restored.isEmpty { precacheNextImages() }
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
        fetchCursor = savedLinearCursor

        let restored = restoreLinearStack()
        photoStack = restored
        preShuffleStack = nil
        if !restored.isEmpty { precacheNextImages() }
        // loadNextPageIfNeeded will top up the stack from fetchCursor on the next swipe.
    }

    /// Appends the next page of assets to `photoStack` when the stack is running low.
    /// No-op for filters that need up-front analysis (burst / blurry) since their
    /// pool is already bounded by the initial large page.
    private func loadNextPageIfNeeded() {
        guard !isFetchingNextPage,
              photoStack.count <= lowWatermark else { return }

        // Shuffle segment exhausted — silently return to the linear stream.
        if isShuffleModeActive && fetchCursor >= photoService.totalAssetCount {
            shuffleExhausted()
            return
        }

        guard fetchCursor < photoService.totalAssetCount else { return }

        // For analysis-heavy filters, use the refill mechanism
        // which scans continuously until the buffer is full.
        if currentFilter == .blurryPhotos || currentFilter == .burstPhotos {
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
                    photoService.startCaching(
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
        self.lastAction = (topCard, .keep)
        photoStack.removeFirst()
        DailyLimitService.shared.recordSwipe()
        hapticService.keep()
        precacheNextImages()
        loadNextPageIfNeeded()
    }

    /// Swipe Left — Delete (moves to Review Bin)
    func deletePhoto() {
        guard let topCard = photoStack.first else { return }
        lastSwipedImage = imageCache.object(forKey: topCard.id as NSString)
        processedAssetIDs.insert(topCard.id)
        self.lastAction = (topCard, .delete)
        photoStack.removeFirst()
        reviewBin.append(topCard)
        totalSpaceSaved += topCard.fileSize
        DailyLimitService.shared.recordSwipe()
        hapticService.delete()
        precacheNextImages()
        saveBinToDisk()
        loadNextPageIfNeeded()
    }

    /// Swipe Up — Star Keeper
    func starPhoto() {
        guard var topCard = photoStack.first else { return }
        lastSwipedImage = imageCache.object(forKey: topCard.id as NSString)
        processedAssetIDs.insert(topCard.id)
        self.lastAction = (topCard, .starKeeper)
        photoStack.removeFirst()
        topCard.isStarred = true
        hapticService.starKeeper()
        precacheNextImages()
        loadNextPageIfNeeded()
        Task {
            try? await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: topCard.asset)
                request.isFavorite = true
            }
        }
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

        if last.action == .delete {
            reviewBin.removeAll { $0.id == item.id }
            totalSpaceSaved -= item.fileSize
            saveBinToDisk()
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

    /// Resets all "Kept" decisions to start over
    func resetProgress() {
        persistence.keptPhotoIDs = []
        processedAssetIDs = []
        loadPhotos(filter: currentFilter)
    }

    // MARK: - Dispatch Helper

    func performAction(_ action: SwipeAction) {
        switch action {
        case .keep:       keepPhoto()
        case .delete:     deletePhoto()
        case .starKeeper: starPhoto()
        case .undo:       undoLastAction()
        }
    }

    // MARK: - Private Helpers

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
        guard filter == .blurryPhotos || filter == .burstPhotos else { return }

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
            PhotoLibraryService.shared.loadImage(for: item.asset, targetSize: targetSize) { [weak self] img in
                guard let self, let img else { return }
                self.imageCache.setObject(img, forKey: key, cost: Int(targetSize.width * targetSize.height * 4))
                Task { @MainActor [weak self] in self?.loadedImageIDs.insert(item.id) }
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
            PhotoLibraryService.shared.loadImage(for: item.asset, targetSize: targetSize) { [weak self] img in
                guard let self, let img else { return }
                self.imageCache.setObject(img, forKey: key, cost: Int(targetSize.width * targetSize.height * 4))
                Task { @MainActor [weak self] in self?.loadedImageIDs.insert(item.id) }
            }
        }

        evictStaleCacheEntries(keeping: nextItems)
    }

    private func evictStaleCacheEntries(keeping items: [PhotoItem]) {
        var keepIDs = Set(items.map { $0.id })
        // Index-0 immunity: never evict the card currently on screen,
        // even if called unexpectedly while a drag is in progress.
        if let topID = photoStack.first?.id { keepIDs.insert(topID) }
        for id in activeCacheIDs where !keepIDs.contains(id) && id != lastAction?.item.id {
            imageCache.removeObject(forKey: id as NSString)
            loadedImageIDs.remove(id)
        }
        activeCacheIDs = keepIDs
        if let lastID = lastAction?.item.id { activeCacheIDs.insert(lastID) }
    }

    /// Tracks which asset IDs currently have entries in `imageCache` so we can
    /// perform targeted eviction without enumerating the NSCache.
    private var activeCacheIDs: Set<String> = []
}
