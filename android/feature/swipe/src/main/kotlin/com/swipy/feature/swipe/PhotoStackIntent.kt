package com.swipy.feature.swipe

import com.swipy.domain.model.PhotoItem
import com.swipy.domain.model.SwipeAction

sealed interface PhotoStackIntent {
    data class Swipe(val item: PhotoItem, val action: SwipeAction) : PhotoStackIntent
    data object Undo : PhotoStackIntent

    /** UI tapped "Empty Trash" — ViewModel decides API 30+ batch vs API 29 one-at-a-time. */
    data object RequestEmptyReviewBin : PhotoStackIntent

    /** The system delete/recovery confirmation returned RESULT_OK. */
    data object ConfirmEmptyReviewBin : PhotoStackIntent
}
