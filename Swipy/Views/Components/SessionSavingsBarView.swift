import SwiftUI

// MARK: - ChubbyStarShape

/// Custom 5-pointed star with a fat inner radius and rounded tips.
/// innerRatio 0.50 (vs 0.38 standard) gives short, chubby points with a thick belly.
private struct ChubbyStarShape: Shape {
    var innerRatio: CGFloat = 0.50
    var tipRounding: CGFloat = 0.26

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        let r = R * innerRatio
        let n = 5

        func outer(_ i: Int) -> CGPoint {
            let a = CGFloat(i) * (2 * .pi / CGFloat(n)) - .pi / 2
            return CGPoint(x: c.x + R * cos(a), y: c.y + R * sin(a))
        }
        func inner(_ i: Int) -> CGPoint {
            let a = CGFloat(i) * (2 * .pi / CGFloat(n)) - .pi / 2 + .pi / CGFloat(n)
            return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        var path = Path()
        for i in 0..<n {
            let o  = outer(i)
            let ip = inner((i + n - 1) % n)
            let ic = inner(i)
            let a1 = lerp(ip, o, 1 - tipRounding)
            let a2 = lerp(ic, o, 1 - tipRounding)
            if i == 0 { path.move(to: ip) }
            path.addLine(to: a1)
            path.addQuadCurve(to: a2, control: o)
            path.addLine(to: ic)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - LavaWaveShape

/// Fills a rect from the bottom up to `fillFraction`, with a living sine-wave top edge.
/// Two overlapping waves (opposite phase directions) create the lava-lamp slosh.
/// Clip this to ChubbyStarShape() to confine the fill to the star outline.
private struct LavaWaveShape: Shape {
    var fillFraction: Double  // 0..1
    var wavePhase: Double     // continuously increasing (radians), driven by TimelineView

    // Only fillFraction participates in SwiftUI animations.
    // wavePhase is driven by TimelineView at display refresh rate — not via withAnimation.
    var animatableData: Double {
        get { fillFraction }
        set { fillFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard fillFraction > 0.004 else { return Path() }

        // Shrink amplitude near empty/full so edges look clean
        let fade = min(fillFraction * 7, (1 - fillFraction) * 7, 1.0)
        let amplitude = Double(rect.height) * 0.11 * fade
        let baseY    = Double(rect.height) * (1 - fillFraction)
        let w        = Double(rect.width)
        let h        = Double(rect.height)

        func waveY(at t: Double) -> Double {
            // Primary wave: 1.5 cycles across width, moves left
            // Secondary wave: 2.5 cycles, moves right — creates organic lava feel
            baseY
                + amplitude * 0.62 * sin(t * .pi * 3.0 + wavePhase)
                + amplitude * 0.38 * sin(t * .pi * 5.0 - wavePhase * 1.35)
        }

        let steps = 90
        var path = Path()

        // Outline: bottom-left → bottom-right → wavy top (right→left) → close
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w, y: waveY(at: 1.0)))

        for i in stride(from: steps - 1, through: 0, by: -1) {
            let t = Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: w * t, y: waveY(at: t)))
        }

        path.closeSubpath()  // straight line back to (0, h)
        return path
    }
}

// MARK: - SessionSavingsConfig

/// Single source of truth for the milestone threshold.
/// In DEBUG builds the threshold drops to 50 MB so the celebration can be
/// triggered quickly during development without deleting a full gigabyte.
private enum SessionSavingsConfig {
    #if DEBUG
    static let milestoneThreshold: Double = 50
    static let milestoneUnit = "50M"
    #else
    static let milestoneThreshold: Double = 1000
    static let milestoneUnit = "GB"
    #endif
}

// MARK: - SessionSavingsBarView

/// Compact gamified top bar showing space saved in the current session.
/// sessionMB: cumulative megabytes deleted this session (monotonically increasing).
struct SessionSavingsBarView: View {
    let sessionMB: Double

    // MARK: Derived values

