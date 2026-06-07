//
//  SwipeStackView.swift
//  CleanSwipe
//
//  המסך הראשי עם סטאק הקלפים ומנוע ה-Swipe
//

import SwiftUI
import Photos

struct SwipeStackView: View {
    // Use the shared VM passed from ContentView — fixes the ReviewBin empty bug
    @EnvironmentObject private var viewModel: PhotoStackViewModel
    @Binding var selectedTab: Int
    @State private var dragOffset: CGSize = .zero
    @State private var dragRotation: Double = 0

    // Particle explosion state
    @State private var showParticles = false
    @State private var particleOrigin: CGPoint = .zero
    // Top-right destination — DopamineMeter is centered but particles fly to top-right
    private let meterDestination = CGPoint(x: UIScreen.main.bounds.width - 40, y: 55)
    private let largeFileSizeThreshold: Int64 = 2_000_000 // 2 MB for dev

    // Shuffle / Offline animation state (shared card stack transforms)
    @State private var cardStackOffset: CGFloat = 0
    @State private var cardStackOpacity: Double = 1
    @State private var cardStackScale: CGFloat = 1
    /// True between shuffle fly-out and its landing — prevents double-trigger.
    @State private var awaitingShuffleLanding = false
    /// True between offline-mode fly-out and its landing — prevents double-trigger.
    @State private var awaitingOfflineLanding = false

    // Time / mode indicator overlay
    @State private var showTimeIndicator = false
    @State private var timeIndicatorText = ""
    /// Small label shown above the bold indicator text. Set per-transition type.
    @State private var timeIndicatorHeader = ""

    /// Prevents firing prepareUpcomingCards() more than once per gesture.
    @State private var hasFiredEarlyPrecache = false
    /// True between drag start and drag end — used to cancel/resume pre-fetch.
    @State private var isDragging = false

    // Shake hint toast — shown once after the user's 3rd swipe (first session only).
    @AppStorage("shakeHintSwipeCount") private var shakeHintSwipeCount = 0
    @AppStorage("hasSeenShakeHint") private var hasSeenShakeHint = false
    @State private var showShakeHintToast = false

    private let cardStackSize = 3 // כמה קלפים מציגים מאחור

