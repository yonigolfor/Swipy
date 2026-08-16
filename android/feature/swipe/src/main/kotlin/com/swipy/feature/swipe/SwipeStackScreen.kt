package com.swipy.feature.swipe

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.swipy.core.designsystem.component.SessionSavingsBar
import com.swipy.core.designsystem.component.ShuffleBadge
import com.swipy.core.designsystem.component.ShuffleCapsule
import com.swipy.core.designsystem.component.UndoFab
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val monthYearFormatter = DateTimeFormatter.ofPattern("MMMM yyyy")

/**
 * Screen chrome — the Compose analogue of iOS SwipeStackView. Card stack, Session Savings Bar,
 * Undo FAB, and (Milestone 1) the Shuffle capsule + mode badge + fly-out/land-in transition —
 * the direct port of `performShuffleTransition`/`.onChange(of: shuffleBatchID)`
 * (SwipeStackView.swift:686-707, 260-279).
 */
@Composable
fun SwipeStackScreen(
    onNavigateToReviewBin: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: PhotoStackViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val screenHeightPx = with(density) { LocalConfiguration.current.screenHeightDp.dp.toPx() }

    // Card-area transform driving the shuffle fly-out/land-in — owned locally, never hoisted
    // into PhotoStackUiState, matching this codebase's "no per-frame/transient gesture-adjacent
    // state in StateFlow" rule (this isn't a per-frame gesture value, but the same "render-only,
    // local" discipline applies to any purely-visual transient transform).
    val cardAreaOffsetY = remember { Animatable(0f) }
    val cardAreaOpacity = remember { Animatable(1f) }
    val cardAreaScale = remember { Animatable(1f) }
    var isTransitioning by remember { mutableStateOf(false) }
    var indicatorText by remember { mutableStateOf<String?>(null) }
    // Resolved here, not inline in the LaunchedEffect below — stringResource() requires a
    // @Composable context, and viewModel.effects.collect {}'s lambda isn't one.
    val shuffleLandedHomeLabel = stringResource(R.string.swipe_shuffle_landed_home)

    /** Fly-out → dispatch intent → parked off-screen, mirrors performShuffleTransition. */
    fun flyOutThenDispatch(intent: PhotoStackIntent) {
        if (isTransitioning) return
        isTransitioning = true
        scope.launch {
            coroutineScope {
                launch { cardAreaOffsetY.animateTo(-screenHeightPx * 0.65f, tween(220, easing = FastOutLinearInEasing)) }
                launch { cardAreaOpacity.animateTo(0f, tween(220, easing = FastOutLinearInEasing)) }
                launch { cardAreaScale.animateTo(0.82f, tween(220, easing = FastOutLinearInEasing)) }
            }
            delay(270)
            cardAreaOffsetY.snapTo(with(density) { 55.dp.toPx() })
            cardAreaScale.snapTo(0.85f)
            viewModel.onIntent(intent)
        }
    }

    LaunchedEffect(Unit) {
        viewModel.effects.collect { effect ->
            when (effect) {
                PhotoStackEffect.NothingToUndo -> Unit
                is PhotoStackEffect.ShuffleLanded -> {
                    coroutineScope {
                        launch { cardAreaOffsetY.animateTo(0f, spring(dampingRatio = 0.72f, stiffness = 130f)) }
                        launch { cardAreaOpacity.animateTo(1f, spring(dampingRatio = 0.72f, stiffness = 130f)) }
                        launch { cardAreaScale.animateTo(1f, spring(dampingRatio = 0.72f, stiffness = 130f)) }
                    }
                    isTransitioning = false
                    indicatorText = effect.landedAtEpochSeconds
                        ?.let { seconds -> monthYearFormatter.format(Instant.ofEpochSecond(seconds).atZone(ZoneId.systemDefault())) }
                        ?: shuffleLandedHomeLabel
                    delay(2200)
                    indicatorText = null
                }
            }
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    translationY = cardAreaOffsetY.value
                    alpha = cardAreaOpacity.value
                    scaleX = cardAreaScale.value
                    scaleY = cardAreaScale.value
                },
        ) {
            when {
                uiState.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))

                uiState.stack.isEmpty() -> Text(
                    text = stringResource(R.string.swipe_empty_state),
                    modifier = Modifier.align(Alignment.Center),
                    style = MaterialTheme.typography.titleMedium,
                )

                else -> CardStackLayer(
                    items = uiState.stack,
                    onSwipeCommitted = { item, action ->
                        viewModel.onIntent(PhotoStackIntent.Swipe(item, action))
                    },
                    modifier = Modifier.padding(top = 100.dp),
                )
            }
        }

        // Session Savings Bar — floats as a direct Box sibling (not nested inside the card
        // layer) so its z-order beats the cards, matching SwipeStackView.swift's ZStack layering.
        SessionSavingsBar(
            sessionSpaceSavedMB = uiState.sessionSpaceSavedMB,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .shadow(
                    elevation = 12.dp,
                    shape = RoundedCornerShape(20.dp),
                    ambientColor = Color.Black.copy(alpha = 0.18f),
                    spotColor = Color.Black.copy(alpha = 0.18f),
                )
                .background(color = MaterialTheme.colorScheme.surface, shape = RoundedCornerShape(20.dp)),
        )

        AnimatedVisibility(
            visible = uiState.isShuffleModeActive,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 96.dp),
            enter = slideInVertically(tween(300)) { -it } + fadeIn(tween(300)),
            exit = slideOutVertically(tween(220)) { -it } + fadeOut(tween(220)),
        ) {
            ShuffleBadge(
                label = stringResource(R.string.swipe_shuffle_mode_label),
                onDismiss = { flyOutThenDispatch(PhotoStackIntent.DeactivateShuffle) },
            )
        }

        indicatorText?.let { text ->
            Text(
                text = text,
                color = Color.White,
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier
                    .align(Alignment.Center)
                    .background(color = Color.Black.copy(alpha = 0.35f), shape = RoundedCornerShape(18.dp))
                    .padding(horizontal = 24.dp, vertical = 14.dp),
            )
        }

        TextButton(
            onClick = onNavigateToReviewBin,
            modifier = Modifier.align(Alignment.TopEnd).padding(top = 96.dp, end = 8.dp),
        ) {
            Text(stringResource(R.string.swipe_review_bin_button, uiState.reviewBinCount))
        }

        // FAB column — Shuffle capsule above Undo, matching the iOS FAB row's VStack order.
        Column(
            modifier = Modifier.align(Alignment.BottomStart).padding(start = 24.dp, bottom = 32.dp),
        ) {
            ShuffleCapsule(
                isActive = uiState.isShuffleModeActive,
                onToggle = { flyOutThenDispatch(PhotoStackIntent.ActivateShuffle) },
                onExit = { flyOutThenDispatch(PhotoStackIntent.DeactivateShuffle) },
                modifier = Modifier.padding(bottom = 24.dp),
            )
            UndoFab(
                enabled = uiState.canUndo,
                onClick = { viewModel.onIntent(PhotoStackIntent.Undo) },
            )
        }
    }
}
