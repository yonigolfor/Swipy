//
//  FilterCategory.swift
//  CleanSwipe
//
//  קטגוריות "Easy Targets" לסינון מהיר
//

import SwiftUI

enum FilterCategory: String, CaseIterable, Identifiable {
    case screenshots
    case screenRecordings
    case largeVideos
    case blurryPhotos
    case all
    case burstPhotos

    var displayName: String {
        switch self {
        case .screenshots: return String(localized: "filter.screenshots")
        case .screenRecordings: return String(localized: "filter.recordings")
        case .largeVideos: return String(localized: "filter.large_videos")
        case .blurryPhotos: return String(localized: "filter.blurry")
        case .all: return String(localized: "filter.all")
        case .burstPhotos: return String(localized: "filter.burst")
        }
    }
    
    var id: String { displayName }

    var icon: String {
        switch self {
        case .burstPhotos: return "square.stack.3d.up"
        case .screenshots: return "camera.viewfinder"
        case .screenRecordings: return "record.circle"
        case .largeVideos: return "film"
        case .blurryPhotos: return "eye.slash"
        case .all: return "photo.stack"
        }
    }
    
    var color: Color {
        switch self {
        case .burstPhotos: return .cyan
        case .screenshots: return .blue
        case .screenRecordings: return .purple
        case .largeVideos: return .orange
        case .blurryPhotos: return .red
        case .all: return .gray
        }
    }
    
    var description: String {
            switch self {
            case .screenshots: return String(localized: "filter.screenshots.desc")
            case .screenRecordings: return String(localized: "filter.recordings.desc")
            case .largeVideos: return String(localized: "filter.large_videos.desc")
            case .blurryPhotos: return String(localized: "filter.blurry.desc")
            case .all: return String(localized: "filter.all.desc")
            case .burstPhotos: return String(localized: "filter.burst.desc")
            }
        }
}