    var body: some View {
        // Outer ZStack: background | card column | DopamineMeter floating on top.
        // DopamineMeter MUST be a direct child of this ZStack (not buried inside
        // the VStack) so that .zIndex(100) has real effect against the cards.
        ZStack(alignment: .top) {
            // 1. Background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            // 2. Column: spacer gap + cards + instructions
            VStack(spacing: 0) {
                // Reserve the same vertical space DopamineMeter will occupy
                // so the cards don't slide underneath it (≈ 90pt incl. padding).
                Color.clear.frame(height: 90)

                // Card Stack — force LTR so swipe physics are always consistent:
                // right = Keep, left = Delete, regardless of device language.
                GeometryReader { geometry in
                    ZStack {
                        if viewModel.isOfflineMode && viewModel.isScanning && viewModel.photoStack.isEmpty {
                            offlineScanningView
                        } else if viewModel.isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text(String(localized: "loading.scanning"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else if viewModel.photoStack.isEmpty {
                            VictoryView(
                                onEmptyBin: { selectedTab = 2 },
                                onImportPhotos: PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited ? {
                                    guard let url = URL(string: UIApplication.openSettingsURLString),
                                          UIApplication.shared.canOpenURL(url) else { return }
                                    UIApplication.shared.open(url)
                                } : nil,
                                onReviewSnoozed: viewModel.pendingSnoozedCount > 0 ? { viewModel.flushSnoozedItemsNow() } : nil,
                                reviewBinCount: viewModel.reviewBin.count,
                                snoozedCount: viewModel.pendingSnoozedCount,
                                currentFilter: viewModel.currentFilter,
                                isOfflineMode: viewModel.isOfflineMode,
                                offlineFoundNoLocalItems: viewModel.offlineFoundNoLocalItems
                            )
                            .id("victory")
                        } else {
                            ForEach(
                                Array(viewModel.photoStack.prefix(cardStackSize).enumerated()),
                                id: \.element.id
                            ) { index, item in
                                PhotoCardView(
                                    item: item,
                                    isTopCard: index == 0,
                                    cachedImage: viewModel.imageCache.object(forKey: item.id as NSString)
                                )
                                    .frame(
                                        width: geometry.size.width - 40,
                                        height: geometry.size.height - 40
                                    )
                                    .zIndex(Double(cardStackSize - index))
                                    .offset(
                                        x: index == 0 ? dragOffset.width : 0,
                                        y: index == 0 ? dragOffset.height : CGFloat(index * 8)
                                    )
                                    .scaleEffect(index == 0 ? 1.0 : (1.0 - CGFloat(index) * 0.05))
                                    .rotationEffect(
                                        .degrees(index == 0 ? dragRotation : item.rotation)
                                    )
                                    .opacity(index == 0 ? 1.0 : (1.0 - Double(index) * 0.2))
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragOffset)
                                    .gesture(index == 0 ? dragGesture : nil)
                                    .overlay {
                                        if index == 0 { swipeIndicatorOverlay }
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.35), value: viewModel.isScanning)
                    // Shuffle / offline transition modifiers — applied to the whole card area
                    .offset(y: cardStackOffset)
                    .scaleEffect(cardStackScale)
                    .opacity(cardStackOpacity)
                }
                .padding(.vertical, 10)
                .environment(\.layoutDirection, .leftToRight)
            }

            // 3. DopamineMeter — floats above everything in this ZStack.
            //    .zIndex(100) works here because it is a direct ZStack sibling,
            //    not nested inside the VStack.
            DopamineMeter(
                spaceSaved: viewModel.spaceSavedText,
                itemCount: viewModel.reviewBin.count
            )
            .padding(.top, 10)
            .zIndex(100)

            // 4. Mode Badges — shuffle (hidden in offline mode) and/or offline badge
            VStack(spacing: 8) {
                if viewModel.isShuffleModeActive && !viewModel.isOfflineMode {
                    shuffleBadge
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if viewModel.isOfflineMode {
                    offlineBadge
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 100)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.isShuffleModeActive)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.isOfflineMode)
            .zIndex(110)

            // 5b. Offline prompt banner — one-per-session, auto-dismisses after 8s
            if viewModel.showOfflinePrompt {
                offlinePromptBanner
                    .zIndex(120)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 5. Time Indicator — month/year overlay that appears on shuffle jump
            if showTimeIndicator {
                timeIndicatorView
                    .zIndex(150)
                    .transition(.opacity)
            }

            // 5c. Shake Hint Toast — appears once after 3rd swipe, first session only
            if showShakeHintToast {
                shakeHintToastView
                    .zIndex(160)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 6. FAB row — shuffle (left, hidden in offline mode) + offline mode (right)
            // Force LTR so FABs stay on correct sides in RTL locales (e.g. Hebrew).
            VStack {
                Spacer()
                HStack {
                    if !viewModel.isOfflineMode {
                        shuffleFAB
                            .overlay(alignment: .top) {
                                if viewModel.isShuffleModeActive {
                                    resetToTodayButton
                                        .offset(y: -(48 + 10))
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal:   .move(edge: .bottom).combined(with: .opacity)
                                        ))
                                }
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.isShuffleModeActive)
                            .transition(.opacity.combined(with: .scale))
                    }
                    Spacer()
                    offlineFAB
                }
                .padding(.horizontal, 24)
                // Extra clearance when the top card is a video so the FABs
                // don't sit on top of the VideoProgressBar.
                .padding(.bottom, 140)
            }
            .environment(\.layoutDirection, .leftToRight)
            .zIndex(50)

            // 7. Particle explosion overlay — rendered above everything including DopamineMeter
            if showParticles {
                ParticleExplosionView(
                    origin: particleOrigin,
                    destination: meterDestination,
                    color: .systemRed
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(200)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showParticles = false
                    }
                }
            }
        }
        .onShake {
            viewModel.undoLastAction()
        }
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear {
            // Recover from a stuck shuffle or offline transition (e.g. user switched
            // tabs mid-flight). The batchID onChange won't re-fire, so reset manually.
            if awaitingShuffleLanding || awaitingOfflineLanding {
                awaitingShuffleLanding = false
                awaitingOfflineLanding = false
                cardStackOffset = 0
                cardStackOpacity = 1
                cardStackScale = 1
            }
            if viewModel.photoStack.isEmpty && !viewModel.isLoading {
                viewModel.refreshPhotos()
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
            // Pause all pooled players when leaving the Swipe tab.
            viewModel.pauseVideoPool()
        }
        .fullScreenCover(isPresented: $viewModel.shouldShowPaywall) {
            PaywallView()
        }
        // Shuffle landing: fires when shuffleBatchID changes (activateShuffle / deactivateShuffle).
        .onChange(of: viewModel.shuffleBatchID) { _ in
            guard awaitingShuffleLanding else { return }
            awaitingShuffleLanding = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                cardStackOffset = 0
                cardStackOpacity = 1
                cardStackScale = 1
            }
            if viewModel.isShuffleModeActive {
                if let date = viewModel.photoStack.first?.asset.creationDate {
                    triggerTimeIndicator(for: date)
                }
            } else {
                triggerReturnHomeIndicator()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                HapticService.shared.shuffleLand()
            }
        }
        // Offline landing: fires when isLoading transitions false — directly observing
        // the scan/load completion is more reliable than a separate batch-ID signal.
        .onChange(of: viewModel.isLoading) { isNowLoading in
            guard !isNowLoading, awaitingOfflineLanding else { return }
            awaitingOfflineLanding = false
            // Card area is already at its final position (sprang back at transition start).
            triggerOfflineIndicator(entering: viewModel.isOfflineMode)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                HapticService.shared.shuffleLand()
            }
        }
    }

    // MARK: - Shuffle FAB

    private var resetToTodayButton: some View {
        Button {
            performShuffleTransition { viewModel.deactivateShuffle() }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)

                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var shuffleFAB: some View {
        Button {
            performShuffleTransition { viewModel.activateShuffle() }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().fill(
                            viewModel.isShuffleModeActive
                                ? LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.5, blue: 1.0),
                                             Color(red: 0.5, green: 0.2, blue: 0.9)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(
                        color: viewModel.isShuffleModeActive ? Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.5) : .black.opacity(0.18),
                        radius: 14, y: 5
                    )

                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .rotationEffect(viewModel.isShuffleModeActive ? .degrees(180) : .zero)
                    .animation(.spring(response: 0.4, dampingFraction: 0.65), value: viewModel.isShuffleModeActive)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(awaitingShuffleLanding ? 0.9 : 1.0)
        .animation(.spring(response: 0.3), value: awaitingShuffleLanding)
    }

    // MARK: - Shuffle Mode Badge

    private var shuffleBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "shuffle")
                .font(.system(size: 11, weight: .bold))
            Text(String(localized: "shuffle.mode_badge"))
                .font(.system(size: 12, weight: .semibold))
            Button {
                performShuffleTransition { viewModel.deactivateShuffle() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.55),
                                     Color(red: 0.5, green: 0.2, blue: 0.9).opacity(0.45)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }

    // MARK: - Offline FAB

    private var offlineFAB: some View {
        Button {
            performOfflineTransition(deactivating: viewModel.isOfflineMode) {
                if viewModel.isOfflineMode {
                    viewModel.deactivateOfflineMode()
                } else {
                    viewModel.activateOfflineMode()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().fill(
                            viewModel.isOfflineMode
                                ? LinearGradient(
                                    colors: [Color(red: 0.1, green: 0.35, blue: 0.9),
                                             Color(red: 0.3, green: 0.1, blue: 0.75)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(
                        color: viewModel.isOfflineMode
                            ? Color(red: 0.1, green: 0.35, blue: 0.9).opacity(0.5)
                            : .black.opacity(0.18),
                        radius: 14, y: 5
                    )

                Image(systemName: viewModel.isOfflineMode ? "airplane.circle.fill" : "airplane")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .scaleEffect(viewModel.isOfflineMode ? 1.1 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: viewModel.isOfflineMode)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Offline Badge

    private var offlineBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "airplane")
                .font(.system(size: 11, weight: .bold))
            Text("Offline Mode")
                .font(.system(size: 12, weight: .semibold))
            Button {
                performOfflineTransition(deactivating: true) { viewModel.deactivateOfflineMode() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.35, blue: 0.9).opacity(0.55),
                                     Color(red: 0.3, green: 0.1, blue: 0.75).opacity(0.45)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }

    // MARK: - Offline Scanning State

    private var offlineScanningView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.1, green: 0.35, blue: 0.9).opacity(0.18),
                                 Color(red: 0.3, green: 0.1, blue: 0.75).opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 140, height: 140)
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 70))
                    .foregroundColor(Color(red: 0.1, green: 0.35, blue: 0.9))
                    .shadow(color: Color(red: 0.1, green: 0.35, blue: 0.9).opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .padding(.top, 40)

            VStack(spacing: 12) {
                Text(String(localized: "offline.scanning_title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(String(localized: "offline.scanning_subtitle"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }

            ProgressView()
                .scaleEffect(1.2)
                .tint(Color(red: 0.1, green: 0.35, blue: 0.9))

            Spacer()
        }
        .padding()
        .transition(.opacity)
    }

    // MARK: - Offline Prompt Banner

    private var offlinePromptBanner: some View {
        let reason = viewModel.offlinePromptReason
        let icon: String = reason == .offline ? "wifi.slash" : "wifi.exclamationmark"
        let title: String = {
            switch reason {
            case .offline:      return "You're offline"
            case .constrained:  return "Low Data Mode is on"
            case .slowNetwork:  return "Connection seems slow"
            }
        }()
        let subtitle: String = {
            switch reason {
            case .offline:      return "Switch to swipe only locally stored photos"
            case .constrained:  return "Switch to Offline Mode to avoid using data"
            case .slowNetwork:  return "Switch to Offline Mode for a smoother experience ⚡️"
            }
        }()

        return VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.78))
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.spring(response: 0.35)) {
                        viewModel.showOfflinePrompt = false
                    }
                    performOfflineTransition { viewModel.activateOfflineMode() }
                } label: {
                    Text("Switch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.35)) {
                        viewModel.showOfflinePrompt = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.08, green: 0.25, blue: 0.75).opacity(0.75),
                                             Color(red: 0.2, green: 0.05, blue: 0.55).opacity(0.55)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
            .padding(.horizontal, 16)
            .padding(.top, 100)

            Spacer()
        }
    }

    // MARK: - Time Indicator

    private var timeIndicatorView: some View {
        Color.clear
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .overlay(alignment: .center) {
                VStack(spacing: 4) {
                    if !timeIndicatorHeader.isEmpty {
                        Text(timeIndicatorHeader)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .textCase(.uppercase)
                            .kerning(1.2)
                    }
                    Text(timeIndicatorText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
            }
    }

    // MARK: - Shake Hint Toast

    private var shakeHintToastView: some View {
        VStack(spacing: 8) {
            Text(String(localized: "onboarding.shake_hint.title"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 1.0, green: 0.353, blue: 0.373))

            HStack(spacing: 6) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(String(localized: "onboarding.shake_hint.subtitle"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .textCase(.uppercase)
                    .kerning(1.2)
            }

            Button {
                withAnimation(.easeOut(duration: 0.25)) { showShakeHintToast = false }
            } label: {
                Text(String(localized: "onboarding.demo.cta"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
        .frame(maxWidth: 360)
        .padding(.horizontal, 12)
        .padding(.top, 100)
    }

    private func triggerShakeHintToast() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            showShakeHintToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            guard showShakeHintToast else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                showShakeHintToast = false
            }
        }
    }

    // MARK: - Shuffle Transition

    /// Executes a shuffle action with a fly-out / land-in animation.
    /// Guards against double-triggering while a transition is already in flight.
    private func performShuffleTransition(action: @escaping () -> Void) {
        guard !awaitingShuffleLanding else { return }
        HapticService.shared.shuffle()

        withAnimation(.easeIn(duration: 0.22)) {
            cardStackOffset = -UIScreen.main.bounds.height * 0.65
            cardStackOpacity = 0
            cardStackScale = 0.82
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) {
            cardStackOffset = 55
            cardStackScale = 0.85
            cardStackOpacity = 0
            awaitingShuffleLanding = true
            action()
        }
    }

    // MARK: - Offline Transition

    /// Fly-out / land-in animation for offline mode toggle — mirrors performShuffleTransition.
    /// Pass `deactivating: true` when the intent is to exit offline mode — bypasses the
    /// awaitingOfflineLanding guard so the user can cancel even during an active scan.
    private func performOfflineTransition(deactivating: Bool = false, action: @escaping () -> Void) {
        if deactivating && awaitingOfflineLanding {
            // Cancel while scan is in progress: cards are already back in position,
            // no fly-out needed. Setting isOfflineMode = false inside action() causes
            // scanLocalUniverse to exit via `guard isOfflineMode else { break }`.
            awaitingOfflineLanding = false
            HapticService.shared.shuffle()
            action()
            return
        }
        guard !awaitingOfflineLanding else { return }
        // Set synchronously before any async work so onChange(of: isLoading) always
        // sees the flag as true when it fires — prevents the race condition where a
        // fast-returning scanLocalUniverse flips isLoading before the asyncAfter runs.
        awaitingOfflineLanding = true
        HapticService.shared.shuffle()

        withAnimation(.easeIn(duration: 0.22)) {
            cardStackOffset = -UIScreen.main.bounds.height * 0.65
            cardStackOpacity = 0
            cardStackScale = 0.82
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) {
            action()
            // Spring the card area back immediately — "Searching your device..."
            // is now visible during the scan instead of a blank screen.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                cardStackOffset = 0
                cardStackOpacity = 1
                cardStackScale = 1
            }
        }
    }

    // MARK: - Time / Mode Indicator Helpers

    private func triggerTimeIndicator(for date: Date) {
        timeIndicatorHeader = String(localized: "shuffle.time_traveled")
        timeIndicatorText = formatShuffleDate(date)
        withAnimation(.easeIn(duration: 0.2)) { showTimeIndicator = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.35)) { showTimeIndicator = false }
        }
    }

    private func triggerReturnHomeIndicator() {
        timeIndicatorHeader = String(localized: "shuffle.return_home_header")
        timeIndicatorText = String(localized: "shuffle.return_home")
        withAnimation(.easeIn(duration: 0.2)) { showTimeIndicator = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.35)) { showTimeIndicator = false }
        }
    }

