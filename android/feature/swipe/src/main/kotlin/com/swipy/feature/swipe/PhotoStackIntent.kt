package com.swipy.feature.swipe

import com.swipy.domain.model.PhotoItem
import com.swipy.domain.model.SwipeAction

sealed interface PhotoStackIntent {
    data class Swipe(val item: PhotoItem, val action: SwipeAction) : PhotoStackIntent
    data object Undo : PhotoStackIntent
}
