//
//  CardStackView.swift
//  CleanSwipe
//
//  הסטאק של הקלפים + מנוע ה-Drag/Pinch — מבודד מ-SwipeStackView
//

import SwiftUI
import Photos

/// Uniquely identifies a single undo request so `CardStackView`'s `.onChange` always
/// fires even if two consecutive undos happen to carry the same `SwipeAction` — see
/// `performUndo()` in SwipeStackView for why that can't actually happen today, but the
/// id-based identity makes the trigger robust regardless.
struct UndoRequest {
    let id = UUID()
    let action: SwipeAction
}

extension UndoRequest: Equatable {
    static func == (lhs: UndoRequest, rhs: UndoRequest) -> Bool { lhs.id == rhs.id }
}

/// Owns the swipe/pinch gesture's *continuous* state (`dragOffset`, `dragRotation`,
/// `pinchScale`, `pinchOffset`, `pinchAnchor`, `pinchPanOrigin`) as private `@State` —
/// these used to live on `SwipeStackView` itself, which also hosts `SessionSavingsBarView`,
/// the mode badges, the FAB row (`.ultraThinMaterial` fills, gradients, shadows), and the
/// particle-explosion overlay. Because `dragOffset` was read inside that view's `body`,
/// every `.onChanged` frame (up to 120/sec while dragging) forced SwiftUI to re-diff the
/// *entire* screen, not just the card — measured at 125-130% CPU during rapid swiping.
/// Moving the continuous state down here means a drag/pinch frame only re-diffs this
/// view's body. `isPinching`/`isDragging`/`isUndoAnimating` stay as `@Binding`s into
/// SwipeStackView's own `@State` — they're still "shared" storage, but they only flip
/// a couple of times per gesture (start/end), not every frame, so mirroring them costs
/// nothing while letting the FAB row / tab-bar-hide / dim-overlay logic that lives in
/// the parent keep reading them exactly as before.
struct CardStackView: View {
    @EnvironmentObject private var viewModel: PhotoStackViewModel
    @Binding var selectedTab: Int

    @Binding var isPinching: Bool
    @Binding var isDragging: Bool
    @Binding var isUndoAnimating: Bool

    /// Set by SwipeStackView's `performUndo()` (shake or Undo-button tap) once
    /// `viewModel.undoLastAction()` has already re-inserted the restored item at the
    /// front of `photoStack`. This view reacts by flying the new top card in from the
    /// edge/tilt matching the undone action — it owns `dragOffset`/`dragRotation`, so
    /// the entry animation has to run here, not in the parent.
    ///
    /// A later revision briefly moved the whole undo pipeline (guard checks +
    /// `viewModel.undoLastAction()`) into `CardStackView` itself, triggered by a plain
    /// `undoTrigger: Int` bump, specifically to close a code-review-flagged PLAUSIBLE
    /// (not confirmed) risk that the two-hop version below could show a promoted card's
    /// first frame before its off-screen position was set. That change was reverted —
    /// a reported on-device drag-smoothness regression appeared immediately after it
    /// shipped. Static analysis couldn't find a mechanism by which it should have
    /// affected the drag hot path (`undoTrigger`/`pendingUndoRequest` are both read only
    /// in a rare `.onChange`, never in `cardStack()`'s `ForEach` body or either
    /// `.visualEffect` closure) — but the on-device report takes priority over a
    /// theoretical fix for a low-severity, unconfirmed finding, so it was reverted
    /// pending further investigation rather than kept on the strength of that analysis.
    let pendingUndoRequest: UndoRequest?

    /// Shuffle / offline-mode fly-out-fly-in transform, driven by SwipeStackView's own
    /// `withAnimation` calls — passed down as plain values (not bindings) since this
    /// view never needs to write them; SwiftUI's ambient transaction still animates
    /// them correctly here because the parent's `withAnimation` wraps the mutation that
    /// causes this view to re-render with the new value.
    let cardStackOffset: CGFloat
    let cardStackScale: CGFloat
    let cardStackOpacity: Double

    let onExitOfflineMode: () -> Void
    /// Called once a swipe has been finalized (fired well after the gesture itself
    /// ends) so SwipeStackView can drive its own UI concerns — the shake-hint toast
    /// counter and the large-file delete particle burst — that don't belong down here.
    let onSwipeFinalized: (PhotoItem, SwipeAction) -> Void

    // MARK: - Continuous gesture state (never read by SwipeStackView)

