package com.swipy.feature.reviewbin

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.theme.SwipeGreen
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val CelebrationEmerald = Color(0xFF00B380)
private val ConfettiBlue = Color(0xFF4D8CF2)
private val ConfettiPurple = Color(0xFF8C4DF2)
private val ConfettiPink = Color(0xFFF24D9E)
private val ConfettiOrange = Color(0xFFF2A64D)

/**
 * Full-screen "dopamine hit" overlay shown after Empty Trash succeeds — Compose port of iOS
 * TrashCelebrationView.swift. Hand-rolled confetti/animation, no Lottie or other third-party
 * animation dependency — matches iOS's own zero-third-party-dependency implementation and this
 * project's "zero third-party product dependencies" stance on both platforms.
 */
@Composable
fun TrashCelebrationOverlay(
    spaceSavedLabel: String,
    itemCount: Int,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val scale = remember { Animatable(0.3f) }
    val alpha = remember { Animatable(0f) }
    var particlesVisible by remember { mutableStateOf(false) }
    var dismissed by remember { mutableStateOf(false) }

    fun dismiss() {
        if (dismissed) return
        dismissed = true
        scope.launch {
            coroutineScope {
                launch { scale.animateTo(0.8f, tween(250)) }
                launch { alpha.animateTo(0f, tween(250)) }
            }
            onDismiss()
        }
    }

    LaunchedEffect(Unit) {
        coroutineScope {
            launch { scale.animateTo(1f, spring(dampingRatio = 0.62f, stiffness = 210f)) }
            launch { alpha.animateTo(1f, spring(dampingRatio = 0.62f, stiffness = 210f)) }
        }
        delay(200)
        particlesVisible = true
        delay(4800)
        dismiss()
    }

    Box(
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.55f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = { dismiss() },
            ),
        contentAlignment = Alignment.Center,
    ) {
        ConfettiField(visible = particlesVisible)

        Column(
            modifier = Modifier
                .graphicsLayer {
                    scaleX = scale.value
                    scaleY = scale.value
                    this.alpha = alpha.value
                }
                .padding(horizontal = 32.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(MaterialTheme.colorScheme.surface)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = {}, // absorb taps so tapping the card itself doesn't dismiss
                )
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(text = "🎉", fontSize = 62.sp)
            Spacer(Modifier.height(20.dp))
            Text(
                text = "Space Reclaimed! 🚀",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(8.dp))
            Text(text = "You freed up", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text = spaceSavedLabel,
                style = TextStyle(
                    fontSize = 52.sp,
                    fontWeight = FontWeight.Black,
                    brush = Brush.linearGradient(listOf(SwipeGreen, CelebrationEmerald)),
                ),
            )
            Text(
                text = "by deleting $itemCount item${if (itemCount == 1) "" else "s"}",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(24.dp))
            Button(
                onClick = { dismiss() },
                colors = ButtonDefaults.buttonColors(containerColor = SwipeGreen),
                shape = CircleShape,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(text = "Awesome! 💪", color = Color.White, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

private data class ConfettiSpec(val angleDeg: Double, val distanceDp: Float, val sizeDp: Float, val color: Color)

private val confettiSpecs: List<ConfettiSpec> = List(20) { i ->
    val colors = listOf(SwipeGreen, CelebrationEmerald, ConfettiBlue, ConfettiPurple, ConfettiPink, ConfettiOrange)
    ConfettiSpec(
        angleDeg = i * 18.0,
        distanceDp = (100 + (i * 37) % 121).toFloat(),
        sizeDp = (6 + (i * 5) % 9).toFloat(),
        color = colors[i % colors.size],
    )
}

@Composable
private fun ConfettiField(visible: Boolean) {
    confettiSpecs.forEach { p ->
        val rad = Math.toRadians(p.angleDeg)
        val offsetX by animateFloatAsState(
            targetValue = if (visible) (cos(rad) * p.distanceDp).toFloat() else 0f,
            animationSpec = tween(900),
            label = "confettiX",
        )
        val offsetY by animateFloatAsState(
            targetValue = if (visible) (sin(rad) * p.distanceDp).toFloat() else 0f,
            animationSpec = tween(900),
            label = "confettiY",
        )
        val particleAlpha by animateFloatAsState(
            targetValue = if (visible) 0f else 1f,
            animationSpec = tween(900),
            label = "confettiAlpha",
        )
        Box(
            modifier = Modifier
                .graphicsLayer { translationX = offsetX.dp.toPx(); translationY = offsetY.dp.toPx(); this.alpha = particleAlpha }
                .width(p.sizeDp.dp)
                .height(p.sizeDp.dp)
                .clip(CircleShape)
                .background(p.color),
        )
    }
}
