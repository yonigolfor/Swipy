//
//  BurstAnalyzer.swift
//  Swipy
//

import Photos
import Vision

class BurstAnalyzer {
    static let shared = BurstAnalyzer()
    private init() {}

    private let timeGapThreshold: TimeInterval = 30.0
    private let visualDistanceThreshold: Float = 0.85
    private let minGroupSize = 5

    /// Groups photos into burst clusters using native burstIdentifier or
    /// (gap ≤ 30s AND visual similarity via VNFeaturePrint).
    /// Chain comparison: each new photo is compared to the last added,
    /// which handles gradual scene drift in long shooting sessions.
    /// `maxConcurrency` bounds the feature-print precompute pass — interactive callers
    /// (scanUntilFull) use the default; background callers (the post-onboarding
    /// prescan) pass a lower value since nothing there is time-sensitive.
    func analyze(_ items: [PhotoItem], maxConcurrency: Int = defaultConcurrency) async -> [PhotoItem] {
        guard items.count >= minGroupSize else { return [] }

        let sorted = items.sorted {
            ($0.asset.creationDate ?? .distantPast) < ($1.asset.creationDate ?? .distantPast)
        }

        // Every item that isn't part of a native burst chain may need its feature print —
        // which one depends on the grouping decisions below, so precompute all of them
        // concurrently up front. The grouping pass itself is then pure CPU (dictionary
        // lookups + vector distance), no more sequential per-photo I/O waits.
        let prints = await featurePrints(for: sorted, maxConcurrency: maxConcurrency)

        var groups: [[PhotoItem]] = []
        var currentGroup: [PhotoItem] = [sorted[0]]
        // Feature print of the last item added to the current group
        var lastPrint: VNFeaturePrintObservation? = prints[sorted[0].id]

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]

            let gap = timeDelta(prev, curr)
            let sameBurstID = prev.asset.burstIdentifier != nil
                && prev.asset.burstIdentifier == curr.asset.burstIdentifier

            var shouldGroup = false
            let currPrint = prints[curr.id]

            if sameBurstID {
                // Native iOS burst — no need for visual check
                shouldGroup = true
            } else if gap <= timeGapThreshold {
                if let p1 = lastPrint, let p2 = currPrint {
                    var distance: Float = 0
                    try? p1.computeDistance(&distance, to: p2)
                    shouldGroup = distance < visualDistanceThreshold
                } else {
                    // Feature print unavailable (iCloud-only asset) — fall back to time
                    shouldGroup = true
                }
            }

            if shouldGroup {
                currentGroup.append(curr)
                // Advance chain anchor to the last confirmed similar photo
                if let p = currPrint { lastPrint = p }
            } else {
                if currentGroup.count >= minGroupSize { groups.append(currentGroup) }
                currentGroup = [curr]
                // Reuse already-computed print for the new group's anchor
                lastPrint = currPrint
            }
        }
        if currentGroup.count >= minGroupSize { groups.append(currentGroup) }

        // Tag autoPick (only when iOS explicitly chose one)
        var result: [PhotoItem] = []
        for group in groups {
            let autoPickID = group.first { $0.asset.burstSelectionTypes.contains(.autoPick) }?.id
            let tagged = group.map { item -> PhotoItem in
                var copy = item
                copy.isBurstBest = (autoPickID != nil && item.id == autoPickID)
                return copy
            }
            result.append(contentsOf: tagged)
        }
        return result
    }

    // MARK: - Private

    /// Default concurrency for interactive scans — see BlurBurstScanEngine.defaultConcurrency
    /// for the same rationale (this mirrors it rather than sharing it, to keep the two
    /// engines independent).
    static let defaultConcurrency = 6

    /// Computes feature prints for every item concurrently, bounded to avoid decoding
    /// too many images at once. Order-independent — the grouping pass looks these up by ID.
    /// Cache-first: a feature print is reused instead of re-running Vision, which is
    /// what keeps the on-demand Smart Filters scan cheap on repeat visits. This relies
    /// on PhotoStackViewModel.photoLibraryDidChange invalidating the cached entry via
    /// BlurBurstCacheService.invalidate(assetIDs:) whenever PHChange reports the asset
    /// in changedObjects — a PHAsset's localIdentifier survives in-app edits (crop/
    /// filter/markup) even though the pixels don't, so without that invalidation a
    /// cached print would silently go stale.
    private func featurePrints(for items: [PhotoItem], maxConcurrency: Int) async -> [String: VNFeaturePrintObservation] {
        var result: [String: VNFeaturePrintObservation] = [:]
        await withTaskGroup(of: (String, VNFeaturePrintObservation?).self) { group in
            var iterator = items.makeIterator()
            func addNext() {
                guard let item = iterator.next() else { return }
                group.addTask {
                    if let cached = BlurBurstCacheService.shared.featurePrint(for: item.id) {
                        return (item.id, cached)
                    }
                    guard let computed = await self.featurePrint(for: item.asset) else { return (item.id, nil) }
                    BlurBurstCacheService.shared.setFeaturePrint(computed, for: item.id)
                    return (item.id, computed)
                }
            }
            for _ in 0..<maxConcurrency { addNext() }
            while let (id, fp) = await group.next() {
                if let fp { result[id] = fp }
                addNext()
            }
        }
        return result
    }

    private func featurePrint(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat   // single callback, no degraded intermediate
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                resumed = true
                guard let cgImage = image?.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                let request = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                continuation.resume(returning: request.results?.first as? VNFeaturePrintObservation)
            }
        }
    }

    private func timeDelta(_ a: PhotoItem, _ b: PhotoItem) -> TimeInterval {
        guard let d1 = a.asset.creationDate, let d2 = b.asset.creationDate else { return .infinity }
        return d2.timeIntervalSince(d1)
    }
}