    private var progressFraction: Double {
        let t = SessionSavingsConfig.milestoneThreshold
        return sessionMB.truncatingRemainder(dividingBy: t) / t
    }
    private var milestoneCount: Int { Int(sessionMB / SessionSavingsConfig.milestoneThreshold) }
    private var currentMB: Double {
        sessionMB.truncatingRemainder(dividingBy: SessionSavingsConfig.milestoneThreshold)
    }

    // MARK: Animation state

    @State private var animatedProgress: Double = 0
    /// Drives the lava fill inside the star — drains with easeIn after each GB milestone.
    @State private var starFill: Double = 0
    @State private var celebrationTrigger = 0
    /// True while the fill-to-1 → celebration → drain → remainder sequence is in flight.
    @State private var isGBTransitioning = false

    // MARK: Body

    var body: some View {
        HStack(spacing: 14) {
            progressSection
            starSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: milestoneCount) { old, new in
            guard new > old else { return }
            isGBTransitioning = true

            // Step 1: fill bar and star to 100%
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                animatedProgress = 1.0
                starFill = 1.0
            }

            Task { @MainActor in
                // Wait for fill to visually peak at 1.0
                try? await Task.sleep(for: .milliseconds(360))

                // Step 2: star celebration
                celebrationTrigger += 1
                triggerHapticBurst()

                // Step 3: after star cycle — bar snaps to remainder, star drains with easeIn
                try? await Task.sleep(for: .milliseconds(CelebrationPhase.totalDurationMS))

                // Bar: instant reset then spring to remainder
                animatedProgress = 0
                withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                    animatedProgress = progressFraction
                }

                // Star: lava drains out (slow start → accelerating, like liquid emptying)
                withAnimation(.easeIn(duration: 0.65)) {
                    starFill = 0
                }
                try? await Task.sleep(for: .milliseconds(680))

                // Re-sync star with bar after drain completes
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    starFill = progressFraction
                }
                isGBTransitioning = false
            }
        }
        .onChange(of: progressFraction) { _, new in
            guard !isGBTransitioning else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                animatedProgress = new
                starFill = new
            }
        }
        .onAppear {
            animatedProgress = progressFraction
            starFill = progressFraction
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(mbLabel)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.3), value: currentMB)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.3, green: 0.65, blue: 1.0),
                                    Color(red: 0.55, green: 0.3, blue: 0.95)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * animatedProgress))
                }
            }
            .frame(height: 12)

            HStack(spacing: 3) {
                Text(String(localized: "meter.space_saved"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mbLabel: String {
        String(format: "%.0f MB", currentMB)
    }

    // MARK: - Star Section

    private static let starSize: CGFloat = 68

    private var starSection: some View {
        PhaseAnimator(
            CelebrationPhase.allCases,
            trigger: celebrationTrigger
        ) { phase in
            ZStack {
                // Arms — outside rotationEffect so they stay pinned while the star spins
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.yellow)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -44, y: 10)
                    .opacity(phase.showArms ? 1 : 0)

                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.yellow)
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(30))
                    .offset(x: 44, y: 10)
                    .opacity(phase.showArms ? 1 : 0)

                // Star body — rotates and scales as one unit
                ZStack {
                    // Dim background star
                    ChubbyStarShape()
                        .fill(Color.primary.opacity(0.13))
                        .frame(width: Self.starSize, height: Self.starSize)

                    // Lava-wave fill — continuous sine wave clipped to star outline
                    TimelineView(.animation) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate * 1.6
                        LavaWaveShape(fillFraction: starFill, wavePhase: phase)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.72, blue: 0.0),
                                        Color(red: 1.0, green: 0.88, blue: 0.15)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                    }
                    .clipShape(ChubbyStarShape())
                    .frame(width: Self.starSize, height: Self.starSize)

                    // Milestone count + unit label, centered on star body
                    if milestoneCount > 0 {
                        VStack(spacing: 0) {
                            Text("\(milestoneCount)")
                                .font(.system(size: 19, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                            Text(SessionSavingsConfig.milestoneUnit)
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black.opacity(0.8))
                        }
                        .offset(y: 1)
                    }
                }
                .rotationEffect(.degrees(phase.starRotation))
                .scaleEffect(phase.starScale)
            }
            .frame(width: 92, height: 76)
        } animation: { phase in
            phase.animation
        }
    }

    // MARK: - Haptics

    /// Multi-beat haptic burst: medium build → double heavy peak → success ding.
    private func triggerHapticBurst() {
        Task { @MainActor in
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            let medium = UIImpactFeedbackGenerator(style: .medium)
            let notif = UINotificationFeedbackGenerator()
            heavy.prepare(); medium.prepare(); notif.prepare()

            medium.impactOccurred(intensity: 0.7)
            try? await Task.sleep(for: .milliseconds(85))
            heavy.impactOccurred(intensity: 0.9)
            try? await Task.sleep(for: .milliseconds(85))
            heavy.impactOccurred(intensity: 1.0)
            try? await Task.sleep(for: .milliseconds(90))
            medium.impactOccurred(intensity: 0.8)
            try? await Task.sleep(for: .milliseconds(95))
            heavy.impactOccurred(intensity: 1.0)
            try? await Task.sleep(for: .milliseconds(70))
            notif.notificationOccurred(.success)
        }
    }
}

