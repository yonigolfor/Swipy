package com.swipy.feature.swipe

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
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
) {
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

        val visible = items.take(CARD_STACK_SIZE)

        visible.forEachIndexed { index, item ->
            key(item.id) {
                val isTop = index == 0
                val scope = rememberCoroutineScope()

                val offsetX = remember { Animatable(0f) }
                val offsetY = remember { Animatable(0f) }
                val rotation = remember { Animatable(0f) }
                var swipeDirection by remember { mutableStateOf<SwipeAction?>(null) }
                var isDragging by remember { mutableStateOf(false) }

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
                            translationX = if (isTop) offsetX.value else 0f
                            translationY = if (isTop) offsetY.value else restingOffsetY
                            rotationZ = if (isTop) rotation.value else tiltDegrees
                            scaleX = restingScale
                            scaleY = restingScale
                            alpha = restingAlpha
                        }
                        .pointerInput(item.id, isTop) {
                            if (!isTop) return@pointerInput
                            detectDragGestures(
                                onDragStart = { isDragging = true },
                                onDrag = { change, dragAmount ->
                                    change.consume()
                                    scope.launch {
                                        offsetX.snapTo(offsetX.value + dragAmount.x)
                                        offsetY.snapTo(offsetY.value + dragAmount.y)
                                        rotation.snapTo(
                                            (offsetX.value / ROTATION_SENSITIVITY)
                                                .coerceIn(-MAX_ROTATION_DEGREES, MAX_ROTATION_DEGREES),
                                        )
                                    }
                                    // Reuses the same threshold/resolution as the actual commit
                                    // decision below (unlike iOS, which happens to use one
                                    // shared 80pt SwipeDirection.from(offset:) for both already)
                                    // — the live badge preview must never show a direction that
                                    // wouldn't actually commit if released right now.
                                    val newDirection = resolveSwipeDirection(offsetX.value, offsetY.value, thresholdPx)
                                    if (newDirection != swipeDirection) swipeDirection = newDirection
                                },
                                onDragEnd = {
                                    isDragging = false
                                    swipeDirection = null
                                    val direction = resolveSwipeDirection(offsetX.value, offsetY.value, thresholdPx)
                                    scope.launch {
                                        if (direction != null) {
                                            val targetX = when (direction) {
                                                SwipeAction.Keep -> flingDistanceXPx
                                                SwipeAction.Delete -> -flingDistanceXPx
                                                else -> offsetX.value
                                            }
                                            val targetY = if (direction == SwipeAction.Snooze) {
                                                -flingDistanceYPx
                                            } else {
                                                offsetY.value
                                            }
                                            launch { offsetX.animateTo(targetX, tween(220)) }
                                            launch { offsetY.animateTo(targetY, tween(220)) }
                                            onSwipeCommitted(item, direction)
                                        } else {
                                            val snapBack = spring<Float>(dampingRatio = Spring.DampingRatioMediumBouncy)
                                            launch { offsetX.animateTo(0f, snapBack) }
                                            launch { offsetY.animateTo(0f, snapBack) }
                                            launch { rotation.animateTo(0f, snapBack) }
                                        }
                                    }
                                },
                                onDragCancel = {
                                    isDragging = false
                                    swipeDirection = null
                                },
                            )
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
                                val progress = (hypot(offsetX.value, offsetY.value) / indicatorFadeDistancePx)
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
