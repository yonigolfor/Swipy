package com.swipy.feature.swipe

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.swipy.core.designsystem.haptics.rememberHapticManager
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.model.SwipeAction
import kotlin.math.hypot
import kotlin.random.Random
import kotlinx.collections.immutable.ImmutableList
import kotlinx.coroutines.launch

private const val CARD_STACK_SIZE = 3
private const val ROTATION_SENSITIVITY = 20f
private const val MAX_ROTATION_DEGREES = 15f
private val SWIPE_THRESHOLD = 120.dp

/** Total horizontal margin (both sides combined) around the card — mirrors iOS
 * `geometry.size.width - 40` (CardStackView.swift:103). */
private val CARD_HORIZONTAL_MARGIN = 40.dp

/** Background-card recede step per index — mirrors iOS's `index * 8pt` (CardStackView.swift:224). */
private val BACKGROUND_CARD_STEP = 8.dp

/** Fixed per-item tilt range — mirrors iOS `Double.random(in: -4...4)` (PhotoItem.swift:33).
 * Seeded from the item's own id (not re-rolled on every recomposition/relaunch) so a card's
 * tilt stays stable for as long as it's visible, the same way iOS assigns it once at model
 * creation rather than computing it fresh in the view. */
private const val MAX_TILT_DEGREES = 4f

/**
 * Drag magnitude at which the SwipeIndicator reaches full opacity/scale. NOT a literal port of
 * iOS's 100pt (CardStackView.swift:253) — iOS's direction unlocks at 80pt, 80% of its own 100pt
 * fade distance, so the badge is already 80% faded in the instant it appears and finishes over
 * the remaining 20%. Android's direction unlocks at SWIPE_THRESHOLD (120dp, reusing the actual
 * commit threshold — see the onDrag comment below for why), which is already past a 100dp fade
 * distance; keeping 100dp here would make the badge pop in at full opacity with no visible fade
 * at all. 150dp preserves the same 80%-faded-on-appearance ratio (120 / 150 = 0.8) instead.
 */
private val INDICATOR_FADE_DISTANCE = 150.dp

/**
 * Owns every continuous gesture value locally — never hoists a per-frame drag delta into
 * PhotoStackUiState/StateFlow. See android/CLAUDE.md "Gesture Engine & Card Stack
 * Performance" for the full rationale; this is the direct Compose port of that doc.
 */
