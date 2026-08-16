package com.swipy.feature.reviewbin

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.swipy.core.designsystem.haptics.rememberHapticManager
import com.swipy.core.designsystem.theme.SwipeRed
import com.swipy.domain.model.PhotoItem

/**
 * Screen chrome — the Compose analogue of iOS ReviewBinView: 3-column 4:3 grid, tap-to-preview
 * (full-screen viewer with an explicit Restore button — no longer restore-on-tap), pending/
 * lifetime savings header, Empty Trash -> native MediaStore confirmation -> Trash Celebration.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReviewBinScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: ReviewBinViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val hapticManager = rememberHapticManager()
    var celebration by remember { mutableStateOf<CelebrationData?>(null) }

    val deleteConfirmationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            viewModel.onIntent(ReviewBinIntent.ConfirmEmptyTrash)
        }
    }

    LaunchedEffect(Unit) {
        viewModel.effects.collect { effect ->
            when (effect) {
                is ReviewBinEffect.LaunchDeleteConfirmation -> deleteConfirmationLauncher.launch(
                    IntentSenderRequest.Builder(effect.pendingIntent.intentSender).build(),
                )
                is ReviewBinEffect.EmptyTrashCompleted -> {
                    // Triple-heavy at full intensity (HAPTICS.md: "the strongest feedback in
                    // the app, matching the finality of permanent deletion").
                    hapticManager.emptyTrashBurst()
                    celebration = CelebrationData(effect.spaceSavedBytes, effect.itemCount)
                }
            }
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.reviewbin_top_bar_title)) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text(stringResource(R.string.reviewbin_back_button)) }
                    },
                    actions = {
                        if (uiState.items.isNotEmpty()) {
                            TextButton(onClick = { viewModel.onIntent(ReviewBinIntent.RequestEmptyTrash) }) {
                                Text(stringResource(R.string.reviewbin_empty_trash_action), color = SwipeRed)
                            }
                        }
                    },
                )
            },
        ) { padding ->
            Box(modifier = Modifier.fillMaxSize().padding(padding)) {
                when {
                    uiState.isLoading -> CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                    )

                    uiState.items.isEmpty() -> LifetimeSavingsHeader(
                        lifetimeSpaceSavedBytes = uiState.lifetimeSpaceSaved,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .fillMaxWidth(),
                    )

                    else -> LazyVerticalGrid(
                        columns = GridCells.Fixed(3),
                        contentPadding = PaddingValues(bottom = 16.dp),
                    ) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            PendingSummaryHeader(
                                spaceSavedBytes = uiState.totalSpaceSaved,
                                itemCount = uiState.items.size,
                            )
                        }
                        items(uiState.items, key = { it.id }) { item ->
                            ReviewGridCell(
                                item = item,
                                onTap = { viewModel.onIntent(ReviewBinIntent.SelectItem(item)) },
                                onLongPressRestore = { viewModel.onIntent(ReviewBinIntent.Restore(item)) },
                            )
                        }
                    }
                }
            }
        }

        celebration?.let { data ->
            TrashCelebrationOverlay(
                spaceSavedLabel = formatSpaceSaved(data.spaceSavedBytes),
                itemCount = data.itemCount,
                onDismiss = { celebration = null },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }

    uiState.selectedItem?.let { item ->
        ReviewMediaPreviewDialog(
            item = item,
            onDismiss = { viewModel.onIntent(ReviewBinIntent.DismissPreview) },
            onRestore = { viewModel.onIntent(ReviewBinIntent.Restore(item)) },
        )
    }
}

private data class CelebrationData(val spaceSavedBytes: Long, val itemCount: Int)

/** 4:3 grid cell — tap opens the full-screen preview, long-press restores directly (the
 * Compose analogue of iOS's context-menu Restore shortcut). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ReviewGridCell(
    item: PhotoItem,
    onTap: () -> Unit,
    onLongPressRestore: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .padding(2.dp)
            .aspectRatio(4f / 3f)
            .combinedClickable(onClick = onTap, onLongClick = onLongPressRestore),
    ) {
        AsyncImage(
            model = item.uriString,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        if (item.isVideo) {
            Text(
                text = "▶ " + formatDuration(item.durationMs),
                color = Color.White,
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .background(Color.Black.copy(alpha = 0.5f))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }
}
