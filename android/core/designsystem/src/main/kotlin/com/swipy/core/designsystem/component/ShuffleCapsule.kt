package com.swipy.core.designsystem.component

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.theme.ShuffleAccentEnd
import com.swipy.core.designsystem.theme.ShuffleAccentStart

/**
 * Shuffle toggle + exit, sharing one glassmorphic surface — Compose port of iOS
 * `shuffleCapsule`/`shuffleToggleButton`/`exitShuffleButton` (SwipeStackView.swift:309-392).
 * Uses [CircleShape][androidx.compose.foundation.shape.CircleShape] as the container shape:
 * applied to a wide `Row`, Compose resolves that to a stadium/pill exactly like SwiftUI's
 * `Capsule()` (corner radius = min(width, height)/2 on all four corners).
 *
 * No material-icons-extended dependency (same reasoning as UndoFab) — "shuffle" and "exit"
 * glyphs are plain text/emoji, not vector icons.
 */
@Composable
fun ShuffleCapsule(
    isActive: Boolean,
    onToggle: () -> Unit,
    onExit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val rotation by animateFloatAsState(
        targetValue = if (isActive) 180f else 0f,
        animationSpec = spring(dampingRatio = 0.65f, stiffness = 210f),
        label = "shuffleIconRotation",
    )
    val borderBrush: Brush = if (isActive) {
        // Compose analogue of iOS's AngularGradient — a full sweep through the two accent
        // colors and back, so the border reads as a continuous loop with no seam.
        Brush.sweepGradient(listOf(ShuffleAccentStart, ShuffleAccentEnd, ShuffleAccentStart))
    } else {
        SolidColor(Color.White.copy(alpha = 0.12f))
    }
    val shadowColor = if (isActive) ShuffleAccentStart.copy(alpha = 0.5f) else Color.Black.copy(alpha = 0.18f)
    val toggleInteractionSource = remember { MutableInteractionSource() }
    val exitInteractionSource = remember { MutableInteractionSource() }

    GlassSurface(
        shape = CircleShape,
        modifier = modifier,
        borderBrush = borderBrush,
        borderWidth = if (isActive) 1.5.dp else 1.dp,
        shadowElevation = if (isActive) 14.dp else 10.dp,
        shadowColor = shadowColor,
    ) {
        Row(modifier = Modifier.padding(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clickable(
                        interactionSource = toggleInteractionSource,
                        indication = null,
                        onClick = onToggle,
                    )
                    .semantics { contentDescription = "Shuffle" },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "🔀",
                    fontSize = 19.sp,
                    modifier = Modifier.graphicsLayer { rotationZ = rotation },
                )
            }

            AnimatedVisibility(
                visible = isActive,
                enter = scaleIn(tween(220), initialScale = 0.4f),
                exit = scaleOut(tween(220), targetScale = 0.4f),
            ) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clickable(
                            interactionSource = exitInteractionSource,
                            indication = null,
                            onClick = onExit,
                        )
                        .semantics { contentDescription = "Exit shuffle" },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(text = "✕", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
            }
        }
    }
}
