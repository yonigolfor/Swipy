package com.swipy.feature.swipe

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.util.Size
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.swipy.domain.model.PhotoItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 20dp corners + a soft `black 15%` elevation shadow — mirrors iOS's `cardShadow()`
 * (`.shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)`, View+Extensions.swift:12-14).
 * Compose's `Modifier.shadow` has no direct x/y offset parameter the way SwiftUI's does — its
 * elevation shadow is already visually biased downward by convention, which reads close enough
 * to iOS's y:5 without a custom Canvas-drawn shadow; a known simplification, not a literal port. */
private val CardCornerRadius = 20.dp
private val CardShadowColor = Color.Black.copy(alpha = 0.15f)

/** Blurred-background-fill + sharp-foreground-fit composite — mirrors iOS's `imageContentView`
 * (PhotoCardView.swift:471-488): a letterbox technique that fills a card whose aspect ratio
 * doesn't match the media's, without hard black bars or cropping content away. */
private val LetterboxBlurRadius = 25.dp
private const val LetterboxBackgroundScale = 1.1f

/** The Android port of iOS's `PhotoCardView.globalMute` static var — a single mute flag shared
 * across every video card, not per-card state, so muting one video keeps every other video
 * card muted too when it becomes the top card. Lives here since only VideoCardContent reads it. */
