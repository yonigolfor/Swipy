//
//  ReviewBinViewModel.swift
//  CleanSwipe
//
//  ViewModel עבור מסך Review Bin
//

import SwiftUI
import Photos

@MainActor
class ReviewBinViewModel: ObservableObject {
    @Published var selectedItem: PhotoItem?
    @Published var isShowingDeleteConfirmation = false
    
    private let hapticService = HapticService.shared
    
    /// פתיחת תמונה במסך מלא
    func selectItem(_ item: PhotoItem) {
        selectedItem = item
        hapticService.selection()
    }
    
    /// סגירת מסך מלא
    func deselectItem() {
        selectedItem = nil
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
