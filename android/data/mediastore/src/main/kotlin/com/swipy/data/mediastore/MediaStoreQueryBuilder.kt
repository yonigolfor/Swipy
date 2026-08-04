package com.swipy.data.mediastore

import android.provider.MediaStore
import com.swipy.domain.model.FilterCategory

internal data class MediaStoreQuerySpec(
    val selection: String,
    val selectionArgs: Array<String>,
)

/**
 * Builds the WHERE clause per category. MediaStore has no direct "is screenshot" column
 * (unlike PHAsset's photoScreenshot media subtype on iOS) — screenshots/recordings are
 * detected via the relative-path/bucket-name heuristic every gallery-cleanup app on Android
 * uses. BlurryPhotos/BurstPhotos return only the Phase-1 candidate-pool selection (every
 * non-screenshot image) — the real ML-Kit-equivalent analysis that narrows this to a
 * verified match lives in :data:vision, not here. See android/CLAUDE.md "Smart Filter
 * Counting (2-Phase)".
 */
internal object MediaStoreQueryBuilder {

    // Parity with iOS PhotoLibraryService.largeVideoThresholdBytes (50_000_000).
    const val LARGE_VIDEO_THRESHOLD_BYTES = 50_000_000L

    private const val SCREENSHOT_PATH_MATCH = "%Screenshot%"
    private const val SCREEN_RECORDING_NAME_MATCH = "screenrecord%"
    private const val SCREENSHOT_BUCKET_NAME = "Screenshots"

    fun forCategory(filter: FilterCategory): MediaStoreQuerySpec = when (filter) {
        FilterCategory.All -> MediaStoreQuerySpec(
            selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?, ?)",
            selectionArgs = arrayOf(
                MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
                MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString(),
            ),
        )

        FilterCategory.Screenshots -> MediaStoreQuerySpec(
            selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ? AND " +
                "(${MediaStore.Files.FileColumns.RELATIVE_PATH} LIKE ? OR " +
                "${MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME} = ?)",
            selectionArgs = arrayOf(
                MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
                SCREENSHOT_PATH_MATCH,
                SCREENSHOT_BUCKET_NAME,
            ),
        )

        FilterCategory.ScreenRecordings -> MediaStoreQuerySpec(
            selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ? AND " +
                "(${MediaStore.Files.FileColumns.RELATIVE_PATH} LIKE ? OR " +
                "${MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME} = ? OR " +
                "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?)",
            selectionArgs = arrayOf(
                MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString(),
                SCREENSHOT_PATH_MATCH,
                SCREENSHOT_BUCKET_NAME,
                SCREEN_RECORDING_NAME_MATCH,
            ),
        )

        FilterCategory.LargeVideos -> MediaStoreQuerySpec(
            selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ? AND " +
                "${MediaStore.Files.FileColumns.SIZE} > ?",
            selectionArgs = arrayOf(
                MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString(),
                LARGE_VIDEO_THRESHOLD_BYTES.toString(),
            ),
        )

        FilterCategory.BlurryPhotos, FilterCategory.BurstPhotos -> MediaStoreQuerySpec(
            selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ? AND NOT " +
                "(${MediaStore.Files.FileColumns.RELATIVE_PATH} LIKE ? OR " +
                "${MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME} = ?)",
            selectionArgs = arrayOf(
                MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
                SCREENSHOT_PATH_MATCH,
                SCREENSHOT_BUCKET_NAME,
            ),
        )
    }
}
