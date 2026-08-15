package com.swipy.core.designsystem.component

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.sin

/**
 * Undo FAB — the Compose port of iOS `undoButton` (SwipeStackView.swift): a 56dp glass circle
 * with a curved-arrow "undo" glyph, dimmed to 70% and disabled when there's nothing to undo.
 *
 * No androidx material-icons-extended dependency in this project (only material-icons-core is
 * on the classpath, which doesn't include an Undo glyph) — drawn as a small custom Canvas path
 * instead of pulling in a new dependency for one icon.
 */
@Composable
fun UndoFab(
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val alpha by animateFloatAsState(
        targetValue = if (enabled) 1f else 0.7f,
        animationSpec = spring(dampingRatio = 0.8f, stiffness = 380f),
        label = "undoFabAlpha",
    )
    val interactionSource = remember { MutableInteractionSource() }

    GlassSurface(
        shape = CircleShape,
        modifier = modifier
            .size(56.dp)
            .graphicsLayer { this.alpha = alpha }
            .clickable(
                enabled = enabled,
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .semantics { contentDescription = "Undo" },
    ) {
        Box(
            modifier = Modifier
                .size(20.dp)
                .align(Alignment.Center)
                .drawBehind { drawUndoGlyph(color = Color.White, strokeWidthPx = 2.dp.toPx()) },
        )
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawUndoGlyph(color: Color, strokeWidthPx: Float) {
    val radius = (size.minDimension - strokeWidthPx) / 2f
    val center = Offset(size.width / 2f, size.height / 2f)
    val arcTopLeft = Offset(center.x - radius, center.y - radius)

    // Arc sweeps clockwise, leaving a gap where the arrowhead sits (mirrors the open curve
    // of SF Symbol's arrow.uturn.backward).
    val startAngleDeg = 20f
    val sweepAngleDeg = 280f
    drawArc(
        color = color,
        startAngle = startAngleDeg,
        sweepAngle = sweepAngleDeg,
        useCenter = false,
        style = Stroke(width = strokeWidthPx, cap = StrokeCap.Round),
        topLeft = arcTopLeft,
        size = Size(radius * 2f, radius * 2f),
    )

    // Arrowhead at the arc's start point, pointing back along the arc's tangent.
    val startRad = Math.toRadians(startAngleDeg.toDouble())
    val tip = Offset(
        x = center.x + radius * cos(startRad).toFloat(),
        y = center.y + radius * sin(startRad).toFloat(),
    )
    val headLength = strokeWidthPx * 1.8f
    val tangentRad = startRad - Math.PI / 2.0
    val back = Offset(
        x = tip.x - headLength * cos(tangentRad).toFloat(),
        y = tip.y - headLength * sin(tangentRad).toFloat(),
    )
    val normalRad = tangentRad + Math.PI / 2.0
    val perp = Offset(
        x = (headLength * 0.5f) * cos(normalRad).toFloat(),
        y = (headLength * 0.5f) * sin(normalRad).toFloat(),
    )
    val arrowhead = Path().apply {
        moveTo(tip.x, tip.y)
        lineTo(back.x + perp.x, back.y + perp.y)
        lineTo(back.x - perp.x, back.y - perp.y)
        close()
    }
    drawPath(arrowhead, color = color)
}
