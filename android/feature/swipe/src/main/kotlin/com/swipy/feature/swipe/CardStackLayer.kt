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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.model.SwipeAction
import kotlin.math.hypot
import kotlinx.collections.immutable.ImmutableList
import kotlinx.coroutines.launch

private const val CARD_STACK_SIZE = 3
private const val ROTATION_SENSITIVITY = 20f
private const val MAX_ROTATION_DEGREES = 15f
private val SWIPE_THRESHOLD = 120.dp
private val BACKGROUND_CARD_STEP = 18.dp
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
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val thresholdPx = with(density) { SWIPE_THRESHOLD.toPx() }
        val backgroundStepPx = with(density) { BACKGROUND_CARD_STEP.toPx() }
        val flingDistanceXPx = with(density) { maxWidth.toPx() } * 1.5f
        val flingDistanceYPx = with(density) { maxHeight.toPx() } * 1.5f
        val indicatorFadeDistancePx = with(density) { INDICATOR_FADE_DISTANCE.toPx() }

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

                // The card itself — translation/rotation/scale + the drag gesture. SwipeIndicator
                // is a SEPARATE sibling below (not nested in this Box) — it must NOT inherit this
                // graphicsLayer's translation, or it slides off-screen along with a far-dragged
                // card instead of staying pinned to the screen edge (found via on-device testing:
                // nesting it here, matching iOS's `.overlay` being chained after CardStackView's
                // transform modifiers, reads correctly in SwiftUI but does not translate to
                // Compose the same way once the card is dragged past a few hundred px).
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .zIndex((CARD_STACK_SIZE - index).toFloat())
                        .graphicsLayer {
                            translationX = if (isTop) offsetX.value else 0f
                            translationY = if (isTop) offsetY.value else restingOffsetY
                            rotationZ = if (isTop) rotation.value else 0f
                            scaleX = restingScale
                            scaleY = restingScale
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
                // themselves fill, un-transformed) — only opacity/scale react to drag magnitude,
                // never position, so Keep/Delete/Later always stay readable at the screen edge
                // regardless of how far the card underneath has been dragged. A decorative
                // conditional sibling, not a branch around the card — safe per android/CLAUDE.md
                // "Conditional Animation".
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
