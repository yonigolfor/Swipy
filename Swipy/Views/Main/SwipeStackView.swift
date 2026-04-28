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
                        let _ = print("🔄 ZStack rerender, stack count: \(viewModel.photoStack.count)")

                        if viewModel.isLoading {
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
                                reviewBinCount: viewModel.reviewBin.count,
                                currentFilter: viewModel.currentFilter
                            )
                            .id("victory")
                        } else {
                            ForEach(
                                Array(viewModel.photoStack.prefix(cardStackSize).enumerated()),
                                id: \.element.id
                            ) { index, item in
                                PhotoCardView(item: item, isTopCard: index == 0)
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
                }
                .padding(.vertical, 10)
                .environment(\.layoutDirection, .leftToRight)

                // Instructions bar
//                if !viewModel.photoStack.isEmpty {
//                    instructionsView
//                        .padding(.bottom, 20)
//                }
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

            // Particle explosion overlay — rendered above everything including DopamineMeter
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
            viewModel.refreshPhotos()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
            // Pause all pooled players when leaving the Swipe tab.
            viewModel.pauseVideoPool()
        }
    }
    
    // MARK: - Swipe Gesture
    
    // In RTL layout iOS flips the translation.width sign.
    // We normalize it here so swipe-right always means Keep
    // and swipe-left always means Delete regardless of locale.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                dragRotation = Double(value.translation.width / 20)
            }
            .onEnded { value in
                // SwipeDirection uses the RAW translation (not flipped)
                // because .left/.right are already correct in RTL context.
                let direction = SwipeDirection.from(offset: value.translation)

                if let action = direction.action {
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
            instructionItem(icon: "arrow.up", text: "Star", color: .swipeYellow)
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
    }
}

#Preview {
    SwipeStackView(selectedTab: .constant(0))
        .environmentObject(PhotoStackViewModel())
}
