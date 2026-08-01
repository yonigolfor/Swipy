//
//  ReviewBinViewModel.swift
//  CleanSwipe
//
//  ViewModel עבור מסך Review Bin
//

import SwiftUI
import Photos

/// Bundles the tapped item with whatever thumbnail the grid cell already had decoded,
/// so FullScreenMediaView can show it instantly instead of a blank screen while it
/// fetches the high-res version. `thumbnail` is nil only if the cell itself hadn't
/// finished loading yet (rare — cells are pre-cached via startCachingBin).
struct SelectedMedia: Identifiable {
    let item: PhotoItem
    let thumbnail: UIImage?
    var id: String { item.id }
}

@MainActor
class ReviewBinViewModel: ObservableObject {
    @Published var selectedMedia: SelectedMedia?
    @Published var isShowingDeleteConfirmation = false

    private let hapticService = HapticService.shared

    /// פתיחת תמונה במסך מלא
    func selectItem(_ item: PhotoItem, thumbnail: UIImage?) {
        selectedMedia = SelectedMedia(item: item, thumbnail: thumbnail)
        hapticService.selection()
    }

    /// סגירת מסך מלא
    func deselectItem() {
        selectedMedia = nil
    }
    
    /// הצגת אישור מחיקה
    func showDeleteConfirmation() {
        isShowingDeleteConfirmation = true
    }
    
    /// ביטול אישור מחיקה
    func hideDeleteConfirmation() {
        isShowingDeleteConfirmation = false
    }
}