private object GlobalVideoMuteState {
    var isMuted by mutableStateOf(true)
}

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
            .shadow(
                elevation = 10.dp,
                shape = RoundedCornerShape(CardCornerRadius),
                ambientColor = CardShadowColor,
                spotColor = CardShadowColor,
            )
            .clip(RoundedCornerShape(CardCornerRadius))
            .background(MaterialTheme.colorScheme.surfaceVariant),
    ) {
        if (item.isVideo) {
            VideoCardContent(item = item, isActive = isTop, modifier = Modifier.fillMaxSize())
        } else {
            // Photos always get the letterbox composite, regardless of orientation — mirrors
            // iOS, which applies imageContentView() unconditionally (only the video branch
            // there special-cases portrait vs landscape).
            LetterboxAsyncImage(model = item.uriString, modifier = Modifier.fillMaxSize())
        }

        // Top-left: mute toggle (videos only) + screenshot/recording badge — matches iOS's
        // speaker icon being the leading element of its own top-row HStack
        // (PhotoCardView.swift:209-216), grouped here with the corner badge rather than kept
        // as two separately-positioned overlays the way iOS has them (iOS's screenshot/
        // recording badge is a second, independently-anchored top-left overlay that can
        // visually collide with the speaker icon for screen recordings specifically — this
        // single shared Row sidesteps that instead of reproducing it).
        Row(
            modifier = Modifier.align(Alignment.TopStart).padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (item.isVideo) {
                MuteIconBadge(
                    isMuted = GlobalVideoMuteState.isMuted,
                    onToggle = { GlobalVideoMuteState.isMuted = !GlobalVideoMuteState.isMuted },
                )
            }
            if (item.isScreenshot || item.isScreenRecording) {
                Text(
                    text = if (item.isScreenshot) {
                        stringResource(R.string.swipe_badge_screenshot)
                    } else {
                        stringResource(R.string.swipe_badge_recording)
                    },
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier
                        .background(Color(0xFF2196F3).copy(alpha = 0.8f), CircleShape)
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
        }

        // Top-right: file size pill + native share — matches iOS's fileSize/share being the
        // trailing elements of the same top-row HStack (PhotoCardView.swift:243-274). Share
        // only wired live on the top card (matches iOS's `onShare: isTop ? { ... } : nil`) —
        // background cards are fully covered by the top card so this is unreachable by touch
        // regardless, but gating the action itself (not just the tap target) keeps the intent
        // explicit rather than relying on that geometry coincidence.
        Row(
            modifier = Modifier.align(Alignment.TopEnd).padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (item.fileSizeBytes > 0) {
                Text(
                    text = formatFileSize(item.fileSizeBytes),
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .background(Color.Black.copy(alpha = 0.6f), CircleShape)
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
            ShareIconButton(enabled = isTop, item = item)
        }
    }
}

@Composable
private fun ShareIconButton(enabled: Boolean, item: PhotoItem) {
    val context = LocalContext.current
    // Resolved here, not inside shareMediaItem() — stringResource() requires a @Composable
    // context, and that function is a plain click-handler callback, not one.
    val shareCaption = stringResource(R.string.swipe_share_caption)
    Box(
        modifier = Modifier
            .size(28.dp)
            .background(Color.Black.copy(alpha = 0.6f), CircleShape)
            .clickable(
                enabled = enabled,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = { shareMediaItem(context, item, shareCaption) },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = "📤", fontSize = 13.sp) // 📤 outbox tray
    }
}

/** Native Share Sheet for one media item — a content:// MediaStore Uri, granted read
 * permission for the receiving app via FLAG_GRANT_READ_URI_PERMISSION (no FileProvider needed;
 * MediaStore Uris are already content:// and accessible cross-app once that flag is set).
 * [caption] is the Android analogue of iOS's `UIActivityViewController(activityItems:
 * [imageProvider, caption])` — apps that support EXTRA_TEXT alongside EXTRA_STREAM (WhatsApp
 * included) render it as the shared image/video's accompanying message text. */
private fun shareMediaItem(context: Context, item: PhotoItem, caption: String) {
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = if (item.isVideo) "video/*" else "image/*"
        putExtra(Intent.EXTRA_STREAM, Uri.parse(item.uriString))
        putExtra(Intent.EXTRA_TEXT, caption)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(sendIntent, null))
}

@Composable
private fun MuteIconBadge(isMuted: Boolean, onToggle: () -> Unit) {
    Box(
        modifier = Modifier
            .size(28.dp)
            .background(Color.Black.copy(alpha = 0.6f), CircleShape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onToggle,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = if (isMuted) "🔇" else "🔊", fontSize = 13.sp)
    }
}

/** Coil-backed letterbox composite for a static image — see the class-level doc above. */
@Composable
private fun LetterboxAsyncImage(model: Any, modifier: Modifier = Modifier) {
    Box(modifier) {
        AsyncImage(
            model = model,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxSize()
                .blur(LetterboxBlurRadius)
                .scale(LetterboxBackgroundScale),
        )
        AsyncImage(
            model = model,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/** Bitmap-backed equivalent of [LetterboxAsyncImage] — used for the video thumbnail-first
 * placeholder, where the frame is already a decoded Bitmap (from ContentResolver.loadThumbnail),
 * not something Coil can load directly (this project has no coil-video decoder wired — see
 * android/CLAUDE.md's Review Bin section for the same documented gap). */
@Composable
private fun LetterboxBitmap(bitmap: Bitmap, modifier: Modifier = Modifier) {
    val imageBitmap = remember(bitmap) { bitmap.asImageBitmap() }
    Box(modifier) {
        Image(
            bitmap = imageBitmap,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxSize()
                .blur(LetterboxBlurRadius)
                .scale(LetterboxBackgroundScale),
        )
        Image(
            bitmap = imageBitmap,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/**
 * See android/CLAUDE.md "Video via Media3 ExoPlayer, pooled" — VideoPlayerPool hands back a
 * reused player keyed by uri; this composable only owns the play/pause lifecycle for whichever
 * uri it's currently showing, never releases the player itself (drainAll() is reserved for
 * right before a delete/trash request, not ordinary recomposition/navigation).
 *
 * Thumbnail-first: a Bitmap decoded via `ContentResolver.loadThumbnail` (the API 29+ platform
 * primitive that handles video-frame extraction natively — no coil-video dependency needed,
 * unlike Coil's own AsyncImage) is shown immediately; the ExoPlayer surface cross-fades in only
 * once it reports its first rendered frame, mirroring iOS PhotoCardView's thumbnail-then-player
 * fade dance (PhotoCardView.swift:78-140). Landscape video gets the same letterbox treatment as
 * photos for both the thumbnail and (implicitly, via RESIZE_MODE_FIT) the live player; portrait
 * video just fills/crops directly since it already matches the 9:16 card closely.
 *
 * Mute state is [GlobalVideoMuteState] — NOT per-composable — matching the iOS port note above.
 */
@Composable
private fun VideoCardContent(item: PhotoItem, isActive: Boolean, modifier: Modifier = Modifier) {
    val pool = rememberVideoPlayerPool()
    val player = remember(item.uriString) { pool.playerFor(item.uriString) }
    val context = LocalContext.current
    val isLandscape = item.width > item.height

    var thumbnail by remember(item.uriString) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(item.uriString) {
        thumbnail = withContext(Dispatchers.IO) {
            runCatching {
                context.contentResolver.loadThumbnail(Uri.parse(item.uriString), Size(600, 800), null)
            }.getOrNull()
        }
    }

    var isPlayerReady by remember(item.uriString) { mutableStateOf(false) }
    DisposableEffect(player) {
        // Fast path: a pooled player reused after a tab switch may already be rendering —
        // mirrors iOS's own "already ready" check on PHAsset player reuse.
        if (player.playbackState == Player.STATE_READY) isPlayerReady = true
        val listener = object : Player.Listener {
            override fun onRenderedFirstFrame() {
                isPlayerReady = true
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    val playerAlpha by animateFloatAsState(targetValue = if (isPlayerReady) 1f else 0f, label = "videoPlayerAlpha")

    Box(modifier = modifier) {
        thumbnail?.let { bitmap ->
            if (isLandscape) {
                LetterboxBitmap(bitmap = bitmap, modifier = Modifier.fillMaxSize())
            } else {
                Image(
                    bitmap = remember(bitmap) { bitmap.asImageBitmap() },
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        AndroidView(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = playerAlpha },
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    resizeMode = if (isLandscape) {
                        AspectRatioFrameLayout.RESIZE_MODE_FIT
                    } else {
                        AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    }
                }
            },
            update = { view -> view.player = player },
        )
    }

    DisposableEffect(player, isActive, GlobalVideoMuteState.isMuted) {
        if (isActive) {
            player.volume = if (GlobalVideoMuteState.isMuted) 0f else 1f
            player.repeatMode = Player.REPEAT_MODE_ONE
            player.play()
        } else {
            player.pause()
        }
        onDispose { player.pause() }
    }
}
