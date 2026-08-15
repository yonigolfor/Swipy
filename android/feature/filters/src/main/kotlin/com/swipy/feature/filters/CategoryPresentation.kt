package com.swipy.feature.filters

import androidx.compose.ui.graphics.Color
import com.swipy.core.designsystem.theme.FilterAll
import com.swipy.core.designsystem.theme.FilterBlurryPhotos
import com.swipy.core.designsystem.theme.FilterBurstPhotos
import com.swipy.core.designsystem.theme.FilterLargeVideos
import com.swipy.core.designsystem.theme.FilterScreenRecordings
import com.swipy.core.designsystem.theme.FilterScreenshots
import com.swipy.domain.model.FilterCategory

/**
 * FilterCategory -> (glyph, color, copy) lives here, not in :core:designsystem — the design
 * system module only exports raw color tokens (domain-agnostic); joining them to a :domain
 * type belongs to the feature module that already depends on both. No material-icons-extended
 * dependency, same precedent as UndoFab/ShuffleCapsule — glyphs are plain emoji.
 */
internal data class CategoryPresentation(
    val glyph: String,
    val color: Color,
    val title: String,
    val description: String,
)

internal fun FilterCategory.presentation(): CategoryPresentation = when (this) {
    FilterCategory.All -> CategoryPresentation(
        glyph = "🖼️",
        color = FilterAll,
        title = "All Photos",
        description = "Every photo and video in your library",
    )
    FilterCategory.Screenshots -> CategoryPresentation(
        glyph = "📱",
        color = FilterScreenshots,
        title = "Screenshots",
        description = "Screenshots quietly taking up space",
    )
    FilterCategory.ScreenRecordings -> CategoryPresentation(
        glyph = "⏺️",
        color = FilterScreenRecordings,
        title = "Screen Recordings",
        description = "Recordings you probably don't need anymore",
    )
    FilterCategory.LargeVideos -> CategoryPresentation(
        glyph = "🎬",
        color = FilterLargeVideos,
        title = "Large Videos",
        description = "Videos using the most storage",
    )
    FilterCategory.BlurryPhotos -> CategoryPresentation(
        glyph = "🌫️",
        color = FilterBlurryPhotos,
        title = "Blurry Photos",
        description = "Out-of-focus shots worth a second look",
    )
    FilterCategory.BurstPhotos -> CategoryPresentation(
        glyph = "📸",
        color = FilterBurstPhotos,
        title = "Burst Photos",
        description = "Near-duplicate shots from burst mode",
    )
}