    @State private var dragOffset: CGSize = .zero
    @State private var dragRotation: Double = 0
    /// Mirrors `SwipeDirection.from(offset: dragOffset)`, but only written when it actually
    /// changes (i.e. at the rare 80pt threshold crossings) — not on every `.onChanged` frame.
    /// The overlay reads this (not `dragOffset`) to pick which icon/text to show, so that
    /// per-pixel drag movement doesn't force CardStackView.body to re-run just to decide
    /// "still the same direction." The live opacity/scale tracking is handled separately
    /// via the `SwipeIndicator`'s own `.visualEffect` in `cardStack(cardW:cardH:)`, which
    /// *can* read raw `dragOffset` every frame without that cost.
    @State private var swipeDirection: SwipeDirection = .none
    /// Prevents firing prepareUpcomingCards() more than once per gesture.
    @State private var hasFiredEarlyPrecache = false
    /// Bumped on every undo entry animation — lets a stale completion/safety-net from
    /// an earlier undo recognize it's no longer current (mirrors the mechanism that
    /// used to live in SwipeStackView.performUndo()).
    @State private var undoGeneration = 0

    @State private var pinchScale: CGFloat = 1.0
    @State private var pinchOffset: CGSize = .zero
    @State private var pinchAnchor: UnitPoint = .center
    @State private var pinchPanOrigin: CGSize = .zero
    @State private var cardSize: CGSize = .zero

