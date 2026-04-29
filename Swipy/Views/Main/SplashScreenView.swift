import SwiftUI
import Photos

struct SplashScreenView: View {
    // ViewModel lives here so it is created once and survives the entire app session.
    // Hoisting it up from ContentView lets us kick off refreshCategoryCounts()
    // during the splash animation, giving Phase 1+2 a head start before the
    // user ever opens SmartFiltersView.
    @StateObject private var stackViewModel = PhotoStackViewModel()

    @State private var isActive = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var size = 0.7
    @State private var opacity = 0.4

    var body: some View {
        if isActive {
            if hasCompletedOnboarding {
                ContentView(stackViewModel: stackViewModel)
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
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
                    // Only pre-warm counts if permission is already granted.
                    // First-time users haven't granted access yet — fetching now
                    // would populate categoryCounts with zeros and prevent the
                    // lazy .task in SmartFiltersView from triggering a real refresh.
                    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    if status == .authorized || status == .limited {
                        stackViewModel.refreshCategoryCounts()
                    }
                    try? await Task.sleep(for: .seconds(1.3))
                    withAnimation { isActive = true }
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
}

