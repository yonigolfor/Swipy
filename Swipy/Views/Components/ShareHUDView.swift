import SwiftUI

struct ShareHUDView: View {
    @EnvironmentObject var hud: ShareHUDManager

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 14) {
                ringOrCheckmark
                    .frame(width: 60, height: 60)

                Text(phaseLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .id(phaseLabel)
                    .transition(.opacity)

                if !isComplete {
                    Button { hud.triggerCancel() } label: {
                        Text(String(localized: "share.hud.cancel"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 32, y: 10)
            .animation(.smooth, value: animationPhase)
        }
    }

    @ViewBuilder private var ringOrCheckmark: some View {
        ZStack {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.swipeGreen)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.15), value: progressFraction)
                    Text(percentText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: percentText)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Helpers

    private var isComplete: Bool { hud.phase == .complete }

    /// Integer phase category — used to trigger structural animations without
    /// firing on every tiny progress tick (which would re-animate the card layout).
    private var animationPhase: Int {
        switch hud.phase {
        case .idle:        return 0
        case .downloading: return 1
        case .processing:  return 2
        case .complete:    return 3
        }
    }

    private var progressFraction: Double {
        switch hud.phase {
        case .downloading(let p): return p
        case .processing, .complete: return 1.0
        case .idle: return 0
        }
    }

    private var percentText: String { "\(Int(progressFraction * 100))%" }

    private var phaseLabel: String {
        switch hud.phase {
        case .downloading: return String(localized: "share.hud.downloading")
        case .processing:  return String(localized: "share.hud.processing")
        case .complete:    return String(localized: "share.hud.complete")
        case .idle:        return ""
        }
    }
}
