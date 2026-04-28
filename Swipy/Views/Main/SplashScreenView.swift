import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var size = 0.7
    @State private var opacity = 0.4
    
    var body: some View {
        if isActive {
            if hasCompletedOnboarding {
                ContentView()
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

