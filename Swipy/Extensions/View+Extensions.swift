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
    static let cardBackground = Color(UIColor.systemBackground)
    static let dimmedBackground = Color.black.opacity(0.3)
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
