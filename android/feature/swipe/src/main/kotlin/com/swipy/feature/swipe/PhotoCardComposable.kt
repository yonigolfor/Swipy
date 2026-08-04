package com.swipy.feature.swipe

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.swipy.domain.model.PhotoItem

/**
 * Pure content — no gesture/offset handling here, that lives entirely in CardStackLayer's
 * graphicsLayer per android/CLAUDE.md "Gesture Engine & Card Stack Performance". [PhotoItem]
 * is built entirely from Compose-stable primitives (see its own doc comment), so this
 * composable is skippable via plain structural equality with no @Immutable annotation needed.
 *
 * [isTop] gates video playback only (a background card's video stays paused on its first
 * frame) — it's not read by anything gesture-related, so passing it doesn't reintroduce a
 * per-frame recomposition dependency.
 */
@Composable
fun PhotoCardComposable(item: PhotoItem, isTop: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(24.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
    ) {
        if (item.isVideo) {
            VideoCardContent(item = item, isActive = isTop, modifier = Modifier.fillMaxSize())
        } else {
            AsyncImage(
                model = item.uriString,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/**
 * See android/CLAUDE.md "Video via Media3 ExoPlayer, pooled" — VideoPlayerPool hands back a
 * reused player keyed by uri; this composable only owns the play/pause lifecycle for whichever
 * uri it's currently showing, never releases the player itself (drainAll() is reserved for
 * right before a delete/trash request, not ordinary recomposition/navigation).
 *
 * Muted by default — a deliberate simplification, not a full port of iOS's AudioSessionManager
 * mixing behavior (background-audio-aware ducking), which is out of scope for this pass.
 */
@Composable
private fun VideoCardContent(item: PhotoItem, isActive: Boolean, modifier: Modifier = Modifier) {
    val pool = rememberVideoPlayerPool()
    val player = remember(item.uriString) { pool.playerFor(item.uriString) }

    AndroidView(
        modifier = modifier,
        factory = { context ->
            PlayerView(context).apply {
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            }
        },
        update = { view -> view.player = player },
    )

    DisposableEffect(player, isActive) {
        if (isActive) {
            player.volume = 0f
            player.repeatMode = Player.REPEAT_MODE_ONE
            player.play()
        } else {
            player.pause()
        }
        onDispose { player.pause() }
    }
}
