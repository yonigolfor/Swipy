
//
//  OnboardingView.swift
//  CleanSwipe
//
//  5-step onboarding flow shown only on first launch.
//  Step 1: Visual Hook    — animated photo stack
//  Step 2: Scan           — real PHAsset counts with animated counters
//  Step 3: Swipe Demo     — interactive swipe tutorial
//  Step 4: Permission     — pre-permission screen before iOS prompt
//  Step 5: Quick Win      — transition into the app
//

import SwiftUI
import Photos

struct OnboardingView: View {

    @ObservedObject var viewModel: PhotoStackViewModel
    /// Called when onboarding completes — parent should show ContentView.
    let onComplete: () -> Void

    @State private var currentStep = 0

    // Step 3 demo swipe state
    @State private var demoOffset: CGSize = .zero
    @State private var demoRotation: Double = 0
    @State private var demoCardVisible = true
    @State private var demoLabel: String? = nil

    private let totalSteps = 5
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        ZStack {
            // Dark premium background consistent with SplashScreen
            Color(red: 0.08, green: 0.08, blue: 0.10)
                .ignoresSafeArea()

            // Step content
            Group {
                switch currentStep {
                case 0: step1_VisualHook
                case 1: step2_Scan
                case 2: step3_SwipeDemo
                case 3: step4_Permission
                case 4: step5_QuickWin
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(currentStep) // Forces transition on step change
        }
        .onAppear { haptic.prepare(); softHaptic.prepare() }
    }

    // MARK: - Step 1: Visual Hook

    private var step1_VisualHook: some View {
        VStack(spacing: 40) {
            Spacer()

            // Stacked photos animation
            ZStack {
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(white: 0.25 - Double(i) * 0.03),
                                    Color(white: 0.18 - Double(i) * 0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 220, height: 280)
                        .rotationEffect(.degrees(Double(i - 2) * 6))
                        .offset(y: CGFloat(i) * 6)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                }

                // Top card with photo icon
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.28), Color(white: 0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 220, height: 280)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            Text("10,000+")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("photos & videos")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
            }
            .padding(.bottom, 20)

            VStack(spacing: 16) {
                Text(String(localized: "onboarding.hook.title"))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(String(localized: "onboarding.hook.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 32)

            Spacer()

            // Gold CTA button
           Button {
                haptic.impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    currentStep = 3 // Jump directly to Permission screen
                }
            } label: {
                Text(String(localized: "onboarding.hook.cta"))
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.85, blue: 0.3),
                                             Color(red: 1, green: 0.65, blue: 0.1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5),
                            radius: 15, y: 5)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 2: Scan

    private var step2_Scan: some View {
        VStack(spacing: 32) {
            Spacer()

            // Glassmorphic scan card
            VStack(spacing: 24) {
                // Header
                HStack {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text(String(localized: "onboarding.scan.title"))
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    if viewModel.onboardingScanComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Divider().background(Color.white.opacity(0.15))

               // Scan results
                VStack(spacing: 16) {
                    scanRow(
                        icon: "photo.fill",
                        label: String(localized: "onboarding.scan.photos"),
                        value: viewModel.onboardingPhotoCount,
                        isScanning: viewModel.onboardingPhotoCount == 0 && !viewModel.onboardingScanComplete,
                        color: .blue
                    )
                    scanRow(
                        icon: "video.fill",
                        label: String(localized: "onboarding.scan.videos"),
                        value: viewModel.onboardingVideoCount,
                        isScanning: viewModel.onboardingVideoCount == 0 && !viewModel.onboardingScanComplete,
                        color: .purple
                    )
                    scanRow(
                        icon: "film.fill",
                        label: String(localized: "onboarding.scan.large_videos"),
                        value: viewModel.onboardingLargeVideoCount,
                        isScanning: viewModel.onboardingLargeVideoCount == 0 && !viewModel.onboardingScanComplete,
                        color: .orange
                    )
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    }
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(.horizontal, 24)

            // Privacy note
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(String(localized: "onboarding.scan.privacy"))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(spacing: 12) {
                // Primary CTA — appears when scan completes
                if viewModel.onboardingScanComplete {
                    Button {
                        haptic.impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            currentStep = 4
                        }
                    } label: {
                        Text(String(localized: "onboarding.scan.cta"))
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Color(red: 1, green: 0.85, blue: 0.3),
                                                 Color(red: 1, green: 0.65, blue: 0.1)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                            )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Skip button — always visible while scanning
                if !viewModel.onboardingScanComplete {
                    Button {
                        haptic.impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            currentStep = 4
                        }
                    } label: {
                        Text(String(localized: "onboarding.scan.skip"))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.vertical, 12)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 3: Swipe Demo

    private var step3_SwipeDemo: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text(String(localized: "onboarding.demo.title"))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(String(localized: "onboarding.demo.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            // Demo card
            ZStack {
                // Shadow card behind
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.18))
                    .frame(width: 240, height: 300)
                    .offset(y: 10)
                    .scaleEffect(0.95)

                // Main demo card
                if demoCardVisible {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.28), Color(white: 0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 240, height: 300)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.3))
                                Text(String(localized: "onboarding.demo.hint"))
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .overlay {
                            // Swipe label overlay
                            if let label = demoLabel {
                                Text(label)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(demoOffset.width < 0 ? .red : .green)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill((demoOffset.width < 0 ? Color.red : Color.green).opacity(0.2))
                                    )
                                    .rotationEffect(.degrees(demoOffset.width < 0 ? -15 : 15))
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .rotationEffect(.degrees(demoRotation))
                        .offset(demoOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let dx = value.translation.width
                                    demoOffset = CGSize(width: dx, height: value.translation.height)
                                    demoRotation = Double(dx / 20)
                                    withAnimation(.spring(response: 0.2)) {
                                        demoLabel = dx < -30 ? String(localized: "swipe.delete") :
                                                    dx > 30 ? String(localized: "swipe.keep") : nil
                                    }
                                    softHaptic.impactOccurred()
                                }
                                .onEnded { value in
                                    if abs(value.translation.width) > 80 {
                                        // Card flies off screen
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            demoOffset = CGSize(
                                                width: value.translation.width > 0 ? 500 : -500,
                                                height: value.translation.height
                                            )
                                        }
                                        haptic.impactOccurred()
                                        // Reset card after 0.6s
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                            demoCardVisible = false
                                            demoOffset = .zero
                                            demoRotation = 0
                                            demoLabel = nil
                                            withAnimation(.spring(response: 0.4)) {
                                                demoCardVisible = true
                                            }
                                        }
                                    } else {
                                        // Snap back
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            demoOffset = .zero
                                            demoRotation = 0
                                            demoLabel = nil
                                        }
                                    }
                                }
                        )
                        .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .frame(height: 320)

            Text(String(localized: "onboarding.demo.hint"))
                .font(.caption)
                .foregroundColor(.gray)

            Spacer()

            Button {
                haptic.impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    currentStep = 1
                }
            } label: {
                Text(String(localized: "onboarding.demo.cta"))
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(red: 1, green: 0.85, blue: 0.3),
                                         Color(red: 1, green: 0.65, blue: 0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 4: Permission

    private var step4_Permission: some View {
        VStack(spacing: 32) {
            Spacer()

            // Lock icon with glow
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 16) {
                Text(String(localized: "onboarding.permission.title"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(String(localized: "onboarding.permission.subtitle"))
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)

            // Privacy bullets
            VStack(alignment: .leading, spacing: 14) {
                privacyRow(icon: "iphone", text: String(localized: "onboarding.permission.local"))
                privacyRow(icon: "eye.slash.fill", text: String(localized: "onboarding.permission.private"))
                privacyRow(icon: "trash.slash.fill", text: String(localized: "onboarding.permission.control"))
            }
            .padding(.horizontal, 40)

            Spacer()

            Button {
                haptic.impactOccurred()
                requestPermission()
            } label: {
                Text(String(localized: "onboarding.permission.cta"))
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(red: 1, green: 0.85, blue: 0.3),
                                         Color(red: 1, green: 0.65, blue: 0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
                    .shadow(color: Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5),
                            radius: 15, y: 5)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 5: Quick Win

    private var step5_QuickWin: some View {
        VStack(spacing: 32) {
            Spacer()

            // Checkmark with glow
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(Color.green.opacity(0.08))
                    .frame(width: 180, height: 180)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .shadow(color: .green.opacity(0.5), radius: 20)
            }

            VStack(spacing: 16) {
                Text(String(localized: "onboarding.quickwin.title"))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(String(localized: "onboarding.quickwin.subtitle"))
                    .font(.body)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button {
                haptic.impactOccurred()
                onComplete()
            } label: {
                Text(String(localized: "onboarding.quickwin.cta"))
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(red: 1, green: 0.85, blue: 0.3),
                                         Color(red: 1, green: 0.65, blue: 0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
                    .shadow(color: Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5),
                            radius: 15, y: 5)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Helpers

    private func scanRow(icon: String, label: String, value: Int, isScanning: Bool = false, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.white.opacity(0.8))
                .font(.subheadline)
            Spacer()
            if isScanning {
                // Pulsing dots to show active scanning
                ScanningDotsView(color: color)
            } else {
                Text("\(value)")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: value)
            }
        }
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    /// Requests photo library permission then advances to step 5.
    private func requestPermission() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                // Immediately show Swipe Demo while scan runs in background
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    currentStep = 2
                }
                // Start scan in background — numbers will be ready by the time
                // user finishes the demo and reaches the Scan screen
                viewModel.startOnboardingScan()
            }
        }
    }
}

// MARK: - Scanning Dots Animation

struct ScanningDotsView: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1.0 : 0.4)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(i) * 0.2),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

#Preview {
    OnboardingView(viewModel: PhotoStackViewModel(), onComplete: {})
}
