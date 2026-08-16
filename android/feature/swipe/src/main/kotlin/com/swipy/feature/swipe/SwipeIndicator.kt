package com.swipy.feature.swipe

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.R
import com.swipy.core.designsystem.theme.SwipeBlue
import com.swipy.core.designsystem.theme.SwipeGreen
import com.swipy.core.designsystem.theme.SwipeRed
import com.swipy.domain.model.SwipeAction

/**
 * Pure content — no offset/opacity logic here, that lives entirely in CardStackLayer's
 * graphicsLayer, mirroring iOS's SwipeIndicator.swift/CardStackView split exactly (see
 * android/CLAUDE.md "Gesture Engine & Card Stack Performance": reading a per-frame drag value
 * inside this composable's own body would force a recomposition on every drag frame — [direction]
 * is expected to change only rarely, at threshold crossings, not on every `.onChanged` frame).
 *
 * [direction] null (or [SwipeAction.Undo], which has no swipe-gesture meaning) renders nothing.
 */
@Composable
fun SwipeIndicator(direction: SwipeAction?, modifier: Modifier = Modifier) {
    if (direction == null || direction == SwipeAction.Undo) return

    // Absolute (not Start/End) alignment — a swipe is a physical, spatial gesture, not a
    // text-flow concept: dragging right must always show Keep on the physical right edge
    // regardless of layout direction. Alignment.CenterStart/CenterEnd are layout-direction-aware
    // and silently invert under RTL (a Hebrew system locale), which is exactly the bug this
    // fixes — see android/TODO.md item 3 and android/CLAUDE.md "Layout Direction".
    val alignment = when (direction) {
        SwipeAction.Delete -> AbsoluteAlignment.CenterLeft
        SwipeAction.Keep -> AbsoluteAlignment.CenterRight
        SwipeAction.Snooze -> Alignment.TopCenter
        SwipeAction.Undo -> Alignment.Center
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(
                start = 40.dp,
                end = 40.dp,
                top = if (direction == SwipeAction.Snooze) 60.dp else 0.dp,
            ),
        contentAlignment = alignment,
    ) {
        when (direction) {
            SwipeAction.Delete -> IndicatorCapsule(
                glyph = "🗑",
                label = stringResource(R.string.swipe_action_delete),
                color = SwipeRed,
            )
            SwipeAction.Keep -> IndicatorCapsule(
                glyph = "✓",
                label = stringResource(R.string.swipe_action_keep),
                color = SwipeGreen,
            )
            SwipeAction.Snooze -> IndicatorCapsule(
                glyph = "🤷",
                label = stringResource(R.string.swipe_action_later),
                color = SwipeBlue,
            )
            SwipeAction.Undo -> Unit
        }
    }
}

@Composable
private fun IndicatorCapsule(glyph: String, label: String, color: Color) {
    Row(
        modifier = Modifier
            .shadow(
                elevation = 10.dp,
                shape = CircleShape,
                ambientColor = color.copy(alpha = 0.5f),
                spotColor = color.copy(alpha = 0.5f),
            )
            .background(
                brush = Brush.linearGradient(listOf(color, color.copy(alpha = 0.82f))),
                shape = CircleShape,
            )
            .padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = glyph, fontSize = 22.sp, color = Color.White)
        Text(text = label, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
    }
}
