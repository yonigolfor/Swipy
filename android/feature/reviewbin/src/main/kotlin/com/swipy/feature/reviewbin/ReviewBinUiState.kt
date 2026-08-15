package com.swipy.feature.reviewbin

import com.swipy.domain.model.PhotoItem
import kotlinx.collections.immutable.PersistentList
import kotlinx.collections.immutable.persistentListOf

data class ReviewBinUiState(
    val isLoading: Boolean = true,
    val items: PersistentList<PhotoItem> = persistentListOf(),
    /** Pending space saved — the bin's current size, awaiting permanent deletion. */
    val totalSpaceSaved: Long = 0L,
    /** All-time freed space, across every emptied trash — shown only when the bin is empty. */
    val lifetimeSpaceSaved: Long = 0L,
    /** Item open in the full-screen preview dialog, or null when none is open. */
    val selectedItem: PhotoItem? = null,
)
