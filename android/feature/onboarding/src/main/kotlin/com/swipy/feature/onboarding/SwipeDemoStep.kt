package com.swipy.feature.onboarding

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.component.GoldCapsuleButton
import com.swipy.core.designsystem.haptics.rememberHapticManager
import com.swipy.core.designsystem.theme.SwipeGreen
import com.swipy.core.designsystem.theme.SwipeRed
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val FLY_OFF_THRESHOLD = 80f
private const val FLY_OFF_DISTANCE = 500f
private const val ROTATION_DIVISOR = 20f

/** Port of iOS `step3_SwipeDemo` (OnboardingView.swift:351-490) — draggable mock card with a
 * KEEP/DELETE label overlay, fly-off past an 80dp threshold, resets after a beat. */
@Composable
fun SwipeDemoStep(onNext: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(Modifier.weight(1f))

        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = stringResource(R.string.onboarding_demo_title), fontSize = 32.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Spacer(Modifier.height(8.dp))
            Text(text = stringResource(R.string.onboarding_demo_subtitle), fontSize = 14.sp, color = Color.Gray)
        }

        Spacer(Modifier.height(24.dp))

        Box(modifier = Modifier.fillMaxWidth().height(320.dp), contentAlignment = Alignment.Center) {
            OnboardingMockCardBackground(
                topWhite = 0.18f,
                bottomWhite = 0.18f,
                modifier = Modifier.size(240.dp, 300.dp).graphicsLayer { translationY = 10.dp.toPx(); scaleX = 0.95f; scaleY = 0.95f },
            )
            DemoCard()
        }

        Spacer(Modifier.height(24.dp))
        Text(
            text = stringResource(R.string.onboarding_demo_hint),
            fontSize = 12.sp,
            color = Color.Gray,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(Modifier.weight(1f))

        GoldCapsuleButton(
            text = stringResource(R.string.onboarding_demo_cta),
            onClick = onNext,
            modifier = Modifier.padding(start = 32.dp, end = 32.dp, bottom = 48.dp),
        )
    }
}

private enum class DemoSwipeDirection { Delete, Keep }

@Composable
private fun DemoCard() {
    val scope = rememberCoroutineScope()
    val hapticManager = rememberHapticManager()
    val offsetX = remember { Animatable(0f) }
    val offsetY = remember { Animatable(0f) }
    var visible by remember { mutableStateOf(true) }
    // Direction, not the resolved localized string — comparing a stored label against a
    // hardcoded "Delete" literal would silently break once the rendered text is Hebrew.
    var direction by remember { mutableStateOf<DemoSwipeDirection?>(null) }

    if (!visible) return

    Box(
        modifier = Modifier
            .size(240.dp, 300.dp)
            .graphicsLayer {
                translationX = offsetX.value
                translationY = offsetY.value
                rotationZ = offsetX.value / ROTATION_DIVISOR
            }
            .pointerInput(Unit) {
                detectDragGestures(
                    onDrag = { change, dragAmount ->
                        change.consume()
                        scope.launch {
                            offsetX.snapTo(offsetX.value + dragAmount.x)
                            offsetY.snapTo(offsetY.value + dragAmount.y)
                        }
                        val newDirection = when {
                            offsetX.value < -30f -> DemoSwipeDirection.Delete
                            offsetX.value > 30f -> DemoSwipeDirection.Keep
                            else -> null
                        }
                        if (newDirection != direction) {
                            direction = newDirection
                            // iOS calls softHaptic.impactOccurred() on every raw onChanged
                            // frame — only on direction transitions here instead, since
                            // Vibrator.vibrate() has no per-app coalescing the way UIKit's
                            // taptic engine does (see HapticManager.softTick's doc comment).
                            hapticManager.softTick()
                        }
                    },
                    onDragEnd = {
                        val dx = offsetX.value
                        if (kotlin.math.abs(dx) > FLY_OFF_THRESHOLD) {
                            hapticManager.mediumTap()
                            val targetX = if (dx > 0) FLY_OFF_DISTANCE else -FLY_OFF_DISTANCE
                            scope.launch {
                                offsetX.animateTo(targetX, spring(dampingRatio = 0.7f, stiffness = 260f))
                                visible = false
                                offsetX.snapTo(0f)
                                offsetY.snapTo(0f)
                                direction = null
                                delay(150)
                                visible = true
                            }
                        } else {
                            scope.launch {
                                val snapBack = spring<Float>(dampingRatio = Spring.DampingRatioMediumBouncy)
                                offsetX.animateTo(0f, snapBack)
                                offsetY.animateTo(0f, snapBack)
                            }
                            direction = null
                        }
                    },
                )
            },
    ) {
        OnboardingMockCardBackground(topWhite = 0.28f, bottomWhite = 0.20f, modifier = Modifier.fillMaxSize())
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
        ) {
            Text(text = "🖼️", fontSize = 50.sp)
            Spacer(Modifier.height(12.dp))
            Text(
                text = stringResource(R.string.onboarding_demo_hint),
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.7f),
            )
        }
        direction?.let { swipeDirection ->
            val isDelete = swipeDirection == DemoSwipeDirection.Delete
            val color = if (isDelete) SwipeRed else SwipeGreen
            val text = if (isDelete) {
                stringResource(com.swipy.core.designsystem.R.string.swipe_action_delete)
            } else {
                stringResource(com.swipy.core.designsystem.R.string.swipe_action_keep)
            }
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text = text,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    color = color,
                    modifier = Modifier
                        .graphicsLayer { rotationZ = if (isDelete) -15f else 15f }
                        .background(color.copy(alpha = 0.2f), CircleShape)
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }
}
