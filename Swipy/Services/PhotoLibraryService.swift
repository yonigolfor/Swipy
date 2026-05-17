//
//  PhotoLibraryService.swift
//  CleanSwipe
//
//  ניהול גישה לגלריית התמונות
//

import Photos
import UIKit

/// שירות לגישה ל-Photo Library
class PhotoLibraryService: ObservableObject {
    static let shared = PhotoLibraryService()
    static let largeVideoThresholdBytes: Int64 = 50_000_000

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    /// When true, all image/video requests skip iCloud downloads.
    /// Set by PhotoStackViewModel when offline mode is activated.
    var isOfflineMode: Bool = false

    private let imageManager = PHCachingImageManager()

    // The raw PHFetchResult — treated as a lazy index, never fully enumerated.
    // Access individual objects with object(at:) or bounded ranges only.
    private(set) var fetchResult: PHFetchResult<PHAsset>?

    /// Total number of assets in the current fetch result (O(1)).
    var totalAssetCount: Int { fetchResult?.count ?? 0 }

    private init() {
        checkAuthorization()
    }

    // MARK: - Authorization

    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status == .authorized || status == .limited
    }

    // MARK: - Fetch Setup (no enumeration)

    /// Refreshes the fetch result without enumerating any objects.
    /// Returns the result so callers can store the count if needed.
    @discardableResult
    func fetchAllPhotos() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        fetchResult = result
        return result
    }

    // MARK: - Paginated Loading

    /// Fetches a page of PhotoItems for the given category, starting at `startIndex`
    /// in the underlying PHFetchResult, skipping any asset whose ID is in `excluding`.
    ///
    /// Only `pageSize` (at most) objects are ever instantiated — avoids allocating
    /// 50 k PhotoItem wrappers up front.
    ///
    /// - Returns: A tuple of the collected items and the next fetch-result index
    ///   to resume from on the next page call (or `nil` if the result is exhausted).
    func fetchPageOfAssets(
        for category: FilterCategory,
        startIndex: Int,
        pageSize: Int,
        excluding processedIDs: Set<String>
    ) -> (items: [PhotoItem], nextIndex: Int?) {
        guard let fetchResult = fetchResult, fetchResult.count > 0 else {
            return ([], nil)
        }

        var collected: [PhotoItem] = []
        collected.reserveCapacity(pageSize)
        var idx = startIndex
        let total = fetchResult.count

        while idx < total && collected.count < pageSize {
            let asset = fetchResult.object(at: idx)
            idx += 1

            // Skip already-processed assets without creating a PhotoItem.
            guard !processedIDs.contains(asset.localIdentifier) else { continue }

            // Apply category filter using only PHAsset properties (no PhotoItem needed
            // for the fast path — only allocate PhotoItem when the asset qualifies).
            switch category {
            case .all:
                collected.append(PhotoItem(asset: asset))

            case .screenshots:
                if asset.isScreenshot {
                    collected.append(PhotoItem(asset: asset))
                }

            case .screenRecordings:
                if asset.isScreenRecording {
                    collected.append(PhotoItem(asset: asset))
                }

            case .largeVideos:
                // fileSize requires PHAssetResource — create item only to read it.
                let item = PhotoItem(asset: asset)
                if item.isVideo && item.fileSize > PhotoLibraryService.largeVideoThresholdBytes {
                    collected.append(item)
                }

            case .burstPhotos:
                // BurstAnalyzer needs a full pool; handled via fetchPageOfAssets
                // with a larger page in the ViewModel.
                collected.append(PhotoItem(asset: asset))

            case .blurryPhotos:
                // Only images, not screenshots; blur check done in ViewModel.
                if asset.mediaType == .image && !asset.isScreenshot {
                    collected.append(PhotoItem(asset: asset))
                }
            }
        }

        // Sort large videos by file size descending (only the current page).
        if category == .largeVideos {
            collected.sort { $0.fileSize > $1.fileSize }
        }

        let nextIndex: Int? = (idx < total) ? idx : nil
        return (collected, nextIndex)
    }

    // MARK: - Targeted Asset Lookup

    /// Fetches specific assets by their local identifiers — used for bin restoration.
    /// Much cheaper than building a full-library map.
    func fetchAssets(forIDs ids: [String]) -> [String: PHAsset] {
        guard !ids.isEmpty else { return [:] }
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: ids,
            options: nil
        )
        var map: [String: PHAsset] = [:]
        map.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            map[asset.localIdentifier] = asset
        }
        return map
    }

    // MARK: - Count (fast path)

    /// Phase 1 — instant counts using only PHAsset metadata (no resource scan).
    /// Returns results in milliseconds since it never touches file resources.
    /// Used to show immediate numbers in SmartFiltersView before the accurate
    /// Phase 2 background scan completes.
    func countFast(for category: FilterCategory, excluding processedIDs: Set<String> = []) -> Int {
        guard let fetchResult else { return 0 }

        switch category {
        case .all:
            return max(0, fetchResult.count - processedIDs.count)

        case .screenshots:
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaSubtype & %d != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            let result = PHAsset.fetchAssets(with: options)
            return max(0, result.count - processedIDs.count)

        case .screenRecordings:
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType == %d AND (pixelWidth == 1170 OR pixelWidth == 1284 OR pixelWidth == 2532)",
                PHAssetMediaType.video.rawValue
            )
            let result = PHAsset.fetchAssets(with: options)
            return max(0, result.count - processedIDs.count)

        case .largeVideos:
            // Duration-based estimate: videos > 10 s are very likely to exceed 50 MB.
            // Much closer to the real count than returning all videos.
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType == %d AND duration > 10",
                PHAssetMediaType.video.rawValue
            )
            let result = PHAsset.fetchAssets(with: options)
            return max(0, result.count - processedIDs.count)

        case .burstPhotos:
            // Match the same logic as fetchPageOfAssets which returns ALL assets
            // and lets BurstAnalyzer group them. So count is an approximation.
            // We show total image count as upper bound.
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let result = PHAsset.fetchAssets(with: options)
            return max(0, result.count - processedIDs.count)

        case .blurryPhotos:
            // Match fetchPageOfAssets which filters: image type AND not screenshot
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType == %d AND NOT (mediaSubtype & %d != 0)",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            let result = PHAsset.fetchAssets(with: options)
            return max(0, result.count - processedIDs.count)
        }
    }

    /// Approximate count of assets for a category, excluding processed IDs.
    /// For `.all`, this is O(1). Other categories still enumerate but benefit
    /// from the in-memory PHFetchResult cache.
    func count(for category: FilterCategory, excluding processedIDs: Set<String> = []) -> Int {
        guard let fetchResult = fetchResult else { return 0 }

        if category == .all {
            return max(0, fetchResult.count - processedIDs.count)
        }

        // largeVideos needs PHAssetResource (I/O per asset) — scope the fetch
        // to videos only so we never call assetResources on photos.
        if category == .largeVideos {
            return countLargeVideos(excluding: processedIDs)
        }

        let cap = 100
        var count = 0
        fetchResult.enumerateObjects { asset, _, stop in
            guard !processedIDs.contains(asset.localIdentifier) else { return }
            switch category {
            case .all, .largeVideos: break
            case .screenshots:
                if asset.isScreenshot { count += 1 }
            case .screenRecordings:
                if asset.isScreenRecording { count += 1 }
            case .burstPhotos:
                count += 1
            case .blurryPhotos:
                if asset.mediaType == .image && !asset.isScreenshot { count += 1 }
            }
            if count >= cap { stop.pointee = true }
        }
        return count
    }

    /// Counts large videos (> 50 MB). Duration pre-filter skips short clips;
    /// cap stops enumeration once 100 are found (matches the "99+" UI ceiling).
    private func countLargeVideos(excluding processedIDs: Set<String>) -> Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND duration >= 3",
            PHAssetMediaType.video.rawValue
        )
        let candidates = PHAsset.fetchAssets(with: options)
        let cap = 100
        var count = 0
        candidates.enumerateObjects { asset, _, stop in
            guard !processedIDs.contains(asset.localIdentifier) else { return }
            let size = PHAssetResource.assetResources(for: asset)
                .first.flatMap { $0.value(forKey: "fileSize") as? Int64 } ?? 0
            if size > PhotoLibraryService.largeVideoThresholdBytes { count += 1 }
            if count >= cap { stop.pointee = true }
        }
        return count
    }

    // MARK: - Local Availability

    /// Returns true if the asset's primary resource is fully stored on-device.
    /// Uses PHAssetResource metadata — no file I/O, safe to call on any thread.
    func isLocallyAvailable(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        let primaryTypes: Set<PHAssetResourceType> = [.photo, .video, .audio,
                                                       .fullSizePhoto, .fullSizeVideo,
                                                       .fullSizePairedVideo]
        for resource in resources where primaryTypes.contains(resource.type) {
            return (resource.value(forKey: "locallyAvailable") as? Bool) ?? true
        }
        return true
    }

    // MARK: - Image Loading

    /// Loads an image for a given asset asynchronously.
    /// Pass forceNetworkAccess:true to bypass offline mode (e.g. background pre-fetch).
    func loadImage(
        for asset: PHAsset,
        targetSize: CGSize,
        forceNetworkAccess: Bool = false,
        completion: @escaping (UIImage?) -> Void
    ) {
        let allowsNetwork = forceNetworkAccess || !isOfflineMode
        let options = PHImageRequestOptions()
        options.deliveryMode = allowsNetwork ? .highQualityFormat : .opportunistic
        options.isNetworkAccessAllowed = allowsNetwork
        options.isSynchronous = false

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    /// Loads a fast local thumbnail — never touches iCloud.
    /// Used as the immediate placeholder for video cards while the AVPlayer warms up.
    func loadThumbnail(
        for asset: PHAsset,
        targetSize: CGSize = CGSize(width: 300, height: 400),
        completion: @escaping (UIImage?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// Starts image caching for a set of assets.
    func startCaching(for items: [PhotoItem], targetSize: CGSize) {
        let assets = items.map { $0.asset }
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    /// Stops image caching for a set of assets.
    func stopCaching(for items: [PhotoItem]) {
        let assets = items.map { $0.asset }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: .zero,
            contentMode: .aspectFill,
            options: nil
        )
    }

    // MARK: - Deletion

    /// Permanently deletes the given assets from the photo library.
    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
}
