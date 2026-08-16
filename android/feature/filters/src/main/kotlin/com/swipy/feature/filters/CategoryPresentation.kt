package com.swipy.feature.filters

import androidx.annotation.StringRes
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
 *
 * [titleRes]/[descriptionRes] hold resource ids, not resolved strings — this function isn't
 * @Composable (it's called from inside `remember { }`), so stringResource() can't run here;
 * callers resolve these at the actual Text() call site instead.
 */
internal data class CategoryPresentation(
    val glyph: String,
    val color: Color,
    @StringRes val titleRes: Int,
    @StringRes val descriptionRes: Int,
)

internal fun FilterCategory.presentation(): CategoryPresentation = when (this) {
    FilterCategory.All -> CategoryPresentation(
        glyph = "🖼️",
        color = FilterAll,
        titleRes = R.string.filter_all_title,
        descriptionRes = R.string.filter_all_description,
    )
    FilterCategory.Screenshots -> CategoryPresentation(
        glyph = "📱",
        color = FilterScreenshots,
        titleRes = R.string.filter_screenshots_title,
        descriptionRes = R.string.filter_screenshots_description,
    )
    FilterCategory.ScreenRecordings -> CategoryPresentation(
        glyph = "⏺️",
        color = FilterScreenRecordings,
        titleRes = R.string.filter_screen_recordings_title,
        descriptionRes = R.string.filter_screen_recordings_description,
    )
    FilterCategory.LargeVideos -> CategoryPresentation(
        glyph = "🎬",
        color = FilterLargeVideos,
        titleRes = R.string.filter_large_videos_title,
        descriptionRes = R.string.filter_large_videos_description,
    )
    FilterCategory.BlurryPhotos -> CategoryPresentation(
        glyph = "🌫️",
        color = FilterBlurryPhotos,
        titleRes = R.string.filter_blurry_photos_title,
        descriptionRes = R.string.filter_blurry_photos_description,
    )
    FilterCategory.BurstPhotos -> CategoryPresentation(
        glyph = "📸",
        color = FilterBurstPhotos,
        titleRes = R.string.filter_burst_photos_title,
        descriptionRes = R.string.filter_burst_photos_description,
    )
}
