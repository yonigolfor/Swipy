package com.swipy.feature.swipe

import com.swipy.domain.model.PhotoItem
import kotlinx.collections.immutable.PersistentList
import kotlinx.collections.immutable.persistentListOf

/**
 * Single immutable state object — the only thing screens in this module read. See
 * android/CLAUDE.md "Architecture" for why this beats several independent StateFlows.
 * [stack] is a PersistentList (not a plain List) so CardStackLayer's stability inference
 * isn't defeated on every unrelated recomposition — see "Card Isolation" in that doc — and
 * so the ViewModel gets structural add/remove without a full-list copy each swipe.
 */
data class PhotoStackUiState(
    val isLoading: Boolean = true,
    val stack: PersistentList<PhotoItem> = persistentListOf(),
    val canUndo: Boolean = false,
    val reviewBinCount: Int = 0,
    /** Cumulative MB freed by delete swipes this session — mirrors iOS sessionSpaceSavedMB. */
    val sessionSpaceSavedMB: Double = 0.0,
    /** True when the user has jumped to a random point in the timeline. Mirrors iOS isShuffleModeActive. */
    val isShuffleModeActive: Boolean = false,
)