@Composable
fun CardStackLayer(
    items: ImmutableList<PhotoItem>,
    onSwipeCommitted: (PhotoItem, SwipeAction) -> Unit,
    modifier: Modifier = Modifier,
    onPinchStateChanged: (Boolean) -> Unit = {},
    // Synchronous, cheap (StateFlow.value reads only) — lets a Keep/Delete crossing the fling
    // threshold be vetoed (daily quota exhausted) BEFORE the fling animation plays, instead of
    // flinging the card off-screen and only then discovering the ViewModel silently ignored it.
    // Default `{ true }` preserves prior behavior for any caller (tests, previews) that doesn't
    // care about the quota gate. See PhotoStackViewModel.canCommitSwipe's own doc comment.
    canCommitSwipe: (SwipeAction) -> Boolean = { true },
) {
    val hapticManager = rememberHapticManager()

    BoxWithConstraints(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        val density = LocalDensity.current
        val thresholdPx = with(density) { SWIPE_THRESHOLD.toPx() }
        val backgroundStepPx = with(density) { BACKGROUND_CARD_STEP.toPx() }
        val flingDistanceXPx = with(density) { maxWidth.toPx() } * 1.5f
        val flingDistanceYPx = with(density) { maxHeight.toPx() } * 1.5f
        val indicatorFadeDistancePx = with(density) { INDICATOR_FADE_DISTANCE.toPx() }

        // Fixed 9:16 portrait card, capped by either the available width (minus side margins)
        // or the available height — mirrors iOS CardStackView.swift:103-104 exactly. This is
        // what makes the stack read as a centered "deck of cards" with visible background
        // around it, rather than an edge-to-edge full-bleed image.
        val cardW = minOf(maxWidth - CARD_HORIZONTAL_MARGIN, maxHeight * 9f / 16f)
        val cardH = cardW * 16f / 9f
        val cardWidthPx = with(density) { cardW.toPx() }
        val cardHeightPx = with(density) { cardH.toPx() }

        val visible = items.take(CARD_STACK_SIZE)

        visible.forEachIndexed { index, item ->
            key(item.id) {
                val isTop = index == 0
                val scope = rememberCoroutineScope()

                // Plain synchronous floats, not Animatable — a drag callback fires up to 120x/sec
                // and isn't itself suspend, so driving it through Animatable.snapTo() forced a
                // fresh coroutine launch (and a MutatorMutex cancel/re-acquire) per frame purely
                // to bridge into a suspend API. animate() below drives these same floats for the
                // release/snap-back animation, so Animatable's machinery is only ever paid for
                // once per gesture, not once per frame. See android/CLAUDE.md "Gesture Engine &
                // Card Stack Performance".
                var offsetX by remember { mutableFloatStateOf(0f) }
                var offsetY by remember { mutableFloatStateOf(0f) }
                var rotation by remember { mutableFloatStateOf(0f) }
                var swipeDirection by remember { mutableStateOf<SwipeAction?>(null) }
                var isDragging by remember { mutableStateOf(false) }

                // Pinch-to-zoom state — same "plain synchronous state, never Animatable during
                // the active gesture" discipline as the drag values above. pinchAnchor is
                // deliberately never reset back to center on release (matches iOS
                // CardStackView.swift's pinchGesture comment) — resetting it would cause a
                // visible jump the next time the user zooms.
                var pinchScale by remember { mutableFloatStateOf(1f) }
                var pinchOffset by remember { mutableStateOf(Offset.Zero) }
                var pinchAnchor by remember { mutableStateOf(TransformOrigin.Center) }

                // Stable per-card tilt for the background/receding look — computed once per
                // item id, not re-rolled on every recomposition.
                val tiltDegrees = remember(item.id) {
                    Random(item.id).nextFloat() * (2 * MAX_TILT_DEGREES) - MAX_TILT_DEGREES
                }

                // Only the card ARRIVING at index 0 springs into place — every other index
                // change snaps instantly. Getting this backwards (animating every index
                // change) was an iOS regression this doc explicitly warns against; see
                // "Conditional Animation" in android/CLAUDE.md.
                val restingScale by animateFloatAsState(
                    targetValue = 1f - (index * 0.05f),
                    animationSpec = if (isTop) spring(dampingRatio = 0.85f, stiffness = 380f) else tween(0),
                    label = "cardScale",
                )
                val restingOffsetY by animateFloatAsState(
                    targetValue = index * backgroundStepPx,
                    animationSpec = if (isTop) spring(dampingRatio = 0.85f, stiffness = 380f) else tween(0),
                    label = "cardRestingOffsetY",
                )
                // Receding opacity for background cards — mirrors iOS `1.0 - index * 0.2`
                // (CardStackView.swift:226). A pure function of index like restingScale/
                // restingOffsetY above, so index 0 naturally evaluates to fully opaque with
                // no isTop branch needed.
                val restingAlpha by animateFloatAsState(
                    targetValue = 1f - (index * 0.2f),
                    animationSpec = if (isTop) spring(dampingRatio = 0.85f, stiffness = 380f) else tween(0),
                    label = "cardAlpha",
                )

                // The card itself — translation/rotation/scale + the drag gesture. SwipeIndicator
                // is a SEPARATE sibling below (not nested in this Box) — it must NOT inherit this
                // graphicsLayer's translation, or it slides off-screen along with a far-dragged
                // card instead of staying pinned to the screen edge (found via on-device testing:
                // nesting it here, matching iOS's `.overlay` being chained after CardStackView's
                // transform modifiers, reads correctly in SwiftUI but does not translate to
                // Compose the same way once the card is dragged past a few hundred px).
                //
                // Every value read inside this graphicsLayer lambda (offsetX/offsetY/rotation/
                // restingScale/restingOffsetY/restingAlpha/tiltDegrees) is deferred to the draw
                // phase, not read in this composable's own body — a drag frame therefore never
                // triggers a recomposition here, only a re-draw, so it can't be the source of
                // any layout-level bleed-through the way the earlier NavHost back-stack bug was.
                Box(
                    modifier = Modifier
                        .size(cardW, cardH)
                        .zIndex((CARD_STACK_SIZE - index).toFloat())
                        .graphicsLayer {
                            // Drag offset and pinch pan are never simultaneously non-zero —
                            // entering a pinch resets offsetX/offsetY to 0, and drag is
                            // suppressed for the rest of the gesture once a pinch has started
                            // (see the pointerInput block below) — so adding them here is safe.
                            translationX = if (isTop) offsetX + pinchOffset.x else 0f
                            translationY = if (isTop) offsetY + pinchOffset.y else restingOffsetY
                            scaleX = if (isTop) restingScale * pinchScale else restingScale
                            scaleY = if (isTop) restingScale * pinchScale else restingScale
                            transformOrigin = if (isTop) pinchAnchor else TransformOrigin.Center
                            alpha = restingAlpha
                        }
                        // Separate layer so rotation always pivots around the card's own
                        // center, independent of pinchAnchor — a single graphicsLayer shares
                        // one transformOrigin between scale and rotation, but iOS's
                        // rotationEffect/scaleEffect are independent modifiers with
                        // independent anchors (rotation always about center). Stacking two
                        // layers is what lets Compose reproduce that independence — this
                        // layer's rotation is applied to the already translated+scaled result
                        // of the layer above, pivoting about the (untransformed) card bounds,
                        // exactly mirroring iOS's offset → scale(anchor) → offset → rotate
                        // modifier chain order (CardStackView.swift "cardStack").
                        .graphicsLayer {
                            rotationZ = if (isTop) rotation else tiltDegrees
                        }
                        .pointerInput(item.id, isTop) {
                            if (!isTop) return@pointerInput

                            fun applyDrag(delta: Offset) {
                                offsetX += delta.x
                                offsetY += delta.y
                                rotation = (offsetX / ROTATION_SENSITIVITY)
                                    .coerceIn(-MAX_ROTATION_DEGREES, MAX_ROTATION_DEGREES)
                                // Reuses the same threshold/resolution as the actual commit
                                // decision below (unlike iOS, which happens to use one shared
                                // 80pt SwipeDirection.from(offset:) for both already) — the
                                // live badge preview must never show a direction that wouldn't
                                // actually commit if released right now.
                                val newDirection = resolveSwipeDirection(offsetX, offsetY, thresholdPx)
                                if (newDirection != swipeDirection) {
                                    swipeDirection = newDirection
                                    hapticManager.thresholdCrossed()
                                }
                            }

                            fun endPinch() {
                                onPinchStateChanged(false)
                                val snapBack = spring<Float>(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = 440f)
                                scope.launch {
                                    launch { animate(pinchScale, 1f, animationSpec = snapBack) { value, _ -> pinchScale = value } }
                                    launch {
                                        animate(pinchOffset.x, 0f, animationSpec = snapBack) { value, _ -> pinchOffset = pinchOffset.copy(x = value) }
                                    }
                                    launch {
                                        animate(pinchOffset.y, 0f, animationSpec = snapBack) { value, _ -> pinchOffset = pinchOffset.copy(y = value) }
                                    }
                                }
                                // pinchAnchor intentionally not reset — see its declaration comment.
                            }

                            fun endDrag() {
                                isDragging = false
                                swipeDirection = null
                                val rawDirection = resolveSwipeDirection(offsetX, offsetY, thresholdPx)
                                // A Keep/Delete crossing the threshold while the daily quota is
                                // exhausted must never fling off-screen — the card has to still
                                // be there (untouched in the ViewModel's stack) once the paywall
                                // is dismissed. Snooze/Undo are never quota-gated (mirrors iOS).
                                val blocked = rawDirection != null &&
                                    (rawDirection == SwipeAction.Keep || rawDirection == SwipeAction.Delete) &&
                                    !canCommitSwipe(rawDirection)
                                val direction = rawDirection.takeUnless { blocked }
                                scope.launch {
                                    if (direction != null) {
                                        val targetX = when (direction) {
                                            SwipeAction.Keep -> flingDistanceXPx
                                            SwipeAction.Delete -> -flingDistanceXPx
                                            else -> offsetX
                                        }
                                        val targetY = if (direction == SwipeAction.Snooze) {
                                            -flingDistanceYPx
                                        } else {
                                            offsetY
                                        }
                                        launch { animate(offsetX, targetX, animationSpec = tween(220)) { value, _ -> offsetX = value } }
                                        launch { animate(offsetY, targetY, animationSpec = tween(220)) { value, _ -> offsetY = value } }
                                        when (direction) {
                                            SwipeAction.Keep -> hapticManager.keep()
                                            SwipeAction.Delete -> hapticManager.delete()
                                            SwipeAction.Snooze -> hapticManager.snooze()
                                            SwipeAction.Undo -> Unit
                                        }
                                        onSwipeCommitted(item, direction)
                                    } else {
                                        val snapBack = spring<Float>(dampingRatio = Spring.DampingRatioMediumBouncy)
                                        launch { animate(offsetX, 0f, animationSpec = snapBack) { value, _ -> offsetX = value } }
                                        launch { animate(offsetY, 0f, animationSpec = snapBack) { value, _ -> offsetY = value } }
                                        launch { animate(rotation, 0f, animationSpec = snapBack) { value, _ -> rotation = value } }
                                        // Still notify the ViewModel of the blocked attempt (no
                                        // haptic, no fling) so it can fire the ShowPaywall effect —
                                        // handleSwipe re-checks the same guard and no-ops the stack.
                                        if (blocked) onSwipeCommitted(item, rawDirection!!)
                                    }
                                }
                            }

                            // Custom dual-mode detector (rather than detectDragGestures) — Compose
                            // has no SwiftUI-style "simultaneousGesture auto-routes by finger
                            // count" primitive, so 1-finger swipe and 2+-finger pinch-zoom are
                            // arbitrated here by inspecting the live pointer count each event, the
                            // same low-level pattern detectTransformGestures itself is built from
                            // (calculateZoom/calculatePan/calculateCentroid are its own public
                            // building blocks). Mirrors CardStackView.swift's MagnificationGesture
                            // .simultaneously(with: DragGesture) composition.
                            awaitEachGesture {
                                awaitFirstDown(requireUnconsumed = false)
                                var isPinchActive = false
                                // True once a pinch has been recognized and released within this
                                // gesture — a remaining single finger must NOT retroactively start
                                // a swipe drag, mirroring iOS's gesture-recognizer exclusivity.
                                var pinchEndedThisGesture = false
                                // Below-touch-slop movement accumulates here until it's large
                                // enough to count as an intentional drag (matches
                                // detectDragGestures' internal touch-slop behavior, which this
                                // custom detector otherwise replaces wholesale).
                                var slopAccumulator = Offset.Zero

                                while (true) {
                                    val event = awaitPointerEvent()
                                    val pressedChanges = event.changes.filter { it.pressed }

                                    when {
                                        pressedChanges.size >= 2 -> {
                                            if (!isPinchActive) {
                                                isPinchActive = true
                                                onPinchStateChanged(true)
                                                // A single-finger drag may already be mid-flight
                                                // when the second finger lands — without this
                                                // reset, offsetX/offsetY/rotation would stay
                                                // frozen at their last value and stack underneath
                                                // pinchOffset for the rest of the gesture instead
                                                // of the card tracking the pinch (mirrors iOS's
                                                // identical reset in pinchGesture.onChanged).
                                                isDragging = false
                                                swipeDirection = null
                                                offsetX = 0f
                                                offsetY = 0f
                                                rotation = 0f
                                                val centroid = event.calculateCentroid(useCurrent = true)
                                                pinchAnchor = TransformOrigin(
                                                    (centroid.x / cardWidthPx).coerceIn(0f, 1f),
                                                    (centroid.y / cardHeightPx).coerceIn(0f, 1f),
                                                )
                                            }
                                            val zoom = event.calculateZoom()
                                            // Local/content-space pan must be scaled by the
                                            // current pinchScale to read as 1:1 screen-space
                                            // movement — same correction iOS applies in its own
                                            // inner DragGesture (CardStackView.swift:353-357),
                                            // since pointerInput reports positions in the card's
                                            // pre-transform layout space, not the visually
                                            // scaled-up space.
                                            val pan = event.calculatePan()
                                            pinchScale = (pinchScale * zoom).coerceAtLeast(1f)
                                            pinchOffset += pan * pinchScale
                                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                                        }

                                        pressedChanges.size == 1 -> {
                                            val change = pressedChanges[0]
                                            when {
                                                isPinchActive -> {
                                                    isPinchActive = false
                                                    pinchEndedThisGesture = true
                                                    endPinch()
                                                    if (change.positionChanged()) change.consume()
                                                }
                                                pinchEndedThisGesture -> {
                                                    if (change.positionChanged()) change.consume()
                                                }
                                                change.positionChanged() -> {
                                                    val delta = change.positionChange()
                                                    if (!isDragging) {
                                                        slopAccumulator += delta
                                                        if (slopAccumulator.getDistance() > viewConfiguration.touchSlop) {
                                                            isDragging = true
                                                            change.consume()
                                                            applyDrag(slopAccumulator)
                                                        }
                                                    } else {
                                                        change.consume()
                                                        applyDrag(delta)
                                                    }
                                                }
                                            }
                                        }

                                        else -> break
                                    }
                                }

                                if (isDragging) endDrag()
                            }
                        },
                ) {
                    PhotoCardComposable(item = item, isTop = isTop, modifier = Modifier.fillMaxSize())
                }

                // Pinned to the SCREEN (this Box fills the same BoxWithConstraints the cards
                // themselves are centered inside — deliberately NOT sized to cardW/cardH, so
                // the badge stays readable at the screen edge regardless of how far the
                // smaller card underneath has been dragged), only opacity/scale react to drag
                // magnitude, never position. A decorative conditional sibling, not a branch
                // around the card — safe per android/CLAUDE.md "Conditional Animation".
                if (isTop && isDragging) {
                    SwipeIndicator(
                        direction = swipeDirection,
                        modifier = Modifier
                            .fillMaxSize()
                            .zIndex(1000f)
                            .graphicsLayer {
                                val progress = (hypot(offsetX, offsetY) / indicatorFadeDistancePx)
                                    .coerceIn(0f, 1f)
                                alpha = progress
                                scaleX = progress
                                scaleY = progress
                            },
                    )
                }
            }
        }
    }
}

private fun resolveSwipeDirection(offsetX: Float, offsetY: Float, thresholdPx: Float): SwipeAction? {
    val absX = kotlin.math.abs(offsetX)
    val absY = kotlin.math.abs(offsetY)
    return when {
        offsetY < -thresholdPx && absY >= absX -> SwipeAction.Snooze
        offsetX > thresholdPx && absX > absY -> SwipeAction.Keep
        offsetX < -thresholdPx && absX > absY -> SwipeAction.Delete
        else -> null
    }
}
