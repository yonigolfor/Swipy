package com.swipy.feature.swipe

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.swipy.domain.model.PhotoItem

/**
 * Pure content — no gesture/offset handling here, that lives entirely in CardStackLayer's
 * graphicsLayer per android/CLAUDE.md "Gesture Engine & Card Stack Performance". [PhotoItem]
 * is built entirely from Compose-stable primitives (see its own doc comment), so this
 * composable is skippable via plain structural equality with no @Immutable annotation needed.
 */
@Composable
fun PhotoCardComposable(item: PhotoItem, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(24.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
    ) {
        if (item.isVideo) {
            // Full ExoPlayer/VideoPlayerPool wiring is a separate pass — see
            // android/CLAUDE.md "Video via Media3 ExoPlayer, pooled". A plain placeholder
            // beats a half-wired player for this pass.
            Text(
                text = "Video",
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.align(Alignment.Center),
            )
        } else {
            AsyncImage(
                model = item.uriString,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
