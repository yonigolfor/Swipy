package com.swipy.core.designsystem.component

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Shared "frosted glass" surface — the Compose analogue of iOS's `.ultraThinMaterial` fill
 * used by both the FAB row's Undo button and (Phase 2) the Shuffle capsule, so they never
 * each paint their own surface (avoids blur-on-blur, matching the iOS shuffleCapsule comment).
 *
 * Deliberate simplification: this is a translucent tint + gradient sheen + border, NOT a real
 * backdrop blur of the content behind it. True cross-content blur on Android needs either
 * Window.setBackgroundBlurRadius (whole-window, API 31+, not per-composable) or a third-party
 * layer-capture library (e.g. Haze) — both rejected here per the "zero third-party product
 * dependencies" stance in android/CLAUDE.md. Revisit only if a real blur is proven necessary,
 * not preemptively.
 */
@Composable
fun GlassSurface(
    shape: Shape,
    modifier: Modifier = Modifier,
    tint: Color = Color.White.copy(alpha = 0.14f),
    borderBrush: Brush = SolidColor(Color.White.copy(alpha = 0.12f)),
    borderWidth: Dp = 1.dp,
    shadowElevation: Dp = 10.dp,
    shadowColor: Color = Color.Black.copy(alpha = 0.18f),
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .shadow(
                elevation = shadowElevation,
                shape = shape,
                ambientColor = shadowColor,
                spotColor = shadowColor,
            )
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(Color.White.copy(alpha = 0.20f), Color.White.copy(alpha = 0.05f)),
                ),
                shape = shape,
            )
            .background(color = tint, shape = shape)
            .border(width = borderWidth, brush = borderBrush, shape = shape),
        content = content,
    )
}
