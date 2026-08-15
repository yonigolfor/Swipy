package com.swipy.feature.swipe

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.model.SwipeAction

sealed interface PhotoStackIntent {
    data class Swipe(val item: PhotoItem, val action: SwipeAction) : PhotoStackIntent
    data object Undo : PhotoStackIntent
    data object ActivateShuffle : PhotoStackIntent
    data object DeactivateShuffle : PhotoStackIntent

    /** Selected from the Categories screen — the port of iOS `loadPhotos(filter:)`. */
    data class LoadPhotos(val filter: FilterCategory) : PhotoStackIntent
}
