//
//  SwipeIndicator.swift
//  CleanSwipe
//
//  אינדיקטור שמראה את כיוון ה-Swipe
//

import SwiftUI

/// Pure content — no longer computes its own opacity/scale from `offset`. Callers (see
/// CardStackView) apply those via `.visualEffect` from outside instead, since reading a
/// per-frame drag value directly inside this view's own `body` would force a re-diff of
/// whatever ancestor constructs it on every `.onChanged` frame. `direction` is expected
/// to change rarely (only at threshold crossings), unlike a raw offset/magnitude.
struct SwipeIndicator: View {
    let direction: SwipeDirection

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
        .frame(
            maxWidth: .infinity,
            maxHeight: direction == .up ? .infinity : nil,
            alignment: direction == .right ? .trailing
                     : direction == .left  ? .leading
                     : direction == .up    ? .top
                     : .center
        )
        .padding(.horizontal, 40)
        .padding(.top, direction == .up ? 60 : 0)
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
            Text("🤷‍♂️")
                .font(.title)
            Text(String(localized: "swipe.later"))
                .font(.headline)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.swipeBlue.gradient)
        )
        .shadow(color: .swipeBlue.opacity(0.5), radius: 10)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        
        VStack(spacing: 40) {
            SwipeIndicator(direction: .left)
            SwipeIndicator(direction: .right)
            SwipeIndicator(direction: .up)
        }
    }
}
