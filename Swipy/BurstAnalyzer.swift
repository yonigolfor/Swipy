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
    func analyze(_ items: [PhotoItem]) async -> [PhotoItem] {
        guard items.count >= minGroupSize else { return [] }

        let sorted = items.sorted {
            ($0.asset.creationDate ?? .distantPast) < ($1.asset.creationDate ?? .distantPast)
        }

        var groups: [[PhotoItem]] = []
        var currentGroup: [PhotoItem] = [sorted[0]]
        // Feature print of the last item added to the current group
        var lastPrint: VNFeaturePrintObservation? = await featurePrint(for: sorted[0].asset)

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]

            let gap = timeDelta(prev, curr)
            let sameBurstID = prev.asset.burstIdentifier != nil
                && prev.asset.burstIdentifier == curr.asset.burstIdentifier

            var shouldGroup = false
            var currPrint: VNFeaturePrintObservation? = nil

            if sameBurstID {
                // Native iOS burst — no need for visual check
                shouldGroup = true
            } else if gap <= timeGapThreshold {
                // Only compute feature print when time gate passes
                currPrint = await featurePrint(for: curr.asset)
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
                if let p = currPrint {
                    lastPrint = p
                } else {
                    lastPrint = await featurePrint(for: curr.asset)
                }
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
