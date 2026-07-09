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
    /// Max concurrent feature-print fetches during the prefetch pass below.
    private let scanConcurrencyLimit = 6

    /// Groups photos into burst clusters using native burstIdentifier or
    /// (gap ≤ 30s AND visual similarity via VNFeaturePrint).
    /// Chain comparison: each new photo is compared to the last added,
    /// which handles gradual scene drift in long shooting sessions.
    ///
    /// Two-pass: first fetch every feature print the chain comparison below could
    /// possibly need, concurrently and bounded (see `prefetchFeaturePrints`); then run
    /// the grouping decision purely in-memory. This keeps the only I/O-bound step
    /// parallelized while the sequential grouping logic stays a fast, simple pass.
    func analyze(_ items: [PhotoItem]) async -> [PhotoItem] {
        guard items.count >= minGroupSize else { return [] }

        let sorted = items.sorted {
            ($0.asset.creationDate ?? .distantPast) < ($1.asset.creationDate ?? .distantPast)
        }

        let prints = await prefetchFeaturePrints(for: sorted)

        var groups: [[PhotoItem]] = []
        var currentGroup: [PhotoItem] = [sorted[0]]
        // Feature print of the last item added to the current group
        var lastPrint: VNFeaturePrintObservation? = prints[0]

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]

            let gap = timeDelta(prev, curr)
            let sameBurstID = prev.asset.burstIdentifier != nil
                && prev.asset.burstIdentifier == curr.asset.burstIdentifier

            var shouldGroup = false
            let currPrint = prints[i]

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
                // Anchor for the new group — already prefetched (see prefetchFeaturePrints).
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

    /// Fetches feature prints for every index the chain comparison in `analyze` could
    /// possibly read: index 0 (initial anchor), every index whose gap from its
    /// predecessor is within the time gate and not already same-burst (needs a print
    /// to compare), and each such index's predecessor (serves as its anchor). Every
    /// other index is never read by the grouping pass, so skipping it changes nothing.
    /// Runs the actual fetches concurrently, bounded to scanConcurrencyLimit at a time.
    private func prefetchFeaturePrints(for sorted: [PhotoItem]) async -> [VNFeaturePrintObservation?] {
        var neededIndices: Set<Int> = [0]
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let sameBurstID = prev.asset.burstIdentifier != nil
                && prev.asset.burstIdentifier == curr.asset.burstIdentifier
            if !sameBurstID && timeDelta(prev, curr) <= timeGapThreshold {
                neededIndices.insert(i)
                neededIndices.insert(i - 1)
            }
        }

        var results = [VNFeaturePrintObservation?](repeating: nil, count: sorted.count)

        await withTaskGroup(of: (Int, VNFeaturePrintObservation?).self) { group in
            var iterator = neededIndices.sorted().makeIterator()
            func launchNext() {
                guard let idx = iterator.next() else { return }
                let asset = sorted[idx].asset
                group.addTask { (idx, await self.featurePrint(for: asset)) }
            }
            for _ in 0..<scanConcurrencyLimit { launchNext() }
            for await (idx, print) in group {
                results[idx] = print
                launchNext()
            }
        }
        return results
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
