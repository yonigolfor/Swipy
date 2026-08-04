package com.swipy.feature.swipe

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.data.mediastore.MediaStoreDeletionRequests
import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.model.SwipeAction
import com.swipy.domain.repository.PhotoStateRepository
import com.swipy.domain.usecase.DeletePhotoUseCase
import com.swipy.domain.usecase.GetPhotoStackPageUseCase
import com.swipy.domain.usecase.KeepPhotoUseCase
import com.swipy.domain.usecase.SnoozePhotoUseCase
import com.swipy.domain.usecase.UndoSwipeUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.persistentListOf
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Single source of truth for the swipe screen — see android/CLAUDE.md "Architecture". The
 * only public surface is [uiState]/[effects] (reads) and [onIntent] (the one write entry
 * point); CardStackLayer/SwipeStackScreen never call use cases or the repository directly.
 */
@HiltViewModel
class PhotoStackViewModel @Inject constructor(
    private val getPhotoStackPageUseCase: GetPhotoStackPageUseCase,
    private val keepPhotoUseCase: KeepPhotoUseCase,
    private val deletePhotoUseCase: DeletePhotoUseCase,
    private val snoozePhotoUseCase: SnoozePhotoUseCase,
    private val undoSwipeUseCase: UndoSwipeUseCase,
    private val photoStateRepository: PhotoStateRepository,
    private val deletionRequests: MediaStoreDeletionRequests,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PhotoStackUiState())
    val uiState: StateFlow<PhotoStackUiState> = _uiState.asStateFlow()

    private val _effects = Channel<PhotoStackEffect>(Channel.BUFFERED)
    val effects = _effects.receiveAsFlow()

    // In-memory exclusion set — client-side filtered against each fetched page rather than
    // pushed into the MediaStore selection clause, to avoid an unbounded-growth SQL "NOT IN"
    // list as keptPhotoIds/reviewBinIds accumulate over the app's lifetime. Measure-before-
    // optimizing: revisit only if this is ever shown to matter for a real library size.
    private val excludedIds = mutableSetOf<Long>()
    private var nextOffset = 0
    private var isFetching = false
    private var hasMore = true
    private var lastSwipe: LastSwipe? = null
    private var pendingLegacyDeleteId: Long? = null

    init {
        viewModelScope.launch {
            excludedIds += photoStateRepository.keptPhotoIds.first()
            excludedIds += photoStateRepository.reviewBinIds.first()
            excludedIds += photoStateRepository.snoozedPhotos.first().keys
            loadPage(minCount = INITIAL_LOAD)
            _uiState.update { it.copy(isLoading = false) }
        }
        viewModelScope.launch {
            photoStateRepository.reviewBinIds.collect { ids ->
                _uiState.update { it.copy(reviewBinCount = ids.size) }
            }
        }
    }

    fun onIntent(intent: PhotoStackIntent) {
        when (intent) {
            is PhotoStackIntent.Swipe -> handleSwipe(intent.item, intent.action)
            PhotoStackIntent.Undo -> handleUndo()
            PhotoStackIntent.RequestEmptyReviewBin -> handleRequestEmptyReviewBin()
            PhotoStackIntent.ConfirmEmptyReviewBin -> handleConfirmEmptyReviewBin()
        }
    }

    private fun handleSwipe(item: PhotoItem, action: SwipeAction) {
        excludedIds += item.id
        lastSwipe = LastSwipe(item, action)
        // Optimistic, synchronous removal — the use-case call below is async, but the card
        // must leave the stack immediately so a shake/undo during that window always targets
        // the swipe just made. Mirrors iOS's beginSwipe-before-the-exit-delay ordering.
        _uiState.update { state ->
            state.copy(stack = state.stack.remove(item), canUndo = true)
        }

        viewModelScope.launch {
            when (action) {
                SwipeAction.Keep -> keepPhotoUseCase(item.id)
                SwipeAction.Delete -> deletePhotoUseCase(item)
                SwipeAction.Snooze -> snoozePhotoUseCase(item.id)
                SwipeAction.Undo -> Unit
            }
            maybeLoadMore()
        }
    }

    private fun handleUndo() {
        val last = lastSwipe
        if (last == null) {
            _effects.trySend(PhotoStackEffect.NothingToUndo)
            return
        }
        lastSwipe = null
        excludedIds -= last.item.id
        _uiState.update { state ->
            state.copy(stack = state.stack.add(0, last.item), canUndo = false)
        }
        viewModelScope.launch { undoSwipeUseCase(last.item, last.action) }
    }

    private fun handleRequestEmptyReviewBin() {
        viewModelScope.launch {
            val ids = photoStateRepository.reviewBinIds.first()
            if (ids.isEmpty()) return@launch

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val pendingIntent = deletionRequests.createBatchDeleteRequest(ids)
                _effects.trySend(PhotoStackEffect.LaunchDeleteConfirmation(pendingIntent))
            } else {
                deleteNextLegacyItem(ids)
            }
        }
    }

    /**
     * API 29 fallback — one Review Bin item per call (see MediaStoreDeletionRequests for why
     * this can't be a single batched dialog pre-30). Deletes outright wherever possible;
     * only pauses for a system confirmation on the first item that actually needs one.
     */
    private suspend fun deleteNextLegacyItem(remainingIds: List<Long>) {
        val id = remainingIds.firstOrNull() ?: run {
            _effects.trySend(PhotoStackEffect.ReviewBinEmpty)
            return
        }
        val recoveryIntent = deletionRequests.deleteOrGetRecoveryIntent(id)
        if (recoveryIntent == null) {
            photoStateRepository.removeFromReviewBinPermanently(id)
            deleteNextLegacyItem(remainingIds.drop(1))
        } else {
            pendingLegacyDeleteId = id
            _effects.trySend(PhotoStackEffect.LaunchDeleteConfirmation(recoveryIntent))
        }
    }

    private fun handleConfirmEmptyReviewBin() {
        viewModelScope.launch {
            val legacyId = pendingLegacyDeleteId
            if (legacyId != null) {
                pendingLegacyDeleteId = null
                // The recovery intent only grants permission — the delete must be retried.
                deletionRequests.deleteOrGetRecoveryIntent(legacyId)
                photoStateRepository.removeFromReviewBinPermanently(legacyId)
                _effects.trySend(PhotoStackEffect.ReviewBinEmpty)
            } else {
                photoStateRepository.emptyReviewBin()
                _effects.trySend(PhotoStackEffect.ReviewBinEmpty)
            }
        }
    }

    private suspend fun maybeLoadMore() {
        if (_uiState.value.stack.size <= WATERMARK) {
            loadPage(minCount = PAGE_SIZE)
        }
    }

    private suspend fun loadPage(minCount: Int) {
        if (isFetching || !hasMore) return
        isFetching = true
        try {
            val collected = mutableListOf<PhotoItem>()
            var attempts = 0
            while (collected.size < minCount && hasMore && attempts < MAX_FETCH_ATTEMPTS) {
                val page = getPhotoStackPageUseCase(FilterCategory.All, nextOffset, PAGE_SIZE)
                attempts++
                if (page.isEmpty()) {
                    hasMore = false
                    break
                }
                nextOffset += page.size
                collected += page.filterNot { it.id in excludedIds }
            }
            if (collected.isNotEmpty()) {
                _uiState.update { it.copy(stack = it.stack.addAll(collected)) }
            }
        } finally {
            isFetching = false
        }
    }

    private data class LastSwipe(val item: PhotoItem, val action: SwipeAction)

    private companion object {
        const val INITIAL_LOAD = 50
        const val PAGE_SIZE = 30
        const val WATERMARK = 15
        const val MAX_FETCH_ATTEMPTS = 20
    }
}
