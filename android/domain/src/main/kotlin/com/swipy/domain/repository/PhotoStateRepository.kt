package com.swipy.domain.repository

import kotlinx.coroutines.flow.Flow

/**
 * Persisted swipe-decision state — the Android analogue of iOS's PersistenceService
 * (UserDefaults-backed). See android/CLAUDE.md "Persistence" for the key-by-key mapping.
 *
 * [reviewBinSpaceSaved] is deliberately not a separate stored value — it's derived from
 * [reviewBinFileSizes], mirroring iOS PhotoStackViewModel's own comment on this exact point
 * ("Recompute from stored sizes so totalSpaceSaved is always derivable from bin contents").
 * [totalSpaceSavedLifetime] only increments in [emptyReviewBin] (real, permanent deletion) —
 * not in [addToReviewBin] — matching iOS emptyTrash(), where the lifetime counter is credited
 * only once PHPhotoLibrary deletion actually succeeds, never merely on a swipe-to-bin.
 */
interface PhotoStateRepository {

    val keptPhotoIds: Flow<Set<Long>>
    suspend fun markKept(id: Long)
    suspend fun unmarkKept(id: Long)

    val reviewBinIds: Flow<List<Long>>
    val reviewBinFileSizes: Flow<Map<Long, Long>>
    val reviewBinSpaceSaved: Flow<Long>
    val totalSpaceSavedLifetime: Flow<Long>

    /**
     * Epoch-millis timestamp of when each still-binned id was first added — drives the real
     * "24h since the oldest unresolved item" Review Bin reminder condition (mirrors iOS
     * `NOTIFICATIONS.md` trigger 1), instead of a coarse "bin is non-empty" proxy. Only set once
     * per id (see [addToReviewBin]) — an undo/re-swipe of an already-binned id must not reset
     * its clock.
     */
    val reviewBinAddedAt: Flow<Map<Long, Long>>

    suspend fun addToReviewBin(id: Long, fileSizeBytes: Long)
    suspend fun restoreFromReviewBin(id: Long)
    suspend fun emptyReviewBin()

    /**
     * Single-item permanent deletion — the API 29 fallback path, where Scoped Storage
     * requires one system confirmation per foreign-app item rather than [emptyReviewBin]'s
     * single batched dialog (API 30+). Credits that one item's bytes to
     * [totalSpaceSavedLifetime], same as [emptyReviewBin] does for the whole bin at once.
     */
    suspend fun removeFromReviewBinPermanently(id: Long)

    val snoozedPhotos: Flow<Map<Long, Int>>
    suspend fun snoozePhoto(id: Long, count: Int)
    suspend fun clearSnooze(id: Long)
}
