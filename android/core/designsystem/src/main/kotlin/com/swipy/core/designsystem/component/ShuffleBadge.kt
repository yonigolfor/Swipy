package com.swipy.core.designsystem.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.theme.ShuffleAccentEnd
import com.swipy.core.designsystem.theme.ShuffleAccentStart

/**
 * Small top-floating pill announcing shuffle mode — Compose port of iOS `shuffleBadge`
 * (SwipeStackView.swift:429-463). Unlike [ShuffleCapsule]/[GlassSurface]'s neutral glass tint,
 * this is a solid tinted gradient (leading→trailing, matching the iOS spec exactly), so it
 * doesn't reuse [GlassSurface] — a deliberately different visual per the source spec.
 */
@Composable
fun ShuffleBadge(
    label: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }

    Row(
        modifier = modifier
            .shadow(
                elevation = 10.dp,
                shape = CircleShape,
                ambientColor = Color.Black.copy(alpha = 0.25f),
                spotColor = Color.Black.copy(alpha = 0.25f),
            )
            .background(
                brush = Brush.linearGradient(
                    listOf(ShuffleAccentStart.copy(alpha = 0.55f), ShuffleAccentEnd.copy(alpha = 0.45f)),
                ),
                shape = CircleShape,
            )
            .padding(horizontal = 14.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(text = "🔀", fontSize = 11.sp)
        Text(text = label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        Box(
            modifier = Modifier
                .size(18.dp)
                .clickable(interactionSource = interactionSource, indication = null, onClick = onDismiss),
            contentAlignment = Alignment.Center,
        ) {
            Text(text = "✕", fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f))
        }
    }
}
