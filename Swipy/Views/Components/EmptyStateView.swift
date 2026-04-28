//
//  EmptyStateView.swift
//  CleanSwipe
//
//  מסך שמוצג כשאין תמונות
//

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let icon: String
    var actionTitle: String?
    var action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 10)
            
            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            // Message
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Action button
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.blue.gradient)
                        )
                }
                .padding(.top, 10)
            }
        }
        .padding()
    }
}

// MARK: - Preset Empty States

extension EmptyStateView {
    static var noPhotos: EmptyStateView {
        EmptyStateView(
            title: "No Photos",
            message: "Your photo library is empty or you haven't granted access.",
            icon: "photo.stack"
        )
    }
    
    static var allDone: EmptyStateView {
        EmptyStateView(
            title: "All Done! 🎉",
            message: "You've reviewed all photos in this category.",
            icon: "checkmark.circle.fill"
        )
    }
    
    static var emptyBin: EmptyStateView {
        EmptyStateView(
            title: String(localized: "bin.empty_title"),
            message: String(localized: "bin.empty_message"),
            icon: "trash"
        )
    }
    
    static func categoryEmpty(_ category: FilterCategory) -> EmptyStateView {
        EmptyStateView(
            title: "No \(category.rawValue)",
            message: "No items found in this category.",
            icon: category.icon
        )
    }
}

#Preview {
    VStack(spacing: 50) {
        EmptyStateView.noPhotos
        
        EmptyStateView.allDone
        
        EmptyStateView(
            title: "Custom Title",
            message: "Custom message here",
            icon: "star.fill",
            actionTitle: "Tap Me"
        ) {
            print("Action tapped")
        }
    }
}