    private func triggerOfflineIndicator(entering: Bool) {
        timeIndicatorHeader = entering
            ? String(localized: "offline.indicator_header_enter")
            : String(localized: "offline.indicator_header_exit")
        timeIndicatorText = entering
            ? String(localized: "offline.indicator_text_enter")
            : String(localized: "offline.indicator_text_exit")
        withAnimation(.easeIn(duration: 0.2)) { showTimeIndicator = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.35)) { showTimeIndicator = false }
        }
    }

    private func formatShuffleDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        // Template respects the device locale — shows "October 2022" in English
        // and "אוקטובר 2022" / "2022年10月" on localized devices.
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    // MARK: - Swipe Gesture

    // In RTL layout iOS flips the translation.width sign.
    // We normalize it here so swipe-right always means Keep
    // and swipe-left always means Delete regardless of locale.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    viewModel.cancelPrefetch()
                }
                dragOffset = value.translation
                dragRotation = Double(value.translation.width / 20)

                // Fire early pre-load once the drag clears 80 pt.
                // This gives us the remainder of the gesture (~200-400 ms) to
                // pull the next card's image into NSCache before it hits screen.
                if !hasFiredEarlyPrecache,
                   abs(value.translation.width) > 80 || abs(value.translation.height) > 80 {
                    hasFiredEarlyPrecache = true
                    viewModel.prepareUpcomingCards()
                }
            }
            .onEnded { value in
                isDragging = false
                hasFiredEarlyPrecache = false
                // SwipeDirection uses the RAW translation (not flipped)
                // because .left/.right are already correct in RTL context.
                let direction = SwipeDirection.from(offset: value.translation)

                if let action = direction.action {
                    // Block keep/delete swipes when free daily limit is exhausted
                    if (action == .keep || action == .delete), !viewModel.canSwipe {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.52)) {
                            dragOffset = .zero
                            dragRotation = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            viewModel.shouldShowPaywall = true
                        }
                        return
                    }

                    // Animate card off screen
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        switch direction {
                        case .left:
                            dragOffset = CGSize(width: -500, height: value.translation.height)
                        case .right:
                            dragOffset = CGSize(width: 500, height: value.translation.height)
                        case .up:
                            dragOffset = CGSize(width: value.translation.width, height: -500)
                        case .none:
                            break
                        }
                    }

                    // Perform action after exit-animation completes.
                    // Crucially we reset dragOffset WITHOUT animation so the
                    // incoming card never inherits the ±500 offset and slides in.
                    NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // Capture top card BEFORE performing action (it removes it from stack)
                        let topCard = viewModel.topCard

                        viewModel.performAction(action)
                        dragOffset = .zero
                        dragRotation = 0

                        // Show shake hint toast on 3rd swipe (first session only)
                        if !hasSeenShakeHint {
                            shakeHintSwipeCount += 1
                            if shakeHintSwipeCount >= 3 {
                                hasSeenShakeHint = true
                                triggerShakeHintToast()
                            }
                        }

                        // Trigger particle explosion if this was a delete of a large file
                        if action == .delete,
                           let card = topCard,
                           card.fileSize >= largeFileSizeThreshold {
                            // Particles spawn from the left edge where the card exits
                            particleOrigin = CGPoint(
                                x: 0,
                                y: UIScreen.main.bounds.height / 2
                            )
                            showParticles = true
                        }
                    }
                } else {
                    // Spring back to centre
                    resetCardPosition()
                }
                viewModel.resumePrefetch()
            }
    }

    // MARK: - Swipe Indicator Overlay

    private var swipeIndicatorOverlay: some View {
        let direction = SwipeDirection.from(offset: dragOffset)
        return SwipeIndicator(direction: direction, offset: dragOffset)
    }

    // MARK: - Instructions View

    private var instructionsView: some View {
        HStack(spacing: 30) {
            instructionItem(icon: "arrow.left", text: "Delete", color: .swipeRed)
            instructionItem(icon: "arrow.up", text: "Later", color: .swipeBlue)
            instructionItem(icon: "arrow.right", text: "Keep", color: .swipeGreen)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cardBackground.opacity(0.9))
                .shadow(color: .black.opacity(0.05), radius: 5)
        )
        .padding(.horizontal)
    }

    private func instructionItem(icon: String, text: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helper Methods

    private func resetCardPosition() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = .zero
            dragRotation = 0
        }
        // Re-sync the top card's video in case the early warm-up interrupted
        // playback during the drag (safety net on top of the pool protection).
        NotificationCenter.default.post(name: .resumeTopCardVideo, object: nil)
    }
}

#Preview {
    SwipeStackView(selectedTab: .constant(0))
        .environmentObject(PhotoStackViewModel())
}
