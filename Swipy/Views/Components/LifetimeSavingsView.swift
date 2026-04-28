//
//  LifetimeSavingsView.swift
//  CleanSwipe
//

import SwiftUI

struct LifetimeSavingsView: View {
    let text: String

    @State private var animate = false

    var body: some View {
        VStack(spacing: 6) {
            Text(String(localized: "bin.lifetime_saved"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    .scaleEffect(animate ? 1.15 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: animate
                    )

                Text(text)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())

                Image(systemName: "leaf.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    .scaleEffect(animate ? 1.15 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: animate
                    )
            }

            Text(String(localized: "bin.breathing"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
        .onAppear { animate = true }
    }
}
