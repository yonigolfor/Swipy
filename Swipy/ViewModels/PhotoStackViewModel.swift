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

    /// In-memory cache for the expensive large video count.
    /// Persisted to Documents/largeVideoCount.json between app launches.
    private var cachedLargeVideoCount: Int? = nil

    /// Path to the small JSON cache file for large video count.
    private var cacheFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("largeVideoCount.json")
    }

    // MARK: - Private State

    /// IDs of every asset the user has already acted on (keep / delete / star).
    /// Persists across tab switches and filter changes within one app session.
    /// Cleared only when emptyTrash() is called for permanently-deleted items
    /// (their IDs can never come back anyway), or when the user explicitly
    /// undoes an action via restoreFromBin.
    private(set) var processedAssetIDs: Set<String> = []
    private var lastAction: (item: PhotoItem, action: SwipeAction)?

    // MARK: - Pagination State

    /// The index in the PHFetchResult where the next page load will resume.
    /// Reset to 0 whenever the filter changes or the library is refreshed.
    private var fetchCursor: Int = 0

    /// True while a background page-fetch is in flight — prevents concurrent fetches.
    private var isFetchingNextPage = false

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

            // Ensure fetchResult is populated
            if service.fetchResult == nil {
                service.fetchAllPhotos()
            }

            let processed = await self.processedAssetIDs

            // ── Phase 1: Instant estimates (milliseconds) ─────────────────
            // Builds fast counts for all categories except largeVideos.
            // largeVideos uses cached value from previous run if available.
            var fastCounts: [FilterCategory: Int] = Dictionary(
                uniqueKeysWithValues: FilterCategory.allCases.map {
                    ($0, service.countFast(for: $0, excluding: processed))
                }
            )

            // If we have a cached large video count, use it immediately.
            // This means the user NEVER sees shimmer on repeat launches.
            let cached = await self.cachedLargeVideoCount
            if let cached {
                fastCounts[.largeVideos] = cached
            }

            await MainActor.run {
                withAnimation { self.categoryCounts = fastCounts }
                // Only show shimmer if we have NO cached value yet
                self.isCountingLargeVideos = cached == nil
            }

            // ── Phase 2: Accurate large video count in background ─────────
            // Always runs to verify/update the cache, but only shows
            // shimmer when there is no cached value (first ever launch).
            let accurateLargeVideoCount = await Task.detached(priority: .background) {
                service.count(for: .largeVideos, excluding: processed)
            }.value

            // Save to cache so next launch is instant
            await self.saveLargeVideoCountToCache(accurateLargeVideoCount)

            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    self.categoryCounts[.largeVideos] = accurateLargeVideoCount
                    self.isCountingLargeVideos = false
                }
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
                    photoService.startCaching(
                        for: Array(items.prefix(10)),
                        targetSize: CGSize(width: 400, height: 600)
                    )
                    let firstAssets = Array(items.prefix(5)).map { $0.asset }
                    Task { await VideoPlayerPool.shared.warmUp(for: firstAssets) }
                }

                if self.categoryCounts.isEmpty {
                    self.refreshCategoryCounts()
                }
            }
        }
    }

    /// Appends the next page of assets to `photoStack` when the stack is running low.
    /// No-op for filters that need up-front analysis (burst / blurry) since their
    /// pool is already bounded by the initial large page.
    private func loadNextPageIfNeeded() {
        guard !isFetchingNextPage,
              photoStack.count <= lowWatermark,
              fetchCursor < photoService.totalAssetCount else { return }

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
        processedAssetIDs.insert(topCard.id)
        persistence.saveKeptID(topCard.id)
        self.lastAction = (topCard, .keep)
        photoStack.removeFirst()
        hapticService.keep()
        precacheNextImages()
        loadNextPageIfNeeded()
    }

    /// Swipe Left — Delete (moves to Review Bin)
    func deletePhoto() {
        guard let topCard = photoStack.first else { return }
        processedAssetIDs.insert(topCard.id)
        self.lastAction = (topCard, .delete)
        photoStack.removeFirst()
        reviewBin.append(topCard)
        totalSpaceSaved += topCard.fileSize
        hapticService.delete()
        precacheNextImages()
        saveBinToDisk()
        loadNextPageIfNeeded()
    }

    /// Swipe Up — Star Keeper
    func starPhoto() {
        guard var topCard = photoStack.first else { return }
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

    private func precacheNextImages() {
        let nextItems = Array(photoStack.prefix(5))
        guard !nextItems.isEmpty else { return }
        photoService.startCaching(
            for: nextItems,
            targetSize: CGSize(width: 400, height: 600)
        )
        // Warm up the video player pool with the next upcoming video assets.
        // VideoPlayerPool filters to videos only, so passing all items is safe.
        let nextAssets = nextItems.map { $0.asset }
        Task { await VideoPlayerPool.shared.warmUp(for: nextAssets) }
    }
}
