import SwiftUI

struct SplashScreenView: View {
    // ViewModel lives here so it is created once and survives the entire app session.
    // Hoisting it up from ContentView lets us kick off refreshCategoryCounts()
    // during the splash animation, giving Phase 1+2 a head start before the
    // user ever opens SmartFiltersView.
    @StateObject private var stackViewModel = PhotoStackViewModel()

    @State private var isActive = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Drives the OnboardingView ↔ ContentView swap in `body`. Kept separate from
    /// the @AppStorage flag above because @AppStorage mutations don't reliably
    /// participate in a `withAnimation` transaction (a well-known SwiftUI gotcha) —
    /// wrapping `hasCompletedOnboarding = true` in `withAnimation` alone silently
    /// no-ops the transition and the swap just cuts, which is exactly the "abrupt,
    /// not smooth" symptom this was built to fix. Plain @State animates reliably,
    /// so this mirrors the flag purely for the transition; `hasCompletedOnboarding`
    /// remains the actual value persisted to disk across launches.
    @State private var showMainApp: Bool
    @State private var size = 0.7
    @State private var opacity = 0.4

    init() {
        // Seed from the persisted flag so a returning user (onboarding already
        // completed in a prior session) lands straight on ContentView, not
        // OnboardingView — @State's own default can't see @AppStorage's value.
        _showMainApp = State(initialValue: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))
    }

    /// Onboarding (incl. its embedded paywall page) slides out to the left while
    /// ContentView slides in from the right — the same horizontal language
    /// OnboardingView already uses between its own steps. `.pushForward` (not
    /// `.move(edge:)`) so this looks identical regardless of device language —
    /// see its doc comment in View+Extensions.swift for why that matters.
    private var handoffTransition: AnyTransition { .pushForward }

    var body: some View {
        Group {
            if isActive {
                if showMainApp {
                    ContentView(stackViewModel: stackViewModel)
                        .transition(handoffTransition)
                } else {
                    OnboardingView(viewModel: stackViewModel) {
                        // The paywall page's own dismiss IS this — see step6_Paywall.
                        hasCompletedOnboarding = true
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            showMainApp = true
                        }
                    }
                    .transition(handoffTransition)
                }
            } else {
                ZStack {
                    Color(red: 0.1, green: 0.1, blue: 0.12)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        Image("AppIconImage")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .cornerRadius(30)
                            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)

                        VStack(spacing: 8) {
                            Text("Swipy")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Declutter your memories")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .scaleEffect(size)
                    .opacity(opacity)
                }
                .onAppear {
                    withAnimation(.easeIn(duration: 1.0)) {
                        size = 1.0
                        opacity = 1.0
                    }
                    Task {
                        // Category counts are NOT refreshed here on purpose — the Swipe
                        // screen (the very next thing the user sees) is the #1 priority
                        // and must stay at 0 CPU contention from Vision/CIFilter work.
                        // PhotoStackViewModel.init()'s loadCachedAccurateCounts() already
                        // seeds categoryCounts from disk synchronously, so Smart Filters
                        // still shows last-known numbers instantly if the user gets there
                        // first — a fresh scan only fires from SmartFiltersView itself.
                        try? await Task.sleep(for: .seconds(1.3))
                        withAnimation { isActive = true }
                    }
                }
            }
        }
        #if DEBUG
        // SmartFiltersView's DEBUG reset button sets hasCompletedOnboarding = false, but
        // since showMainApp (above) only mirrors it at init time, that alone wouldn't
        // swap back to OnboardingView mid-session — this notification is the bridge.
        .onReceive(NotificationCenter.default.publisher(for: .debugResetOnboarding)) { _ in
            showMainApp = false
        }
        #endif
    }
}

#if DEBUG
extension Notification.Name {
    static let debugResetOnboarding = Notification.Name("debugResetOnboarding")
}
#endif

#Preview {
    SplashScreenView()
}
