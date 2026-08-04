package com.swipy.feature.reviewbin

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage

/** No full-screen detail viewer yet — a 3-column grid, tap-to-restore, and Empty Trash. */
@Composable
fun ReviewBinScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: ReviewBinViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

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
                // No snackbar host wired up in this minimal chrome yet.
                ReviewBinEffect.ReviewBinEmpty -> Unit
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
            TextButton(onClick = onBack) {
                Text("Back")
            }
            Text("Review Bin", style = MaterialTheme.typography.titleMedium)
            TextButton(
                onClick = { viewModel.onIntent(ReviewBinIntent.RequestEmptyTrash) },
                enabled = uiState.items.isNotEmpty(),
            ) {
                Text("Empty Trash")
            }
        }

        Box(modifier = Modifier.fillMaxSize()) {
            when {
                uiState.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))

                uiState.items.isEmpty() -> Text(
                    text = "Bin is empty",
                    modifier = Modifier.align(Alignment.Center),
                    style = MaterialTheme.typography.titleMedium,
                )

                else -> LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    contentPadding = PaddingValues(4.dp),
                ) {
                    items(uiState.items, key = { it.id }) { item ->
                        Box(
                            modifier = Modifier
                                .padding(2.dp)
                                .aspectRatio(1f)
                                .clickable { viewModel.onIntent(ReviewBinIntent.Restore(item)) },
                        ) {
                            AsyncImage(
                                model = item.uriString,
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize(),
                            )
                            Text(
                                text = "↺ Restore",
                                color = Color.White,
                                style = MaterialTheme.typography.labelSmall,
                                modifier = Modifier
                                    .align(Alignment.BottomCenter)
                                    .fillMaxWidth()
                                    .background(Color.Black.copy(alpha = 0.5f))
                                    .padding(4.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}
