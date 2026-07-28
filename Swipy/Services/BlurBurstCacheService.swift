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

/// Thread-safe, disk-backed cache of blur/burst verdicts keyed by PHAsset localIdentifier.
/// Not MainActor-isolated — read/write from any thread (background scan tasks included).
final class BlurBurstCacheService {
    static let shared = BlurBurstCacheService()

    private struct CacheData: Codable {
        var blurVerdicts: [String: Bool] = [:]
        var burstVerdicts: [String: Bool] = [:]
    }

    private var data: CacheData
    private let lock = NSLock()
    private var isDirty = false
    private var pendingSave: DispatchWorkItem?

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

    // MARK: - Invalidation

    /// Drops verdicts for assets no longer in the library (deleted externally).
    /// Called from photoLibraryDidChange — keeps the cache from growing stale
    /// entries forever without requiring a full-cache wipe on every library edit.
    func invalidate(removedIDs: Set<String>) {
        guard !removedIDs.isEmpty else { return }
        lock.lock()
        for id in removedIDs {
            data.blurVerdicts.removeValue(forKey: id)
            data.burstVerdicts.removeValue(forKey: id)
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
