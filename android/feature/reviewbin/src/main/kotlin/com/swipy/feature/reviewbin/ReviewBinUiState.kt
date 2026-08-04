package com.swipy.feature.reviewbin

import com.swipy.domain.model.PhotoItem
import kotlinx.collections.immutable.PersistentList
import kotlinx.collections.immutable.persistentListOf

data class ReviewBinUiState(
    val isLoading: Boolean = true,
    val items: PersistentList<PhotoItem> = persistentListOf(),
    val totalSpaceSaved: Long = 0L,
)
