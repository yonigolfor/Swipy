import SwiftUI

// MARK: - SharePhase

enum SharePhase: Equatable {
    case idle
    case downloading(Double)  // 0.0–1.0
    case processing
    case complete

    static func == (lhs: SharePhase, rhs: SharePhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.processing, .processing), (.complete, .complete): return true
        case let (.downloading(a), .downloading(b)): return a == b
        default: return false
        }
    }
}

// MARK: - ShareHUDManager

/// Manages the floating UIWindow that hosts ShareHUDView above all other UI (including the system share sheet).
@MainActor
final class ShareHUDManager: ObservableObject {
    static let shared = ShareHUDManager()
    @Published private(set) var phase: SharePhase = .idle
    private(set) var isVisible: Bool = false
    private var window: UIWindow?
    private var cancelAction: (() -> Void)?

    private init() {}

    func show(onCancel: @escaping () -> Void) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive }) else { return }
        cancelAction = onCancel

        let host = UIHostingController(rootView: ShareHUDView().environmentObject(self))
        host.view.backgroundColor = .clear

        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.rootViewController = host
        w.alpha = 0
        w.makeKeyAndVisible()
        window = w
        isVisible = true
        UIView.animate(withDuration: 0.2) { w.alpha = 1 }
    }

    func update(_ newPhase: SharePhase) {
        phase = newPhase
    }

    func hide() {
        guard let w = window else { return }
        window = nil
        isVisible = false
        cancelAction = nil
        UIView.animate(withDuration: 0.25) { w.alpha = 0 } completion: { [weak self] _ in
            w.isHidden = true
            // Only reset phase once the fade completes and no new share has started.
            if self?.window == nil { self?.phase = .idle }
        }
    }

    func triggerCancel() {
        cancelAction?()
    }
}

