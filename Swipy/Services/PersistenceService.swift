import SwiftUI

// Stores user decisions persistently
class PersistenceService {
    static let shared = PersistenceService()
    
    @AppStorage("keptPhotoIDs") private var keptIDsData: Data = Data()
    @AppStorage("totalSpaceSavedLifetime") private var _totalSpaceSavedLifetime: Double = 0
    @AppStorage("reviewBinIDs") private var reviewBinIDsData: Data = Data()
    @AppStorage("reviewBinSpaceSaved") private var _reviewBinSpaceSaved: Double = 0

    var reviewBinSpaceSaved: Int64 {
        get { Int64(_reviewBinSpaceSaved) }
        set { _reviewBinSpaceSaved = Double(newValue) }
    }
    var reviewBinIDs: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: reviewBinIDsData)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                reviewBinIDsData = data
            }
        }
    }
    var totalSpaceSavedLifetime: Int64 {
        get { Int64(_totalSpaceSavedLifetime) }
        set { _totalSpaceSavedLifetime = Double(newValue) }
    }
    
    private init() {}
    
    var keptPhotoIDs: Set<String> {
        get {
            guard let ids = try? JSONDecoder().decode(Set<String>.self, from: keptIDsData) else {
                return []
            }
            return ids
        }
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
}
