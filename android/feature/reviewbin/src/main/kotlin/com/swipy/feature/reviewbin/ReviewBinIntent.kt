package com.swipy.feature.reviewbin

import com.swipy.domain.model.PhotoItem

sealed interface ReviewBinIntent {
    data class Restore(val item: PhotoItem) : ReviewBinIntent
    data object RequestEmptyTrash : ReviewBinIntent

    /** The system delete/recovery confirmation returned RESULT_OK. */
    data object ConfirmEmptyTrash : ReviewBinIntent
}
