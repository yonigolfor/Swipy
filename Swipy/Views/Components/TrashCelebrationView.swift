//
//  TrashCelebrationView.swift
//  CleanSwipe
//
//  Dopamine-hit overlay shown after the trash is emptied
//

import SwiftUI

struct TrashCelebrationView: View {
    let spaceSaved: String
    let itemCount: Int
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var emojiOffset: CGFloat = 0
    @State private var particlesVisible = false

    // Particle data — fixed so the view is deterministic
    private let particles: [(angle: Double, distance: CGFloat, size: CGFloat, color: Color)] = {
        let colors: [Color] = [.swipeGreen, .swipeYellow, .blue, .purple, .pink, .orange]
        var result: [(Double, CGFloat, CGFloat, Color)] = []
        for i in 0..<20 {
            result.append((
                Double(i) * 18.0,
                CGFloat.random(in: 100...220),
                CGFloat.random(in: 6...14),
                colors[i % colors.count]
            ))
        }
        return result
    }()

    var body: some View {
        ZStack {
            // Dimmed background — tap to dismiss
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Confetti particles
            ForEach(Array(particles.enumerated()), id: \.offset) { _, p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .offset(
                        x: particlesVisible ? cos(p.angle * .pi / 180) * p.distance : 0,
                        y: particlesVisible ? sin(p.angle * .pi / 180) * p.distance : 0
                    )
                    .opacity(particlesVisible ? 0 : 1)
                    .animation(
                        .easeOut(duration: 0.9).delay(0.1),
                        value: particlesVisible
                    )
            }

            // Main card
            VStack(spacing: 24) {

                // Trash icon with sparkle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.swipeGreen.opacity(0.25), Color.swipeGreen.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)

                    Text("🎉")
                        .font(.system(size: 62))
                        .offset(y: emojiOffset)
                        .animation(
                            .interpolatingSpring(stiffness: 180, damping: 8)
                                .repeatCount(3, autoreverses: true)
                                .delay(0.25),
                            value: emojiOffset
                        )
                }

                // Headline
                VStack(spacing: 8) {
                    Text("Space Reclaimed! 🚀")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("You freed up")
                        .font(.body)
                        .foregroundColor(.secondary)

                    // Big number
                    Text(spaceSaved)
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.swipeGreen, Color(red: 0.0, green: 0.7, blue: 0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text("by deleting \(itemCount) item\(itemCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Dismiss button
                Button(action: dismiss) {
                    Text("Awesome! 💪")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.swipeGreen, Color(red: 0.0, green: 0.7, blue: 0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(Capsule())
                        )
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
            )
            .padding(.horizontal, 32)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear { animateIn() }
    }

    // MARK: - Animations

    private func animateIn() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
            scale = 1.0
            opacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            emojiOffset = -12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation { particlesVisible = true }
        }
        // Auto-dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.25)) {
            scale = 0.8
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}

#Preview {
    TrashCelebrationView(
        spaceSaved: "1.84 GB",
        itemCount: 47,
        onDismiss: {}
    )
}
