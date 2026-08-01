//
//  View+Extensions.swift
//  CleanSwipe
//
//  Extensions כלליים עבור SwiftUI Views
//

import SwiftUI

extension View {
    /// הוספת shadow עם ערכי default נוחים
    func cardShadow() -> some View {
        self.shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
    
    /// Haptic feedback מהיר
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) -> some View {
        self.onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred()
        }
    }
    
    /// Conditional modifier - מאפשר להוסיף modifier רק אם condition מתקיים
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Animated rotation עבור הקלפים בסטאק
    func stackRotation(_ angle: Double, offset: CGSize = .zero) -> some View {
        self
            .rotationEffect(.degrees(angle))
            .offset(offset)
    }
    
    /// הוספת זיהוי ניעור (Shake) למכשיר
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(DeviceShakeViewModifier(action: action))
    }

    /// Gold gradient fill + glow shadow — premium CTA / selected paywall pricing tier.
    func premiumGoldBackground(cornerRadius: CGFloat) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.86, blue: 0.3),
                            Color(red: 0.95, green: 0.63, blue: 0.10),
                            Color(red: 0.82, green: 0.50, blue: 0.02),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 1.0, green: 0.75, blue: 0.15).opacity(0.55), radius: 22, y: 8)
        )
    }
}

// MARK: - Shake Support Internal
extension NSNotification.Name {
    static let deviceDidShake = NSNotification.Name("MyDeviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

struct DeviceShakeViewModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}

// MARK: - Color Extensions
extension Color {
    static let swipeGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let swipeRed = Color(red: 0.95, green: 0.3, blue: 0.3)
    static let swipeYellow = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let swipeBlue = Color(red: 0.25, green: 0.55, blue: 0.95)
    static let cardBackground = Color(UIColor.systemBackground)
    static let dimmedBackground = Color.black.opacity(0.3)
    // Shuffle mode accent gradient — FAB, capsule glow border, mode badge.
    static let shuffleAccentStart = Color(red: 0.2, green: 0.5, blue: 1.0)
    static let shuffleAccentEnd = Color(red: 0.5, green: 0.2, blue: 0.9)
}

// MARK: - UIApplication Extensions
extension UIApplication {
    /// פותח את מסך ההגדרות של האפליקציה — למשל אחרי דחיית הרשאת גלריה/התראות.
    func openSettings() {
        guard let url = URL(string: Self.openSettingsURLString), canOpenURL(url) else { return }
        open(url)
    }
}

// MARK: - CGSize Extensions
extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }

    var magnitude: CGFloat {
        sqrt(width * width + height * height)
    }
}

// MARK: - Delayed Loading Indicator

/// Overlays `indicator` only if `isReady` is still false `delay` after this view
/// appeared — avoids a spinner flash on the common fast-load case. Generalizes the
/// Task.sleep + cancel-guard + withAnimation pattern used by PhotoCardView's
/// imageSpinnerTask/videoSpinnerTask (kept as-is there — that file is performance-
/// critical and already tuned; this modifier is for new call sites, not a retrofit).
struct DelayedIndicator<IndicatorContent: View>: ViewModifier {
    let isReady: Bool
    let delay: Duration
    @ViewBuilder let indicator: () -> IndicatorContent

    @State private var showIndicator = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay {
                if showIndicator && !isReady {
                    indicator()
                }
            }
            .onAppear {
                // `onAppear`'s closure only runs once per mount, so it can't re-read `isReady`
                // as it changes over the view's lifetime — the check that actually matters is
                // the live one in `.overlay` above, which re-evaluates on every body render.
                // Setting showIndicator unconditionally here is safe: if isReady already flipped
                // true by the time this fires, the overlay's own `!isReady` keeps it hidden.
                task = Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.2)) { showIndicator = true }
                }
            }
            .onDisappear { task?.cancel() }
    }
}

extension View {
    /// See `DelayedIndicator`.
    func delayedIndicator<Content: View>(
        isReady: Bool,
        after delay: Duration = .milliseconds(500),
        @ViewBuilder indicator: @escaping () -> Content
    ) -> some View {
        modifier(DelayedIndicator(isReady: isReady, delay: delay, indicator: indicator))
    }
}

// MARK: - Transition Extensions

extension AnyTransition {
    /// Forward-navigation transition — incoming content enters from the right,
    /// outgoing content exits to the left. Plain `.move(edge:)` is safe here (not
    /// a raw offset) because `SwipyApp` pins `\.layoutDirection` to `.leftToRight`
    /// app-wide, so `.trailing`/`.leading` always resolve to right/left consistently —
    /// see SwipyApp.swift for why that override exists.
    /// Used by OnboardingView's step transitions and SplashScreenView's handoff.
    static var pushForward: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}
