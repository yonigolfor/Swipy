//
//  HapticService.swift
//  CleanSwipe
//
//  ניהול Haptic Feedback עבור כל הפעולות
//

import UIKit

/// שירות רטט עבור feedback למשתמש
class HapticService {
    static let shared = HapticService()
    
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private init() {
        // Prepare generators for lower latency
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
    }
    
    // MARK: - Swipe Actions
    
    /// Swipe Right (Keep) - רטט קל
    func keep() {
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }
    
    /// Swipe Left (Delete) - רטט חזק "crunchy"
    func delete() {
        heavyGenerator.impactOccurred(intensity: 0.8)
        heavyGenerator.prepare()
    }
    
    /// Swipe Up (Star Keeper) - double pulse
    func starKeeper() {
        mediumGenerator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.mediumGenerator.impactOccurred()
            self?.mediumGenerator.prepare()
        }
    }
    
    /// Undo (Shake) - רטט הצלחה
    func undo() {
        notificationGenerator.notificationOccurred(.success)
    }
    
    // MARK: - UI Actions
    
    /// Selection - בחירה בממשק
    func selection() {
        selectionGenerator.selectionChanged()
    }
    
    /// Error - שגיאה
    func error() {
        notificationGenerator.notificationOccurred(.error)
    }
    
    /// Success - הצלחה
    func success() {
        notificationGenerator.notificationOccurred(.success)
    }
    
    /// Warning - אזהרה
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }
    
    // MARK: - Batch Delete
    
    /// Empty Trash - רטט כבד להדגשת הפעולה הסופית
    func emptyTrash() {
        // Triple heavy impact
        heavyGenerator.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.heavyGenerator.impactOccurred(intensity: 1.0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.heavyGenerator.impactOccurred(intensity: 1.0)
            self?.heavyGenerator.prepare()
        }
    }
}
