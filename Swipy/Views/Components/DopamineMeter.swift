//
//  DopamineMeter.swift
//  CleanSwipe
//
//  מונה החיסכון בחלק העליון של המסך
//

import SwiftUI

struct DopamineMeter: View {
    let spaceSaved: String
    let itemCount: Int
    
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.swipeGreen)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: isAnimating)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "meter.space_saved"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(spaceSaved)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
            }
            
            Spacer()
            
            // Item count badge
            if itemCount > 0 {
                VStack(spacing: 2) {
                    Text("\(itemCount)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("items")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.swipeRed.gradient)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        )
        .padding(.horizontal)
        .onChange(of: spaceSaved) { oldValue, newValue in
            // Trigger animation when value changes
            withAnimation(.spring(response: 0.3)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAnimating = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DopamineMeter(spaceSaved: "0 MB", itemCount: 0)
        DopamineMeter(spaceSaved: "245.3 MB", itemCount: 12)
        DopamineMeter(spaceSaved: "1.8 GB", itemCount: 47)
    }
    .padding()
}
