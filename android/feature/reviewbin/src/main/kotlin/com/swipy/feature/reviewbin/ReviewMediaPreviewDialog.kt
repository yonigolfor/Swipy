package com.swipy.feature.reviewbin

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.swipy.domain.model.PhotoItem

/**
 * Full-screen single-item viewer — Compose port of iOS FullScreenMediaView (image branch;
 * the progressive-thumbnail-then-upgrade seeding described in root CLAUDE.md is skipped here
 * since Coil's own memory/disk cache already makes the grid-to-preview transition near-instant
 * for this screen's small thumbnails, unlike the swipe stack's full-resolution card images).
 *
 * A plain full-screen [Dialog] (covers the whole window, floats above the host Activity
 * automatically) rather than a Compose Navigation destination with a shared-element transition
 * — the latter (mentioned as a future direction in android/CLAUDE.md's Navigation section)
 * needs SharedTransitionLayout (API 34+/Compose 1.7+) and is scoped out of this milestone.
 *
 * Uses its own freshly-created ExoPlayer instance, released in onDispose — NOT drawn from
 * :data:mediastore's pooled VideoPlayerPool (that pool is scoped to the swipe card stack).
 * This mirrors iOS's own FullScreenMediaView, which likewise creates a standalone AVPlayer
 * rather than reusing anything from the swipe screen's playback infrastructure.
 */
@Composable
fun ReviewMediaPreviewDialog(
    item: PhotoItem,
    onDismiss: () -> Unit,
    onRestore: () -> Unit,
) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
            if (item.isVideo) {
                VideoPreview(uriString = item.uriString, modifier = Modifier.fillMaxSize())
            } else {
                AsyncImage(
                    model = item.uriString,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            }

            Row(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                GlassIconButton(glyph = "✕", onClick = onDismiss)
                RestoreCapsule(onClick = onRestore)
            }
        }
    }
}

@Composable
private fun VideoPreview(uriString: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val exoPlayer = remember {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(Uri.parse(uriString)))
            prepare()
            playWhenReady = true
        }
    }
    DisposableEffect(Unit) {
        onDispose { exoPlayer.release() }
    }
    AndroidView(
        factory = { PlayerView(it).apply { player = exoPlayer; useController = true } },
        modifier = modifier,
    )
}

@Composable
private fun GlassIconButton(glyph: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .background(color = Color.White.copy(alpha = 0.18f), shape = CircleShape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .padding(12.dp),
    ) {
        Text(text = glyph, color = Color.White, fontSize = 18.sp)
    }
}

@Composable
private fun RestoreCapsule(onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .background(color = Color.White.copy(alpha = 0.25f), shape = CircleShape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = "↺", color = Color.White, fontSize = 16.sp)
        Text(text = "Restore", color = Color.White, fontWeight = FontWeight.SemiBold)
    }
}
