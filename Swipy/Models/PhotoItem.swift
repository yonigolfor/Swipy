//
//  PhotoItem.swift
//  CleanSwipe
//
//  מודל עבור פריט תמונה/וידאו עם מטה-דאטה
//

import Photos
import SwiftUI

/// Wrapper עבור PHAsset עם state נוסף
struct PhotoItem: Identifiable {
    let id: String
    let asset: PHAsset
    var rotation: Double // רוטציה אקראית עבור stack effect
    var isStarred: Bool = false // עבור Burst/Similar mode
    
    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        // רוטציה אקראית בין -4 ל-4 מעלות
        self.rotation = Double.random(in: -4...4)
    }
    
    /// גודל הקובץ
    var fileSize: Int64 {
        asset.fileSize
    }
    
    /// גודל קריא
    var fileSizeString: String {
        asset.fileSizeString
    }
    
    /// סוג המדיה
    var mediaType: PHAssetMediaType {
        asset.mediaType
    }
    
    /// האם זה וידאו
    var isVideo: Bool {
        mediaType == .video
    }
    
    /// משך הוידאו (בשניות)
    var duration: TimeInterval {
        asset.duration
    }
    
    /// משך קריא (MM:SS)
    var durationString: String {
        guard isVideo else { return "" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// תאריך יצירה
    var creationDate: Date? {
        asset.creationDate
    }
    
    /// האם זה screenshot
    var isScreenshot: Bool {
        asset.isScreenshot
    }
    
    /// האם זה screen recording
    var isScreenRecording: Bool {
        asset.isScreenRecording
    }
}

// MARK: - Equatable
extension PhotoItem: Equatable {
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable
extension PhotoItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
