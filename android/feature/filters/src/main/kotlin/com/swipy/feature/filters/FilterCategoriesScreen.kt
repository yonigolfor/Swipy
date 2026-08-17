package com.swipy.feature.filters

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.swipy.core.designsystem.haptics.rememberHapticManager
import com.swipy.domain.model.FilterCategory

/** Screen chrome — the Compose analogue of iOS SmartFiltersView. A plain list, not a grid —
 * see the iOS spec: icon-circle + title + description + count badge + chevron rows only. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilterCategoriesScreen(
    onCategorySelected: (FilterCategory) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: FilterCategoriesViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.filters_top_bar_title)) },
                actions = {
                    IconButton(onClick = { viewModel.onIntent(FilterCategoriesIntent.Refresh) }) {
                        Text(text = "⟳", fontSize = 18.sp)
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
            item {
                Text(
                    text = stringResource(R.string.filters_subtitle),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                )
            }
            items(FilterCategory.entries, key = { it.name }) { category ->
                CategoryRow(
                    category = category,
                    count = uiState.counts[category],
                    isRecalculating = category in uiState.categoriesRecalculating,
                    onClick = { onCategorySelected(category) },
                )
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun CategoryRow(
    category: FilterCategory,
    count: Int?,
    isRecalculating: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val presentation = remember(category) { category.presentation() }
    val hapticManager = rememberHapticManager()
    val isConfirmedEmpty = count == 0
    val isClickable = count == null || count > 0

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(
                enabled = isClickable,
                onClick = {
                    // UISelectionFeedbackGenerator.selectionChanged() (HAPTICS.md "UI Actions").
                    hapticManager.selectionTick()
                    onClick()
                },
            )
            .graphicsLayer { alpha = if (isConfirmedEmpty) 0.4f else 1f }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(50.dp)
                .background(color = presentation.color.copy(alpha = 0.15f), shape = CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(text = presentation.glyph, fontSize = 20.sp)
        }

        Spacer(Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(text = stringResource(presentation.titleRes), style = MaterialTheme.typography.titleMedium)
            Text(
                text = stringResource(presentation.descriptionRes),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Spacer(Modifier.width(8.dp))
        CountBadge(
            count = count,
            color = presentation.color,
            isRecalculating = isRecalculating,
            isAllCategory = category == FilterCategory.All,
        )

        if (isClickable) {
            Spacer(Modifier.width(8.dp))
            // AutoMirrored so it correctly points left in Hebrew/RTL rows instead of a fixed
            // glyph that always points right regardless of layout direction.
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CountBadge(
    count: Int?,
    color: Color,
    isRecalculating: Boolean,
    isAllCategory: Boolean,
) {
    if (count == null) {
        ShimmerBadge()
        return
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (count > 0) {
            val label = if (count >= 100 && !isAllCategory) stringResource(R.string.filters_count_capped) else "$count"
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = Color.White,
                modifier = Modifier
                    .graphicsLayer { alpha = if (isRecalculating) 0.5f else 1f }
                    .background(color = color, shape = CircleShape)
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            )
        } else {
            Text(
                text = stringResource(R.string.filters_count_empty),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (isRecalculating) {
            CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
        }
    }
}

/**
 * Port of iOS ShimmerView — deliberately a pulsing-alpha placeholder rather than a literal
 * directional gradient sweep, to avoid brittle pixel-offset Brush math for a purely decorative
 * loading state. Shown only when a category has never loaded (count == null), matching iOS.
 */
@Composable
private fun ShimmerBadge() {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val alpha by transition.animateFloat(
        initialValue = 0.25f,
        targetValue = 0.6f,
        animationSpec = infiniteRepeatable(tween(700, easing = LinearEasing), repeatMode = RepeatMode.Reverse),
        label = "shimmerAlpha",
    )
    Box(
        modifier = Modifier
            .size(width = 48.dp, height = 16.dp)
            .background(
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = alpha),
                shape = CircleShape,
            ),
    )
}
