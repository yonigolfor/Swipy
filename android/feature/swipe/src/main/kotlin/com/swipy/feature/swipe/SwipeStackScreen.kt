package com.swipy.feature.swipe

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
 * (Undo, a Review Bin entry point) to exercise the MVI + gesture flow end-to-end.
 */
@Composable
fun SwipeStackScreen(
    onNavigateToReviewBin: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: PhotoStackViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        viewModel.effects.collect { /* no snackbar host wired up in this minimal chrome yet */ }
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
            TextButton(onClick = onNavigateToReviewBin) {
                Text("Review Bin (${uiState.reviewBinCount})")
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
