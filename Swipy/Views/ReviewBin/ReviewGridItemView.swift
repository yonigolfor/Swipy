//
//  ReviewGridItemView.swift
//  Swipy
//
//  פריט בודד בגריד של Review Bin
//
//  Performance design:
//  - thumbnailPixelSize injected from ReviewBinView — pixel-exact match with
//    startCachingImages guarantees a PHCachingImageManager cache hit every time.
//  - loadThumbnail (.fastFormat, no network) — serves from PHKit OS cache in <1ms.
//  - Request ID stored and cancelled on onDisappear — no request storm on fast scroll.
//  - Color.clear anchor + .overlay pattern — layout bounds fixed; scaledToFill never bleeds.
//  - Blurred scaledToFill underlay fills letterbox areas for portrait/square assets.
//  - Cell ratio 4:3 — matches standard camera output.
//
//  Restore animation:
//  - Phase 1 (pop):   spring scale 1.0→1.15 over 150ms
//  - Phase 2 (poof):  easeIn scale→0 + opacity→0 + 8-particle burst; haptic fires here
//  - Phase 3 (reflow): onRestore() called inside withAnimation(.smooth) after 300ms total
//

import SwiftUI
import Photos

struct ReviewGridItemView: View {
    let item: PhotoItem
    let thumbnailPixelSize: CGSize
    let onRestore: () -> Void
    var isBeingRestored: Bool = false

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    private enum RestorePhase { case idle, popping, poofing }
    @State private var restorePhase: RestorePhase = .idle
    @State private var hapticTrigger = false

    var body: some View {
        Color.clear
            .aspectRatio(4/3, contentMode: .fit)
            .overlay {
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 18)
                            .scaleEffect(1.1)

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.primary.opacity(0.08)
                        ProgressView()
                    }

                    if item.isVideo {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Text(item.durationString)
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(6)
                            .background(
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .scaleEffect(cellScale)
            .opacity(restorePhase == .poofing ? 0 : 1)
            // Particles sit above the clipped, scaled cell without affecting layout.
            .overlay {
                if restorePhase == .poofing {
                    PoofParticlesView()
                        .allowsHitTesting(false)
                }
            }
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: hapticTrigger)
            .contextMenu {
                Button {
                    // Delay until the context menu dismiss animation completes (~350ms)
                    // so our pop/poof isn't hidden beneath the system dismiss transition.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        triggerRestore()
                    }
                } label: {
                    Label(String(localized: "bin.restore"), systemImage: "arrow.uturn.backward")
                }
            }
            .onChange(of: isBeingRestored) { _, restoring in
                guard restoring else { return }
                triggerRestore()
            }
            .onAppear(perform: loadThumbnail)
            .onDisappear(perform: cancelIfNeeded)
    }

    private var cellScale: CGFloat {
        switch restorePhase {
        case .idle:    1.0
        case .popping: 1.15
        case .poofing: 0.01
        }
    }

    private func triggerRestore() {
        // Phase 1 — pop toward user
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            restorePhase = .popping
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))

            // Phase 2 — poof: shrink + fade + particles + haptic
            hapticTrigger.toggle()
            withAnimation(.easeIn(duration: 0.18)) {
                restorePhase = .poofing
            }

            try? await Task.sleep(for: .milliseconds(300))

            // Phase 3 — grid reflow with smooth spring
            withAnimation(.smooth(duration: 0.45)) {
                onRestore()
            }
        }
    }

    // MARK: - Image Loading

    private func loadThumbnail() {
        requestID = PhotoLibraryService.shared.loadThumbnail(
            for: item.asset,
            targetSize: thumbnailPixelSize
        ) { loaded in
            guard let loaded else { return }
            self.image = loaded
        }
    }

    private func cancelIfNeeded() {
        guard requestID != PHInvalidImageRequestID else { return }
        PhotoLibraryService.shared.cancelRequest(requestID)
        requestID = PHInvalidImageRequestID
    }
}

// MARK: - Poof Particles

private struct PoofParticlesView: View {
    @State private var spread = false

    private struct Particle: Identifiable {
        let id: Int
        let angleDeg: Double
        let distance: CGFloat
        let size: CGFloat
        let isGold: Bool
    }

    private static let particles: [Particle] = [
        Particle(id: 0, angleDeg: 0,   distance: 32, size: 5, isGold: false),
        Particle(id: 1, angleDeg: 45,  distance: 26, size: 4, isGold: true),
        Particle(id: 2, angleDeg: 90,  distance: 34, size: 6, isGold: false),
        Particle(id: 3, angleDeg: 135, distance: 24, size: 4, isGold: true),
        Particle(id: 4, angleDeg: 180, distance: 30, size: 5, isGold: false),
        Particle(id: 5, angleDeg: 225, distance: 27, size: 4, isGold: true),
        Particle(id: 6, angleDeg: 270, distance: 33, size: 6, isGold: false),
        Particle(id: 7, angleDeg: 315, distance: 25, size: 4, isGold: true),
    ]

    var body: some View {
        ZStack {
            ForEach(Self.particles) { p in
                let rad = p.angleDeg * .pi / 180.0
                Circle()
                    .fill(p.isGold ? Color(red: 1.0, green: 0.88, blue: 0.35) : .white)
                    .frame(width: p.size, height: p.size)
                    .offset(
                        x: spread ? cos(rad) * p.distance : 0,
                        y: spread ? sin(rad) * p.distance : 0
                    )
                    .opacity(spread ? 0 : 0.95)
                    .scaleEffect(spread ? 0.2 : 1.0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.38)) {
                spread = true
            }
        }
    }
}