    private let cardStackSize = 3 // כמה קלפים מציגים מאחור
    /// Off-screen distance (pt) a card travels on exit fling / undo re-entry.
    private let cardFlingDistance: CGFloat = 500
    /// Divisor mapping horizontal drag translation to rotation degrees.
    private let cardRotationDivisor: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let cardW = min(geometry.size.width - 40, geometry.size.height * 9.0 / 16.0)
            let cardH = cardW * 16.0 / 9.0
            ZStack {
                if [.denied, .restricted].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite)) {
                    EmptyStateView.galleryAccessDenied(onOpenSettings: UIApplication.shared.openSettings)
                } else if viewModel.isOfflineMode && viewModel.isScanning && viewModel.photoStack.isEmpty {
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
                        onImportPhotos: PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
                            ? UIApplication.shared.openSettings : nil,
                        onReviewSnoozed: viewModel.pendingSnoozedCount > 0 ? { viewModel.flushSnoozedItemsNow() } : nil,
                        onExitOfflineMode: viewModel.isOfflineMode ? onExitOfflineMode : nil,
                        reviewBinCount: viewModel.reviewBin.count,
                        snoozedCount: viewModel.pendingSnoozedCount,
                        currentFilter: viewModel.currentFilter,
                        isOfflineMode: viewModel.isOfflineMode,
                        offlineFoundNoLocalItems: viewModel.offlineFoundNoLocalItems
                    )
                    .id("victory")
                } else {
                    cardStack(cardW: cardW, cardH: cardH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { cardSize = CGSize(width: cardW, height: cardH) }
            .animation(.easeInOut(duration: 0.35), value: viewModel.isScanning)
            // Covers the denied/restricted → loading → cards handoff (scenePhase
            // recovery never wraps the ViewModel reload in withAnimation — per the
            // "no withAnimation on @Published mutations" rule, the crossfade is
            // scoped here instead, on the container that actually swaps branches).
            .animation(.easeInOut(duration: 0.35), value: viewModel.isLoading)
            // Shuffle / offline transition modifiers — applied to the whole card area.
            .offset(y: cardStackOffset)
            .scaleEffect(cardStackScale)
            .opacity(cardStackOpacity)
        }
        .padding(.vertical, 10)
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: isPinching) { _, zooming in
            if !zooming {
                // Explicit withAnimation — this reset used to rely on an implicit
                // .animation(value: pinchScale/pinchOffset) modifier on the top card, which
                // was removed when the transform moved to .visualEffect (visualEffect
                // reads still animate correctly under withAnimation, but no longer under a
                // sibling .animation(value:) modifier, since that would just reintroduce
                // the direct body-level dependency visualEffect exists to avoid).
                withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                    pinchScale = 1.0
                    pinchOffset = .zero
                }
                // pinchAnchor intentionally not reset here — see original rationale
                // in SwipeStackView: resetting it mid-spring causes a visible jump.
            }
        }
        .onChange(of: pendingUndoRequest) { _, request in
            guard let request else { return }
            runUndoEntry(for: request.action)
        }
    }

    private func aestheticScore(for item: PhotoItem) -> Int? {
        viewModel.loadedScoreIDs.contains(item.id)
            ? AestheticScoringService.shared.cachedScore(for: item.id)
            : nil
    }

    /// A single `ForEach` over the visible window, keyed by item id — the same shape as
    /// the pre-refactor architecture. This matters for more than code size: because every
    /// card (including the top one) is now tracked by ONE identity-preserving `ForEach`,
    /// a card promoted from index 1 to index 0 (the next card, after a swipe removes the
    /// old top card) is recognized by SwiftUI as *the same view* whose index changed — not
    /// a new view replacing an old one. That's what makes the index-driven scale/offset/
    /// rotation/opacity modifiers below actually animatable: a `withAnimation`/`.animation(value:)`
    /// can only interpolate a *persisting* view's changing properties, never "animate
    /// between two different views." A prior version of this file split background cards
    /// (a separate `ForEach`) from the top card (a separate `if let` with a manual
    /// `.id()`) for type-checker reasons — but that put the promoted card in a genuinely
    /// different structural tree position each time, which SwiftUI always treats as
    /// destroy-old/create-new regardless of matching ids across that boundary. That
    /// architecture could only "pop" a promoted card into place, never interpolate it —
    /// which is why an earlier attempt at this used a custom `.transition()` (removed;
    /// transitions animate insertion/removal, not a persisting view's property changes,
    /// so it couldn't actually smooth this case either).
    ///
    /// **Every modifier in this row — including gesture/`.visualEffect` attachment — must
    /// stay structurally identical across all indices, varying only by *value* (ternaries
    /// as arguments), never by *branch* (`if/else` wrapping the card differently per
    /// index).** An earlier version of this fix routed index-0-only gestures through
    /// `if index == 0 { applyTopCardGestures(base) } else { base }` — that `if/else` is a
    /// `_ConditionalContent` structural branch, and a card crossing from the `else` side to
    /// the `if` side (exactly what happens when it's promoted to index 0) is a destroy-old/
    /// create-new event to SwiftUI, identical in kind to the `if let`/`ForEach` split bug
    /// documented above — it silently re-broke the exact identity continuity this
    /// architecture exists to provide, so the promotion animation never played. Gestures
    /// are applied unconditionally below, neutralized to a no-op for background cards via
    /// ternary *values* instead.
    @ViewBuilder
    private func cardStack(cardW: CGFloat, cardH: CGFloat) -> some View {
        ForEach(
            Array(viewModel.photoStack.prefix(cardStackSize).enumerated()),
            id: \.element.id
        ) { index, item in
            let isTop = index == 0
            PhotoCardView(
                item: item,
                isTopCard: isTop,
                cachedImage: viewModel.image(for: item.id),
                isCachedImageFinal: viewModel.finalImageIDs.contains(item.id),
                aestheticScore: aestheticScore(for: item),
                onShare: isTop ? { [weak viewModel] completion in
                    viewModel?.shareItem(item, completion: completion)
                } : nil
            )
            .equatable()
            .frame(width: cardW, height: cardH)
            .zIndex(Double(cardStackSize - index))
            // Pure function of index (+ the item's own fixed random tilt for the
            // background look) — index only changes once per completed swipe/undo/snooze,
            // never mid-drag, so animating it here doesn't touch the per-frame drag path
            // at all (that's the .visualEffect below, composed on top). This is the actual
            // "smooth elevation" fix: the SAME view instance's scale/offset/rotation/
            // opacity spring from the index-1 look to the index-0 look, because — per the
            // identity note above — it never stopped being the same view.
            .scaleEffect(isTop ? 1.0 : 1.0 - CGFloat(index) * 0.05)
            .offset(y: isTop ? 0 : CGFloat(index * 8))
            .rotationEffect(.degrees(isTop ? 0 : item.rotation))
            .opacity(isTop ? 1.0 : 1.0 - Double(index) * 0.2)
            // Only the card *arriving* at index 0 gets the spring — every other card
            // (e.g. index 2 → 1, or a freshly-paginated card entering at index 2) snaps
            // straight to its new background position with no motion.
            .animation(isTop ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: index)
            // Drag/pinch live transform — neutralized (identity values) for background
            // cards rather than branched away, so every row keeps the exact same
            // structural shape (see the doc above for why that's required). Reading
            // dragOffset/pinchScale/etc. here for background rows too is harmless — this
            // closure is deferred to SwiftUI's layout phase regardless of `isTop`, so it
            // never touches CardStackView.body.
            .visualEffect { effect, _ in
                effect
                    .offset(x: isTop ? dragOffset.width : 0, y: isTop ? dragOffset.height : 0)
                    .scaleEffect(isTop ? pinchScale : 1.0, anchor: pinchAnchor)
                    .offset(isTop ? pinchOffset : .zero)
                    .rotationEffect(.degrees(isTop ? dragRotation : 0))
            }
            .gesture(isTop ? dragGesture : nil)
            .simultaneousGesture(isTop && !isUndoAnimating ? pinchGesture : nil)
            .overlay {
                // Conditional content INSIDE .overlay is safe — it's a decorative sibling
                // layer, not a branch around the card itself, so it never disturbs the
                // card's own identity/@State the way branching `base` did.
                if isTop && isDragging {
                    SwipeIndicator(direction: swipeDirection)
                        .visualEffect { effect, _ in
                            let progress = min(dragOffset.magnitude / 100, 1.0)
                            return effect.opacity(progress).scaleEffect(progress)
                        }
                }
            }
        }
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

    // MARK: - Pinch Gesture

    // Pure SwiftUI: MagnificationGesture handles scale, inner DragGesture captures the
    // anchor (startLocation) and drives pan. Both coexist with the primary DragGesture
    // (swipe) via .simultaneousGesture — iOS naturally routes 1-finger to DragGesture
    // and 2-finger to MagnificationGesture without any hitTest tricks.
    // Spring reset lives in onChange(of: isPinching) above so it runs inside SwiftUI's
    // render cycle where withAnimation is reliable; onEnded only flips the flag.
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                pinchScale = max(1.0, scale)
                if !isPinching, pinchScale > 1.01 {
                    isPinching = true
                    // A single-finger drag may already be mid-flight when the second
                    // finger lands — dragGesture.onChanged bails out once isPinching
                    // is true, so without this reset dragOffset/dragRotation would
                    // stay frozen at their last value and stack underneath pinchOffset
                    // for the whole gesture instead of the card tracking the pinch.
                    dragOffset = .zero
                    dragRotation = 0
                    // Also reset swipeDirection — dragGesture.onChanged won't run again to
                    // do it (blocked by isPinching), and isDragging stays true throughout
                    // the pinch (DragGesture.onEnded hasn't fired), so without this the
                    // SwipeIndicator overlay would keep whatever direction was last live,
                    // just invisible because dragOffset (and thus its opacity) reset to zero.
                    swipeDirection = .none
                }
            }
            .onEnded { _ in
                // Spring reset handled by onChange(of: isPinching) above.
                isPinching = false
                pinchPanOrigin = .zero
            }
            .simultaneously(with:
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { drag in
                        if !isPinching {
                            // Capture anchor from touch start — best approximation of
                            // centroid available in pure SwiftUI (no 2-finger centroid API).
                            if cardSize.width > 0 {
                                pinchAnchor = UnitPoint(
                                    x: min(1, max(0, drag.startLocation.x / cardSize.width)),
                                    y: min(1, max(0, drag.startLocation.y / cardSize.height))
                                )
                            }
                            pinchPanOrigin = drag.translation
                        } else {
                            // .local coords are in the view's unscaled frame, so multiply
                            // delta by pinchScale to get 1:1 screen-space movement.
                            let dx = (drag.translation.width  - pinchPanOrigin.width)  * pinchScale
                            let dy = (drag.translation.height - pinchPanOrigin.height) * pinchScale
                            pinchOffset = CGSize(width: dx, height: dy)
                        }
                    }
            )
    }

    // MARK: - Swipe Gesture

    // In RTL layout iOS flips the translation.width sign.
    // We normalize it here so swipe-right always means Keep
    // and swipe-left always means Delete regardless of locale.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Pan is handled exclusively by pinchGesture's inner DragGesture.
                // If this 1-finger recognizer fires during a 2-finger pinch its
                // translation comes from the wrong touch point and corrupts pinchOffset.
                guard !isPinching, !isUndoAnimating else { return }
                if !isDragging {
                    isDragging = true
                    viewModel.cancelPrefetch()
                }
                dragOffset = value.translation
                dragRotation = Double(value.translation.width / cardRotationDivisor)
                let newDirection = SwipeDirection.from(offset: value.translation)
                if newDirection != swipeDirection { swipeDirection = newDirection }

                // Fire early pre-load once the drag clears 30 pt.
                // This gives us the remainder of the gesture (~300-500 ms) to
                // pull the next card's image into NSCache before it hits screen.
                if !hasFiredEarlyPrecache,
                   abs(value.translation.width) > 30 || abs(value.translation.height) > 30 {
                    hasFiredEarlyPrecache = true
                    viewModel.prepareUpcomingCards()
                }
            }
            .onEnded { value in
                guard !isUndoAnimating else { return }
                isDragging = false
                hasFiredEarlyPrecache = false
                swipeDirection = .none
                // If a pinch is active or scale hasn't fully reset, discard swipe.
                // MagnificationGesture.onEnded owns the spring-reset of pinchOffset.
                // Routed through resetCardPosition() (not an inline withAnimation) so this
                // path also gets the .resumeTopCardVideo re-sync — a pinch-interrupted drag
                // is just another case of "drag ended without a swipe."
                guard !isPinching, pinchScale <= 1.01 else {
                    resetCardPosition()
                    return
                }
                // SwipeDirection uses the RAW translation (not flipped)
                // because .left/.right are already correct in RTL context.
                let direction = SwipeDirection.from(offset: value.translation)

                if let action = direction.action, let swipedItem = viewModel.topCard {
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
                            dragOffset = CGSize(width: -cardFlingDistance, height: value.translation.height)
                        case .right:
                            dragOffset = CGSize(width: cardFlingDistance, height: value.translation.height)
                        case .up:
                            dragOffset = CGSize(width: value.translation.width, height: -cardFlingDistance)
                        case .none:
                            break
                        }
                    }

                    // Mark the swipe pending *now*, synchronously — makes canUndo/lastAction
                    // point at this card immediately instead of the previous one, so a shake
                    // or Undo tap during the exit-fly below can never restore the wrong photo.
                    viewModel.beginSwipe(swipedItem, action: action)

                    // Perform the actual removal after exit-animation completes.
                    // Crucially we reset dragOffset WITHOUT animation so the
                    // incoming card never inherits the ±500 offset and slides in.
                    NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // swipedItem was captured at gesture-end, not re-read here — the
                        // stack's front can change in the meantime (e.g. shake-to-undo),
                        // so the action must stay bound to the exact card the user swiped.
                        // finalizeSwipe no-ops (returns false) if the user already undid this
                        // exact swipe mid-flight — in that case dragOffset/dragRotation now
                        // belong to the undo's own landing animation and must not be touched.
                        guard viewModel.finalizeSwipe(swipedItem, action: action) else { return }
                        dragOffset = .zero
                        dragRotation = 0
                        onSwipeFinalized(swipedItem, action)
                    }
                } else {
                    // Spring back to centre
                    resetCardPosition()
                }
                viewModel.resumePrefetch()
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

    /// Shake/tap-to-undo re-entry: the restored card enters from the same edge it exited
    /// through, tilted the same way it was mid-swipe, then an underdamped spring pulls it
    /// back to center with a slight overshoot ("deck-landing" feel). SwipeStackView's
    /// performUndo() already called viewModel.undoLastAction() and set isUndoAnimating
    /// (which blocks this view's own dragGesture) before this fires.
    private func runUndoEntry(for action: SwipeAction) {
        undoGeneration += 1
        let generation = undoGeneration

        let entryRotation = Double(cardFlingDistance / cardRotationDivisor)
        switch action {
        case .delete:
            dragOffset = CGSize(width: -cardFlingDistance, height: 0)
            dragRotation = -entryRotation
        case .keep:
            dragOffset = CGSize(width: cardFlingDistance, height: 0)
            dragRotation = entryRotation
        case .snooze:
            dragOffset = CGSize(width: 0, height: -cardFlingDistance)
            dragRotation = 0
        case .undo:
            break
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(
                .spring(response: 0.45, dampingFraction: 0.75),
                completionCriteria: .logicallyComplete
            ) {
                dragOffset = .zero
                dragRotation = 0
            } completion: {
                if undoGeneration == generation { isUndoAnimating = false }
            }
        }
        // Safety net: guarantees the gesture unblocks even if the animation's
        // completion handler never fires (e.g. app backgrounded mid-flight).
        // Generation-gated so a stale timer from an earlier undo can't clear
        // isUndoAnimating while a newer undo's animation is still in flight.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if undoGeneration == generation { isUndoAnimating = false }
        }
    }
}
