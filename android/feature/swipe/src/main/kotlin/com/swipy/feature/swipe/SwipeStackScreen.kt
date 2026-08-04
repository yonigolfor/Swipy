package com.swipy.feature.swipe

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/**
 * Screen chrome — the Compose analogue of iOS SwipeStackView. Deliberately minimal for this
 * pass (no savings bar, FAB row, or shuffle capsule yet — those belong to :core:designsystem
 * components that don't exist here yet); it hosts CardStackLayer plus just enough chrome
 * (Undo, a temporary Empty Trash trigger) to exercise the full MVI + gesture + deletion flow
 * end-to-end.
 */
@Composable
fun SwipeStackScreen(
    modifier: Modifier = Modifier,
    viewModel: PhotoStackViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    val deleteConfirmationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            viewModel.onIntent(PhotoStackIntent.ConfirmEmptyReviewBin)
        }
    }

    LaunchedEffect(Unit) {
        viewModel.effects.collect { effect ->
            when (effect) {
                is PhotoStackEffect.LaunchDeleteConfirmation -> deleteConfirmationLauncher.launch(
                    IntentSenderRequest.Builder(effect.pendingIntent.intentSender).build(),
                )
                // No snackbar host wired up in this minimal chrome yet.
                PhotoStackEffect.NothingToUndo, PhotoStackEffect.ReviewBinEmpty -> Unit
            }
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            TextButton(
                onClick = { viewModel.onIntent(PhotoStackIntent.Undo) },
                enabled = uiState.canUndo,
            ) {
                Text("Undo")
            }
            // Temporary — the real trigger for this belongs to :feature:reviewbin's "Empty
            // Trash" action once that screen exists. Kept here so the Scoped Storage
            // deletion flow (MediaStoreDeletionRequests) has a real, tappable call site to
            // validate against rather than shipping it untested.
            TextButton(
                onClick = { viewModel.onIntent(PhotoStackIntent.RequestEmptyReviewBin) },
                enabled = uiState.reviewBinCount > 0,
            ) {
                Text("Empty Trash (${uiState.reviewBinCount})")
            }
        }

        Box(
            modifier = Modifier
                .weight(1f)
                .padding(24.dp),
        ) {
            when {
                uiState.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))

                uiState.stack.isEmpty() -> Text(
                    text = "No more photos",
                    modifier = Modifier.align(Alignment.Center),
                    style = MaterialTheme.typography.titleMedium,
                )

                else -> CardStackLayer(
                    items = uiState.stack,
                    onSwipeCommitted = { item, action ->
                        viewModel.onIntent(PhotoStackIntent.Swipe(item, action))
                    },
                )
            }
        }
    }
}
