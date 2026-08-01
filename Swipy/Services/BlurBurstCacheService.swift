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

    private struct VerdictData: Codable {
        var blurVerdicts: [String: Bool] = [:]
        var burstVerdicts: [String: Bool] = [:]
    }

    private struct FeaturePrintData: Codable {
        /// Serialized VNFeaturePrintObservation per asset (NSKeyedArchiver), so
        /// BurstAnalyzer can skip re-running Vision for previously-seen assets.
        /// Only valid for the schema recorded in `schemaVersion` — see the
        /// invalidation check in `init()`.
        var prints: [String: Data] = [:]
        var schemaVersion: String = ""
    }

    /// Small, stable booleans — kept in their own file/store so a blur/burst
    /// verdict write never forces re-encoding the much larger, separately-
    /// growing feature-print blobs below, and vice versa (a burst scan's
    /// feature-print writes don't repeatedly re-serialize these).
    private let verdicts: DebouncedJSONStore<VerdictData>
    /// Feature-print vectors are a heavier payload (a few KB each, inflated
    /// further by JSON's base64 encoding of Data) than a boolean verdict, and
    /// grow with how much of the library has been scanned — split into its
    /// own store/file so persisting a verdict write doesn't also re-encode
    /// every feature print ever cached.
    private let featurePrints: DebouncedJSONStore<FeaturePrintData>

    /// Explicitly bumped by a developer only when the app's Vision feature-print
    /// usage actually changes (e.g. switching VNGenerateImageFeaturePrintRequest
    /// revisions) — NOT tied to OS version. An OS-version-string proxy was tried
    /// first and rejected: it wiped the cache on every iOS point release even
    /// when the underlying model almost never changes between them, and it
    /// wouldn't catch a genuine model change that isn't reflected in the OS
    /// version string either. A manual constant is a more honest signal for
    /// what this is actually guarding against: `computeDistance` failing on a
    /// cross-version-incompatible pair silently falls through to "treat as
    /// similar" in BurstAnalyzer (try? leaves distance at its initial 0, which
    /// is < the similarity threshold) — so a stale cross-schema vector could
    /// silently mis-group unrelated photos into a burst instead of throwing a
    /// visible error. Wiping featurePrints alone (verdicts don't carry this
    /// risk) on a mismatch is a small correctness cost, not a performance one —
    /// it only forces the first Smart Filters visit after a bump to recompute.
    private static let currentFeaturePrintSchemaVersion = "1"

    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // Caches directory, not Documents — this is a rebuildable index, not
        // user data, and shouldn't be backed up or synced.
        verdicts = DebouncedJSONStore(
            fileURL: cachesDir.appendingPathComponent("blurBurstVerdicts.json"),
            defaultValue: VerdictData()
        )
        featurePrints = DebouncedJSONStore(
            fileURL: cachesDir.appendingPathComponent("blurBurstFeaturePrints.json"),
            defaultValue: FeaturePrintData()
        )

        if featurePrints.read({ $0.schemaVersion }) != Self.currentFeaturePrintSchemaVersion {
            featurePrints.mutate { $0 = FeaturePrintData(schemaVersion: Self.currentFeaturePrintSchemaVersion) }
        }
    }

    // MARK: - Blur

    func blurVerdict(for id: String) -> Bool? {
        verdicts.read { $0.blurVerdicts[id] }
    }

    func setBlurVerdict(_ isBlurry: Bool, for id: String) {
        verdicts.mutate { $0.blurVerdicts[id] = isBlurry }
    }

    // MARK: - Burst

    func burstVerdict(for id: String) -> Bool? {
        verdicts.read { $0.burstVerdicts[id] }
    }

    /// Batch write — used after a burst analysis pass covers a whole batch at once,
    /// so a 300-item scan triggers one debounced save instead of 300.
    func setBurstVerdicts(_ newVerdicts: [String: Bool]) {
        guard !newVerdicts.isEmpty else { return }
        verdicts.mutate { data in
            for (id, verdict) in newVerdicts { data.burstVerdicts[id] = verdict }
        }
    }

    // MARK: - Feature Prints

    /// Cache-first Vision feature print for burst similarity comparison — nil means
    /// "not cached for the current schema version", not "asset has no burst membership".
    func featurePrint(for id: String) -> VNFeaturePrintObservation? {
        guard let archived = featurePrints.read({ $0.prints[id] }) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: archived)
    }

    func setFeaturePrint(_ observation: VNFeaturePrintObservation, for id: String) {
        guard let archived = try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true) else {
            #if DEBUG
            print("[BlurBurstCacheService] ⚠️ Failed to archive feature print for \(id.prefix(8)) — will recompute via Vision every scan.")
            #endif
            return
        }
        featurePrints.mutate { $0.prints[id] = archived }
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
        verdicts.mutate { data in
            for id in assetIDs {
                data.blurVerdicts.removeValue(forKey: id)
                data.burstVerdicts.removeValue(forKey: id)
            }
        }
        featurePrints.mutate { data in
            for id in assetIDs { data.prints.removeValue(forKey: id) }
        }
    }
}

/// Generic debounced, lock-protected, disk-backed store for one Codable value.
/// Reads run synchronously against the in-memory value; `mutate` applies a change
/// and schedules a single debounced disk write ~2s after the last mutation, so a
/// burst of writes (e.g. hundreds of per-asset verdicts from a TaskGroup scan)
/// coalesces into one file write instead of one per call. Not MainActor-isolated —
/// safe to read/mutate from any thread.
private final class DebouncedJSONStore<Value: Codable> {
    private var value: Value
    private let lock = NSLock()
    private var isDirty = false
    private var pendingSave: DispatchWorkItem?
    private let fileURL: URL

    init(fileURL: URL, defaultValue: Value) {
        self.fileURL = fileURL
        if let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Value.self, from: raw) {
            value = decoded
        } else {
            value = defaultValue
        }
    }

    func read<R>(_ body: (Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(value)
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&value)
        isDirty = true
        // Cancel/reassign happen inside the same lock as the mutation above —
        // scheduleSave() used to do this outside the lock, which was a real
        // data race once callers started invoking it from concurrent TaskGroup
        // children (multiple threads racing on the same class-typed property).
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        pendingSave = work
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func persist() {
        lock.lock()
        guard isDirty else { lock.unlock(); return }
        isDirty = false
        let snapshot = value
        lock.unlock()

        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}
