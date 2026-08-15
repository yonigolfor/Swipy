package com.swipy.feature.reviewbin

import com.swipy.domain.model.PhotoItem

sealed interface ReviewBinIntent {
    data class Restore(val item: PhotoItem) : ReviewBinIntent
    data object RequestEmptyTrash : ReviewBinIntent

    /** The system delete/recovery confirmation returned RESULT_OK. */
    data object ConfirmEmptyTrash : ReviewBinIntent

    /** Tapped a grid tile — opens the full-screen preview. */
    data class SelectItem(val item: PhotoItem) : ReviewBinIntent

    /** Closed the full-screen preview without restoring. */
    data object DismissPreview : ReviewBinIntent
}
