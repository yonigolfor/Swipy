//
//  SwipeAction.swift
//  CleanSwipe
//
//  הגדרת סוגי המחוות והפעולות
//

import Foundation

/// סוג הפעולה שמבצעים על תמונה
enum SwipeAction {
    case keep        // החזק (swipe right)
    case delete      // מחק (swipe left)
    case snooze      // השהה לאחר כך (swipe up) — מוחזרת לסטאק אחרי N החלקות
    case undo        // ביטול (shake)
}

/// כיוון ההחלקה
enum SwipeDirection {
    case left
    case right
    case up
    case none
    
    /// המרה מ-offset לכיוון
    static func from(offset: CGSize) -> SwipeDirection {
        let threshold: CGFloat = 80
        
        // בדיקת swipe למעלה (קודם כי הוא יותר חשוב)
        if offset.height < -threshold && abs(offset.width) < threshold {
            return .up
        }
        
        // Swipe אופקי
        if abs(offset.width) > threshold {
            return offset.width > 0 ? .right : .left
        }
        
        return .none
    }
    
    /// הפעולה המתאימה לכיוון
    var action: SwipeAction? {
        switch self {
        case .left: return .delete
        case .right: return .keep
        case .up: return .snooze
        case .none: return nil
        }
    }
}
