import SwiftUI

class PersistenceService {
    static let shared = PersistenceService()

    // MARK: - Snooze Record

    /// Persisted per-item snooze state. Uses an absolute milestone instead of a
    /// relative countdown so the correct delay survives force-quit and relaunches.
    struct SnoozedPhotoRecord: Codable {
        let snoozeCount: Int      // how many times this item has been snoozed (drives backoff)
        let targetMilestone: Int  // globalActionCounter value at which this item should resurface
    }

    // MARK: - AppStorage Backing

    @AppStorage("keptPhotoIDs")            private var keptIDsData: Data = Data()
    @AppStorage("totalSpaceSavedLifetime") private var _totalSpaceSavedLifetime: Double = 0
    @AppStorage("reviewBinIDs")            private var reviewBinIDsData: Data = Data()
    @AppStorage("reviewBinSpaceSaved")     private var _reviewBinSpaceSaved: Double = 0

    /// V2 snooze storage — [localIdentifier: SnoozedPhotoRecord].
    @AppStorage("snoozedPhotosV2") private var snoozedPhotosData: Data = Data()

    /// Legacy V1 key — [localIdentifier: snoozeCount].
    /// Read-only after migration; zeroed out so migration never re-runs.
    @AppStorage("snoozedPhotos") private var legacySnoozedPhotosData: Data = Data()

    /// Monotonically increasing counter incremented on every keep or delete.
    /// Never decremented (not even on undo) — items compare their targetMilestone
    /// against this value to decide when they are ready to resurface.
    @AppStorage("globalActionCounter") private var _globalActionCounter: Int = 0

    // MARK: - Global Action Counter

    var globalActionCounter: Int {
        get { _globalActionCounter }
        set { _globalActionCounter = newValue }
    }

    // MARK: - Snoozed Photos (V2)

    var snoozedPhotos: [String: SnoozedPhotoRecord] {
        get {
            (try? JSONDecoder().decode(
                [String: SnoozedPhotoRecord].self,
                from: snoozedPhotosData
            )) ?? [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                snoozedPhotosData = data
            }
        }
    }

    func clearSnoozedID(_ id: String) {
        var current = snoozedPhotos
        current.removeValue(forKey: id)
        snoozedPhotos = current
    }

    // MARK: - Migration (V1 → V2)

    /// One-time migration from [String: Int] (V1) to [String: SnoozedPhotoRecord] (V2).
    /// Sets targetMilestone = globalActionCounter for all legacy items so they surface
    /// immediately on first launch after update — matching prior force-quit behaviour.
    /// Must be called once, before restoreSnoozedItems(), during ViewModel init.
    func migrateSnoozeDataIfNeeded() {
        guard !legacySnoozedPhotosData.isEmpty,
              let legacy = try? JSONDecoder().decode(
                  [String: Int].self,
                  from: legacySnoozedPhotosData
              ),
              !legacy.isEmpty else { return }

        let counter = globalActionCounter
        var migrated: [String: SnoozedPhotoRecord] = [:]
        for (id, count) in legacy {
            migrated[id] = SnoozedPhotoRecord(snoozeCount: count, targetMilestone: counter)
        }
        snoozedPhotos = migrated
        legacySnoozedPhotosData = Data() // clear V1 key — migration must not re-run
    }

    // MARK: - Review Bin

    var reviewBinSpaceSaved: Int64 {
        get { Int64(_reviewBinSpaceSaved) }
        set { _reviewBinSpaceSaved = Double(newValue) }
    }

    var reviewBinIDs: [String] {
        get { (try? JSONDecoder().decode([String].self, from: reviewBinIDsData)) ?? [] }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                reviewBinIDsData = data
            }
        }
    }

    // MARK: - Lifetime Space Saved

    var totalSpaceSavedLifetime: Int64 {
        get { Int64(_totalSpaceSavedLifetime) }
        set { _totalSpaceSavedLifetime = Double(newValue) }
    }

    // MARK: - Kept IDs

    var keptPhotoIDs: Set<String> {
        get { (try? JSONDecoder().decode(Set<String>.self, from: keptIDsData)) ?? [] }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                keptIDsData = data
            }
        }
    }

    func saveKeptID(_ id: String) {
        var current = keptPhotoIDs
        current.insert(id)
        keptPhotoIDs = current
    }

    func removeKeptID(_ id: String) {
        var current = keptPhotoIDs
        current.remove(id)
        keptPhotoIDs = current
    }

    func resetIfOld() {
        // Auto-reset removed
    }

    private init() {}
}
