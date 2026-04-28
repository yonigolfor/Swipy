//
//  SwipeIndicator.swift
//  CleanSwipe
//
//  אינדיקטור שמראה את כיוון ה-Swipe
//

import SwiftUI

struct SwipeIndicator: View {
    let direction: SwipeDirection
    let offset: CGSize
    
    private var opacity: Double {
        let distance = offset.magnitude
        return min(distance / 100, 1.0)
    }
    
    private var scale: CGFloat {
    let distance = offset.magnitude
    return min(distance / 100, 1.0)
}
    
    var body: some View {
        Group {
            switch direction {
            case .left:
                deleteIndicator
                
            case .right:
                keepIndicator
                
            case .up:
                starIndicator
                
            case .none:
                EmptyView()
            }
        }
        .opacity(opacity)
.scaleEffect(scale)
.frame(maxWidth: .infinity, alignment: direction == .right ? .trailing : direction == .left ? .leading : .center)
.padding(.horizontal, 40)
.animation(nil, value: scale)
    }
    
    // MARK: - Indicators
    
    private var deleteIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.fill")
                .font(.title)
            Text(String(localized: "swipe.delete"))
                .font(.headline)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.swipeRed.gradient)
        )
        .shadow(color: .swipeRed.opacity(0.5), radius: 10)
    }
    
    private var keepIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
            Text(String(localized: "swipe.keep"))
                .font(.headline)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.swipeGreen.gradient)
        )
        .shadow(color: .swipeGreen.opacity(0.5), radius: 10)
    }
    
    private var starIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.title)
            Text(String(localized: "swipe.later"))
                .font(.headline)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.swipeYellow.gradient)
        )
        .shadow(color: .swipeYellow.opacity(0.5), radius: 10)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        
        VStack(spacing: 40) {
            SwipeIndicator(
                direction: .left,
                offset: CGSize(width: -100, height: 0)
            )
            
            SwipeIndicator(
                direction: .right,
                offset: CGSize(width: 100, height: 0)
            )
            
            SwipeIndicator(
                direction: .up,
                offset: CGSize(width: 0, height: -100)
            )
        }
    }
}
