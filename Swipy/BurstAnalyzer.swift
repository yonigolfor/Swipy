//
//  BurstAnalyzer.swift
//  CleanSwipe
//

import Photos
import UIKit
import Vision

struct BurstGroup {
    let representative: PhotoItem   // התמונה הטובה ביותר
    let duplicates: [PhotoItem]     // השאר — מועמדות למחיקה
}

class BurstAnalyzer {
    static let shared = BurstAnalyzer()
    private init() {}

    /// מקבל assets של burst ומחזיר את הנציג + השאריות
    func analyze(_ items: [PhotoItem]) async -> [PhotoItem] {
        guard !items.isEmpty else { return [] }

        // קבץ לפי burstIdentifier או timestamp (פחות מ-2 שניות בין תמונות)
        let sorted = items.sorted { ($0.asset.creationDate ?? .distantPast) < ($1.asset.creationDate ?? .distantPast) }

        var groups: [[PhotoItem]] = []
        var currentGroup: [PhotoItem] = []

        for item in sorted {
            // קודם בדוק burstIdentifier
            if let burstID = item.asset.burstIdentifier,
               let last = currentGroup.last,
               last.asset.burstIdentifier == burstID {
                currentGroup.append(item)
                continue
            }

            // אחרת בדוק timestamp
            if let lastDate = currentGroup.last?.asset.creationDate,
               let currentDate = item.asset.creationDate,
               currentDate.timeIntervalSince(lastDate) < 2.0 {
                currentGroup.append(item)
            } else {
                if currentGroup.count >= 3 { groups.append(currentGroup) }
                currentGroup = [item]
            }
        }
        if currentGroup.count >= 3 { groups.append(currentGroup) }

        var result: [PhotoItem] = []

        for group in groups {
            guard group.count > 1 else {
                result.append(contentsOf: group)
                continue
            }
            // מצא את הנציג — עדיפות לתמונה עם burstSelectionTypes .autoPick
            let representative = group.first {
                $0.asset.burstSelectionTypes.contains(.autoPick)
            } ?? group.first!

            // החזר רק את השאריות (לא את הנציג)
            let duplicates = group.filter { $0.id != representative.id }
            result.append(contentsOf: duplicates)
        }

        return result
    }
}
