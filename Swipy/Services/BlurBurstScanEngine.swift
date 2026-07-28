//
//  BlurBurstScanEngine.swift
//  Swipy
//
//  Concurrent, cache-backed blur scanning. Deliberately a plain class (not
//  @MainActor) — like BlurDetector and BurstAnalyzer, its methods are
//  nonisolated so the CIFilter/Vision work genuinely runs off the main
//  thread even when awaited from a MainActor caller. Bounds concurrency so
//  a big library doesn't decode dozens of images at once.
//

import UIKit
import Photos

final class BlurBurstScanEngine {
    static let shared = BlurBurstScanEngine()
    private init() {}

    private static let maxConcurrency = 6

    /// Cache-first blur verdict for one asset. Returns nil when the asset isn't
    /// locally analyzable this pass (e.g. iCloud-only with no cached thumbnail yet) —
    /// callers should skip it without treating that as "not blurry", since caching
    /// a false verdict here would permanently hide a photo that just hasn't synced yet.
    func blurVerdict(for item: PhotoItem) async -> Bool? {
        if let cached = BlurBurstCacheService.shared.blurVerdict(for: item.id) { return cached }
        guard !item.isVideo else { return nil }

        let image = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            PhotoLibraryService.shared.loadImageForAnalysis(for: item.asset) { image in
                continuation.resume(returning: image)
            }
        }
        guard let image else { return nil }

        let verdict = BlurDetector.shared.isBlurry(image)
        BlurBurstCacheService.shared.setBlurVerdict(verdict, for: item.id)
        return verdict
    }

    /// Scans `items` with bounded concurrency, invoking `onBlurry` for each confirmed-blurry
    /// item as soon as it resolves — callers hop back to MainActor themselves inside the closure.
    /// Returns once every item has been resolved (not once `onBlurry` has fired N times).
    func scanBlurry(_ items: [PhotoItem], onBlurry: @escaping @Sendable (PhotoItem) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            func addNext() {
                guard let item = iterator.next() else { return }
                group.addTask {
                    if await self.blurVerdict(for: item) == true {
                        await onBlurry(item)
                    }
                }
            }
            for _ in 0..<Self.maxConcurrency { addNext() }
            while await group.next() != nil { addNext() }
        }
    }

    /// Cache-first accurate count, capped at `cap` (matches the "99+" UI ceiling).
    /// Resolves and caches verdicts for any uncached items it encounters along the
    /// way, so repeated badge refreshes get progressively cheaper.
    func countBlurry(_ items: [PhotoItem], cap: Int) async -> Int {
        var count = 0
        await withTaskGroup(of: Bool?.self) { group in
            var iterator = items.makeIterator()
            func addNext() {
                guard count < cap, let item = iterator.next() else { return }
                group.addTask { await self.blurVerdict(for: item) }
            }
            for _ in 0..<Self.maxConcurrency { addNext() }
            while let result = await group.next() {
                if result == true { count += 1 }
                if count < cap { addNext() }
            }
        }
        return min(count, cap)
    }
}
