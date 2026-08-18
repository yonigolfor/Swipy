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
    @Environment(\.scenePhase) private var scenePhase
    /// True from shake-to-undo until the restored card lands back at center —
    /// blocks the drag gesture so a finger grabbing the card mid-flight can't
    /// fight the return spring. Mirrored into CardStackView via @Binding — it only
    /// flips twice per undo (start/landed), so sharing this storage costs nothing.
    @State private var isUndoAnimating = false
    /// Set once undoLastAction() has already re-inserted the restored item at the
    /// front of the stack — CardStackView reacts by flying it in from the edge/tilt
    /// matching the undone action. See CardStackView.runUndoEntry.
    @State private var pendingUndoRequest: UndoRequest?

    /// Tracks the Photos permission status across app foreground/background — lets the
    /// scenePhase hook detect a denied→authorized transition (e.g. user just came back
    /// from Settings) without reloading on every ordinary foreground.
    @State private var lastKnownAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

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

    /// True between drag start and drag end. Mirrored into CardStackView via @Binding —
    /// like isPinching/isUndoAnimating, it only flips twice per gesture, so sharing this
    /// storage costs nothing even though the continuous drag values it gates (dragOffset,
    /// dragRotation) live entirely inside CardStackView now.
    @State private var isDragging = false
    /// True while a pinch is active. Mirrored into CardStackView via @Binding — drives
    /// this view's own tab-bar-hide / dim-overlay / zIndex(200) below.
    @State private var isPinching = false

    // Shake hint toast — shown once after the user's 3rd swipe (first session only).
    @AppStorage("shakeHintSwipeCount") private var shakeHintSwipeCount = 0
    @AppStorage("hasSeenShakeHint") private var hasSeenShakeHint = false
    @State private var showShakeHintToast = false

    var body: some View {
        // Outer ZStack: background | card column | SessionSavingsBarView floating on top.
        // SessionSavingsBarView MUST be a direct child of this ZStack (not buried inside
        // the VStack) so that .zIndex(100) has real effect against the cards.
        ZStack(alignment: .top) {
            // 1. Background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            // 2. Column: spacer gap + cards + bottom reserve
            VStack(spacing: 0) {
                // Reserve the same vertical space SessionSavingsBarView will occupy
                // so the cards don't slide underneath it (≈ 100pt incl. padding).
                Color.clear.frame(height: 100)

                // Card Stack — force LTR so swipe physics are always consistent:
                // right = Keep, left = Delete, regardless of device language.
                // Drag/pinch continuous state lives entirely inside CardStackView — see
                // its header comment for why (CPU spike root-caused to that state living
                // on this view instead, forcing a full re-diff of this whole screen on
                // every drag frame).
                CardStackView(
                    selectedTab: $selectedTab,
                    isPinching: $isPinching,
                    isDragging: $isDragging,
                    isUndoAnimating: $isUndoAnimating,
                    pendingUndoRequest: pendingUndoRequest,
                    cardStackOffset: cardStackOffset,
                    cardStackScale: cardStackScale,
                    cardStackOpacity: cardStackOpacity,
                    onExitOfflineMode: {
                        performOfflineTransition(deactivating: true) { viewModel.deactivateOfflineMode() }
                    },
                    onSwipeFinalized: handleSwipeFinalized
                )
            }
            .zIndex(isPinching ? 200 : 0)

            // 3. SessionSavingsBarView — floats above everything in this ZStack.
            //    .zIndex(100) works here because it is a direct ZStack sibling,
            //    not nested inside the VStack.
            SessionSavingsBarView(sessionMB: viewModel.sessionSpaceSavedMB)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                )
                .padding(.horizontal)
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

            // 6. FAB row — Shuffle (hidden in offline mode; offline entry point moved to
            // SmartFiltersView, and shuffle/offline are mutually exclusive) + Undo (always
            // available — it has no dependency on network/offline state, so it must not be
            // hidden just because it shares this row with Shuffle).
            // Force LTR so FAB stays on correct side in RTL locales (e.g. Hebrew).
            // Hidden when VictoryView is shown (isLoading covers the in-flight shuffle state
            // where photoStack is temporarily empty before the batch lands).
            if viewModel.isLoading || !viewModel.photoStack.isEmpty {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 24) {
                        if !viewModel.isOfflineMode {
                            HStack {
                                shuffleCapsule
                                Spacer()
                            }
                        }
                        HStack {
                            undoButton
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 24)
                    // Extra clearance when the top card is a video so the row
                    // doesn't sit on top of the VideoProgressBar.
                    .padding(.bottom, 140)
                }
                .environment(\.layoutDirection, .leftToRight)
                .zIndex(50)
            }

            // 7. Pinch-zoom background dim — above all chrome but below the zoomed card (zIndex 200).
            // Animates IN only; disappears instantly on release so it doesn't compete
            // with the card's return animation.
            Color.black
                .opacity(isPinching ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(190)
                .animation(isPinching ? .easeInOut(duration: 0.2) : nil, value: isPinching)

            // 8. Particle explosion overlay — rendered above everything including DopamineMeter
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
        .toolbar(isPinching ? .hidden : .visible, for: .tabBar)
        .onShake {
            // DEMO BRANCH ONLY — shake re-stages the 6 bundled demo assets at the
            // front of the stack instead of undo. Revert to `performUndo()` before
            // merging back to main.
            print("[Demo] shake detected, loading \(DemoModeService.activeSession) assets…")
            DemoModeService.loadDemoAssets { assets in
                print("[Demo] loadDemoAssets returned \(assets.count) asset(s)")
                viewModel.pinDemoAssets(assets)
            }
            // Warm the shuffle-only demo bucket now, well ahead of the Shuffle tap later
            // in the recording, so that jump shows zero visible loading. Importing these
            // into Photos makes photoLibraryDidChange see them as new real photos, so they
            // must be explicitly excluded from the main stack — see excludeFromMainStack.
            DemoModeService.prewarmDemoShuffleAssets { assets in
                viewModel.excludeFromMainStack(assets)
            }
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
            } else {
                // Pool may be cold after emptyTrash (drainAll) or first return to tab.
                // For normal tab switches the pool is still warm; this is a fast no-op.
                viewModel.rewarmVideoPool()
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
            // Pause all pooled players when leaving the Swipe tab.
            viewModel.pauseVideoPool()
        }
        .fullScreenCover(isPresented: $viewModel.shouldShowPaywall) {
            PaywallView(context: .swipeLimitReached)
        }
        .sheet(isPresented: $viewModel.isShowingShareSheet) {
            // .presentationDetents were previously suspected as the cause of third-party
            // share extensions (WhatsApp, etc.) flash-dismissing themselves; the real cause
            // was ShareHUDManager's floating HUD window rendering solid black over the
            // extension (see ShareHUDView's background comment). Confirmed fixed with
            // detents restored.
            ActivityView(items: viewModel.shareItems)
                .presentationDetents([.medium, .large])
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
                // DEMO BRANCH ONLY — once the shake demo has run, every shuffle re-pins
                // the demo-shuffle sneak peek to the front of the (still genuinely
                // random) landing stack; the label shows a fixed August 2023 instead of
                // those items' real (just-now) import date. Revert to always using
                // photoStack.first's real creationDate before merging back to main.
                if DemoModeService.shakeDemoLoaded, let fakeDate = demoShuffleDisplayDate {
                    triggerTimeIndicator(for: fakeDate)
                } else if let date = viewModel.photoStack.first?.asset.creationDate {
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
        // Silent re-check when returning from Settings — only reloads if access was
        // actually blocked before and was just granted, never on an ordinary foreground.
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                // Safety net: DragGesture/MagnificationGesture's onEnded isn't guaranteed to
                // fire if the app resigns active mid-gesture (e.g. Home button pressed while
                // a finger is still down on a card) — without this, isDragging/isPinching/
                // viewModel.isUserInteracting could stay stuck `true` for the rest of the
                // session, permanently hanging startBackgroundBlurBurstPrescan()'s gesture-
                // guard loop and starving its scan lock (see CLAUDE.md's code-review note on
                // this). Backgrounding always ends any in-flight gesture from the user's
                // perspective, so unconditionally resetting here is always correct.
                isDragging = false
                isPinching = false
                viewModel.isUserInteracting = false
            }
            guard newPhase == .active else { return }
            let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            defer { lastKnownAuthStatus = currentStatus }
            let wasBlocked = lastKnownAuthStatus == .denied || lastKnownAuthStatus == .restricted
            let nowAllowed = currentStatus == .authorized || currentStatus == .limited
            if wasBlocked, nowAllowed {
                viewModel.loadPhotos(filter: viewModel.currentFilter)
            } else if currentStatus == .denied, lastKnownAuthStatus != .denied {
                // User just revoked access via Settings mid-session (not caught at
                // onboarding, which only fires once, on first request).
                HapticService.shared.error()
            }
        }
    }

    // MARK: - Shuffle Capsule (toggle + exit, unified glassmorphic container)

    /// Icon-only tap target — no background of its own, the parent capsule
    /// supplies the single shared glass surface (avoids blur-on-blur).
    private var shuffleToggleButton: some View {
        Button {
            performShuffleTransition { viewModel.activateShuffle() }
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(
                    viewModel.isShuffleModeActive
                        ? AnyShapeStyle(LinearGradient(
                            colors: [.shuffleAccentStart, .shuffleAccentEnd],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.white)
                )
                .frame(width: 44, height: 44)
                .rotationEffect(viewModel.isShuffleModeActive ? .degrees(180) : .zero)
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: viewModel.isShuffleModeActive)
        }
        .buttonStyle(.plain)
    }

    /// "Exit shuffle" — plain xmark (not xmark.circle.fill, which shuffleBadge already
    /// uses for the same action) so the two controls never look identical.
    private var exitShuffleButton: some View {
        Button {
            performShuffleTransition { viewModel.deactivateShuffle() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var shuffleCapsule: some View {
        HStack(spacing: 2) {
            shuffleToggleButton
            if viewModel.isShuffleModeActive {
                exitShuffleButton
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4, anchor: .leading).combined(with: .opacity),
                        removal:   .scale(scale: 0.4, anchor: .leading).combined(with: .opacity)
                    ))
            }
        }
        .padding(6)
        .background(
            // Glass stays translucent in both states — even while active — so the
            // capsule never blocks the card content underneath it. "On" is
            // communicated by the animated border + tinted icon only, since the
            // top shuffleBadge already spells out the active state in text.
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            viewModel.isShuffleModeActive
                                ? AnyShapeStyle(AngularGradient(
                                    colors: [.shuffleAccentStart, .shuffleAccentEnd, .shuffleAccentStart],
                                    center: .center))
                                : AnyShapeStyle(Color.white.opacity(0.12)),
                            lineWidth: viewModel.isShuffleModeActive ? 1.5 : 1
                        )
                )
                .shadow(
                    color: viewModel.isShuffleModeActive ? Color.shuffleAccentStart.opacity(0.5) : .black.opacity(0.18),
                    radius: 14, y: 5
                )
        )
        .scaleEffect(awaitingShuffleLanding ? 0.9 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isShuffleModeActive)
        .animation(.spring(response: 0.3), value: awaitingShuffleLanding)
    }

    // MARK: - Undo Button

    /// Same deterministic pipeline as shake-to-undo — calls the identical
    /// `performUndo()` so shake and tap share one source of truth.
    private var undoButton: some View {
        let isDisabled = !viewModel.canUndo || isUndoAnimating
        return Button(action: performUndo) {
            ZStack {
                // 56pt matches shuffleCapsule's inactive-state visible circle
                // (44pt inner button + 6pt padding on each side) — keeps the two
                // FAB rows the same size.
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.7 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isDisabled)
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
                            colors: [Color.shuffleAccentStart.opacity(0.55),
                                     Color.shuffleAccentEnd.opacity(0.45)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
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

    /// DEMO BRANCH ONLY — fixed display date for the shuffle-demo sneak peek (see
    /// `.onChange(of: viewModel.shuffleBatchID)` above). Purely cosmetic: the actual
    /// jump target stays exactly as random as ever, only the label lies.
    private var demoShuffleDisplayDate: Date? {
        DateComponents(calendar: .current, year: 2023, month: 8, day: 15).date
    }

    private func formatShuffleDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        // Template respects the device locale — shows "October 2022" in English
        // and "אוקטובר 2022" / "2022年10月" on localized devices.
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    // MARK: - Swipe Finalization Callback

    /// Called by CardStackView once a swipe has fully committed (after finalizeSwipe
    /// succeeds) — drives the two UI concerns that live up here: the shake-hint toast
    /// counter and the large-file delete particle burst. Was previously inline in the
    /// dragGesture.onEnded closure before that gesture moved into CardStackView.
    private func handleSwipeFinalized(_ item: PhotoItem, _ action: SwipeAction) {
        // Show shake hint toast on 3rd swipe (first session only)
        if !hasSeenShakeHint {
            shakeHintSwipeCount += 1
            if shakeHintSwipeCount >= 3 {
                hasSeenShakeHint = true
                triggerShakeHintToast()
            }
        }

        // Trigger particle explosion if this was a delete of a large file
        if action == .delete, item.fileSize >= largeFileSizeThreshold {
            // Particles spawn from the left edge where the card exits
            particleOrigin = CGPoint(x: 0, y: UIScreen.main.bounds.height / 2)
            showParticles = true
        }
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

    /// Shake-to-undo entry point: validates the request and hands the actual re-entry
    /// animation (off-screen start → spring back to center, "deck-landing" overshoot)
    /// to CardStackView via `pendingUndoRequest`, since it owns dragOffset/dragRotation
    /// and the drag gesture those need to stay isolated from this view's body. Ignores
    /// the shake while the user has an active gesture on the top card — inserting the
    /// restored item would shift that card to index 1 out from under their finger/fingers
    /// and hijack the drag/pinch state mid-gesture.
    private func performUndo() {
        guard !isDragging, !isPinching else { return }
        guard let action = viewModel.undoLastAction() else { return }
        isUndoAnimating = true
        pendingUndoRequest = UndoRequest(action: action)
    }
}

#Preview {
    SwipeStackView(selectedTab: .constant(0))
        .environmentObject(PhotoStackViewModel())
}

// MARK: - Share Sheet Wrapper

/// .sheet() presentation lets SwiftUI own the popover context — crash-safe on iPad.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