// MARK: - CelebrationPhase

private enum CelebrationPhase: CaseIterable {
    case idle, windup, spin, settle

    var starRotation: Double {
        switch self {
        case .idle:   0
        case .windup: 8
        case .spin:   -352  // 8° → -352° = full 360° left spin
        case .settle: 0
        }
    }

    var starScale: Double {
        switch self {
        case .idle:   1.0
        case .windup: 1.15
        case .spin:   1.25
        case .settle: 1.0
        }
    }

    var showArms: Bool { self == .spin }

    var animation: Animation {
        switch self {
        case .idle:   .spring(response: 0.38, dampingFraction: 0.70)
        case .windup: .easeOut(duration: 0.10)
        case .spin:   .easeInOut(duration: 0.42)
        case .settle: .spring(response: 0.38, dampingFraction: 0.58)
        }
    }

    /// Approximate visual settle time for each phase (ms).
    /// Used to synchronise the bar's post-celebration animation with the star's return to idle.
    var durationMS: Int {
        switch self {
        case .idle:   480  // spring(response:0.38, damping:0.70)
        case .windup: 100
        case .spin:   420
        case .settle: 560  // underdamped spring(response:0.38, damping:0.58)
        }
    }

    /// Full cycle duration: windup + spin + settle + return-to-idle.
    static var totalDurationMS: Int { allCases.map(\.durationMS).reduce(0, +) }
}

// MARK: - Preview

#Preview {
    @Previewable @State var sessionMB: Double = 0

    VStack(spacing: 0) {
        ZStack {
            Rectangle()
                .fill(.bar)
                .frame(height: 56)
                .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
            SessionSavingsBarView(sessionMB: sessionMB)
        }
        .frame(height: 56)

        Spacer()

        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("\(Int(sessionMB)) MB נמחקו בסשן")
                    .font(.title3).bold()
                Text("\(SessionSavingsConfig.milestoneUnit) שנצברו: \(Int(sessionMB / SessionSavingsConfig.milestoneThreshold))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let step = SessionSavingsConfig.milestoneThreshold
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button("+\(Int(step * 0.1)) MB")  { sessionMB += step * 0.1 }  .buttonStyle(.bordered)
                    Button("+\(Int(step * 0.5)) MB")  { sessionMB += step * 0.5 }  .buttonStyle(.bordered)
                    Button("+1 \(SessionSavingsConfig.milestoneUnit)") { sessionMB += step } .buttonStyle(.bordered)
                }
                HStack(spacing: 10) {
                    Button("+\(Int(step * 0.25)) MB") { sessionMB += step * 0.25 } .buttonStyle(.bordered)
                    Button("← Reset")  { sessionMB = 0 }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }
        }
        .padding()

        Spacer()
    }
    .background(Color(UIColor.secondarySystemBackground))
}
