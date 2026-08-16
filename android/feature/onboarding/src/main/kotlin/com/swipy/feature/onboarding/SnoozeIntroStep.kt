package com.swipy.feature.onboarding

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.component.GoldCapsuleButton
import com.swipy.core.designsystem.theme.SwipeBlue
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val SNOOZE_LABEL_THRESHOLD = -30f
private const val SNOOZE_FLY_THRESHOLD = -80f
private const val SNOOZE_FLY_DISTANCE = -600f

/** Port of iOS `step_SnoozeIntro` (OnboardingView.swift:647-812) — upward-only drag demo with a
 * bouncing arrow hint and a second card peeking out from behind. */
@Composable
fun SnoozeIntroStep(onNext: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(Modifier.weight(1f))

        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(text = stringResource(R.string.onboarding_snooze_title), fontSize = 32.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Spacer(Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.onboarding_snooze_subtitle),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = SwipeBlue,
                textAlign = TextAlign.Center,
            )
        }

        Spacer(Modifier.height(24.dp))

        Box(modifier = Modifier.fillMaxWidth().height(320.dp), contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier.size(240.dp, 300.dp).graphicsLayer { translationY = 10.dp.toPx(); scaleX = 0.95f; scaleY = 0.95f },
                contentAlignment = Alignment.Center,
            ) {
                OnboardingMockCardBackground(topWhite = 0.25f, bottomWhite = 0.18f, modifier = Modifier.fillMaxSize())
                Text(text = "🖼️", fontSize = 50.sp, color = Color.White.copy(alpha = 0.2f))
            }
            SnoozeDemoCard()
        }

        Spacer(Modifier.height(24.dp))
        Text(
            text = stringResource(R.string.onboarding_snooze_body),
            fontSize = 14.sp,
            color = Color.Gray,
            textAlign = TextAlign.Center,
            lineHeight = 18.sp,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp),
        )

        Spacer(Modifier.weight(1f))

        GoldCapsuleButton(
            text = stringResource(R.string.onboarding_snooze_cta),
            onClick = onNext,
            modifier = Modifier.padding(start = 32.dp, end = 32.dp, bottom = 48.dp),
        )
    }
}

@Composable
private fun SnoozeDemoCard() {
    val scope = rememberCoroutineScope()
    val offsetX = remember { Animatable(0f) }
    val offsetY = remember { Animatable(0f) }
    var visible by remember { mutableStateOf(true) }
    var showLabel by remember { mutableStateOf(false) }
    var animateArrow by remember { mutableStateOf(false) }

    LaunchedEffect(visible) {
        animateArrow = false
        if (visible) {
            delay(150)
            animateArrow = true
        }
    }

    if (!visible) return

    val arrowOffset by animateFloatAsState(
        targetValue = if (animateArrow) -8f else 0f,
        animationSpec = infiniteRepeatable(tween(700, easing = LinearEasing), RepeatMode.Reverse),
        label = "snoozeArrowBounce",
    )

    Box(
        modifier = Modifier
            .size(240.dp, 300.dp)
            .graphicsLayer {
                translationX = offsetX.value
                translationY = offsetY.value
                rotationZ = offsetX.value / 20f
            }
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(OnboardingCardCornerRadius))
            .shadow(
                elevation = 15.dp,
                shape = androidx.compose.foundation.shape.RoundedCornerShape(OnboardingCardCornerRadius),
                ambientColor = OnboardingCardShadowColor,
                spotColor = OnboardingCardShadowColor,
            )
            .pointerInput(Unit) {
                detectDragGestures(
                    onDrag = { change, dragAmount ->
                        change.consume()
                        scope.launch {
                            offsetX.snapTo(offsetX.value + dragAmount.x)
                            offsetY.snapTo(offsetY.value + dragAmount.y)
                        }
                        showLabel = offsetY.value < SNOOZE_LABEL_THRESHOLD
                    },
                    onDragEnd = {
                        if (offsetY.value < SNOOZE_FLY_THRESHOLD) {
                            scope.launch {
                                offsetY.animateTo(SNOOZE_FLY_DISTANCE, spring(dampingRatio = 0.7f, stiffness = 260f))
                                visible = false
                                offsetX.snapTo(0f)
                                offsetY.snapTo(0f)
                                showLabel = false
                                delay(150)
                                visible = true
                            }
                        } else {
                            scope.launch {
                                val snapBack = spring<Float>(dampingRatio = Spring.DampingRatioMediumBouncy)
                                offsetX.animateTo(0f, snapBack)
                                offsetY.animateTo(0f, snapBack)
                            }
                            showLabel = false
                        }
                    },
                )
            },
    ) {
        OnboardingMockCardBackground(topWhite = 0.28f, bottomWhite = 0.20f, modifier = Modifier.fillMaxSize())
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(text = "🤔", fontSize = 64.sp)
            Spacer(Modifier.height(16.dp))
            Text(
                text = "⬆️",
                fontSize = 32.sp,
                modifier = Modifier.graphicsLayer { translationY = arrowOffset.dp.toPx() },
            )
        }
        if (showLabel) {
            Text(
                text = stringResource(com.swipy.core.designsystem.R.string.swipe_action_later),
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = SwipeBlue,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 24.dp)
                    .graphicsLayer { rotationZ = -15f }
                    .background(SwipeBlue.copy(alpha = 0.2f), CircleShape)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}
