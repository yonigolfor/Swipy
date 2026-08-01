//
//  BlurBurstCacheService.swift
//  Swipy
//
//  Persisted per-asset verdict cache for the Blurry Photos and Burst Photos
//  Smart Filters. Without this, both categories re-decode and re-analyze
//  every candidate photo on every visit — this is what caused the reported
//  hang. A verdict, once computed, is stable for the lifetime of the asset
//  (blur/burst membership don't change), so it only needs to be computed once.
//

import Foundation
import Vision

/// Thread-safe, disk-backed cache of blur/burst verdicts keyed by PHAsset localIdentifier.
/// Not MainActor-isolated — read/write from any thread (background scan tasks included).
final class BlurBurstCacheService {
    static let shared = BlurBurstCacheService()

    private struct CacheData: Codable {
        var blurVerdicts: [String: Bool] = [:]
        var burstVerdicts: [String: Bool] = [:]
        /// Serialized VNFeaturePrintObservation per asset (NSKeyedArchiver), so
        /// BurstAnalyzer can skip re-running Vision for previously-seen assets.
        /// Only valid for the OS version recorded in `featurePrintSchemaVersion` —
        /// see the invalidation check in `init()`.
        var featurePrints: [String: Data] = [:]
        var featurePrintSchemaVersion: String = ""
    }

    private var data: CacheData
    private let lock = NSLock()
    private var isDirty = false
    private var pendingSave: DispatchWorkItem?

    /// Proxy for the Vision feature-print model in use — Apple ships updated Vision
    /// models with OS updates, and a feature print computed under one model isn't
    /// guaranteed comparable to one computed under another. `computeDistance` failing
    /// on a mismatch silently falls through to "treat as similar" in BurstAnalyzer
    /// (try? leaves distance at its initial 0, which is < the similarity threshold) —
    /// so a stale cross-version vector could silently mis-group unrelated photos into
    /// a burst instead of throwing a visible error. Wiping featurePrints alone (not
    /// blurVerdicts/burstVerdicts, which don't carry this risk) on every OS version
    /// change is a small correctness cost, not a performance one — it only forces the
    /// first Smart Filters visit after an OS update to recompute prints.
    private static let currentFeaturePrintSchemaVersion = ProcessInfo.processInfo.operatingSystemVersionString

    /// Caches directory, not Documents — this is a rebuildable index, not user data,
    /// and shouldn't be backed up or synced.
    private var cacheFileURL: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("blurBurstVerdicts.json")
    }

    private init() {
        data = CacheData()
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("blurBurstVerdicts.json")
        if let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(CacheData.self, from: raw) {
            data = decoded
        }
        if data.featurePrintSchemaVersion != Self.currentFeaturePrintSchemaVersion {
            data.featurePrints = [:]
            data.featurePrintSchemaVersion = Self.currentFeaturePrintSchemaVersion
            scheduleSave()
        }
    }

    // MARK: - Blur

    func blurVerdict(for id: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return data.blurVerdicts[id]
    }

    func setBlurVerdict(_ isBlurry: Bool, for id: String) {
        lock.lock()
        data.blurVerdicts[id] = isBlurry
        lock.unlock()
        scheduleSave()
    }

    // MARK: - Burst

    func burstVerdict(for id: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return data.burstVerdicts[id]
    }

    /// Batch write — used after a burst analysis pass covers a whole batch at once,
    /// so a 300-item scan triggers one debounced save instead of 300.
    func setBurstVerdicts(_ verdicts: [String: Bool]) {
        guard !verdicts.isEmpty else { return }
        lock.lock()
        for (id, verdict) in verdicts { data.burstVerdicts[id] = verdict }
        lock.unlock()
        scheduleSave()
    }

    // MARK: - Feature Prints

    /// Cache-first Vision feature print for burst similarity comparison — nil means
    /// "not cached for the current schema version", not "asset has no burst membership".
    func featurePrint(for id: String) -> VNFeaturePrintObservation? {
        lock.lock()
        let archived = data.featurePrints[id]
        lock.unlock()
        guard let archived else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: archived)
    }

    func setFeaturePrint(_ observation: VNFeaturePrintObservation, for id: String) {
        guard let archived = try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true) else { return }
        lock.lock()
        data.featurePrints[id] = archived
        lock.unlock()
        scheduleSave()
    }

    // MARK: - Invalidation

    /// Drops all cached verdicts/feature prints for the given assets — called
    /// from photoLibraryDidChange both for assets removed from the library
    /// (deleted externally) and for assets whose content changed in place
    /// (crop/filter/markup edits keep the same localIdentifier but change
    /// pixel content, so a verdict/feature print computed before the edit is
    /// stale). Keeps the cache from growing stale entries forever, or silently
    /// serving pre-edit analysis, without requiring a full-cache wipe.
    func invalidate(assetIDs: Set<String>) {
        guard !assetIDs.isEmpty else { return }
        lock.lock()
        for id in assetIDs {
            data.blurVerdicts.removeValue(forKey: id)
            data.burstVerdicts.removeValue(forKey: id)
            data.featurePrints.removeValue(forKey: id)
        }
        lock.unlock()
        scheduleSave()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        lock.lock(); isDirty = true; lock.unlock()
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        pendingSave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func persist() {
        lock.lock()
        guard isDirty else { lock.unlock(); return }
        isDirty = false
        let snapshot = data
        lock.unlock()

        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        try? encoded.write(to: cacheFileURL, options: .atomic)
    }
}
