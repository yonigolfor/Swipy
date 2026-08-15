package com.swipy.feature.swipe

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.model.SwipeAction
import com.swipy.domain.repository.PhotoStateRepository
import com.swipy.domain.usecase.ActivateShuffleUseCase
import com.swipy.domain.usecase.DeactivateShuffleUseCase
import com.swipy.domain.usecase.DeletePhotoUseCase
import com.swipy.domain.usecase.GetPhotoStackPageUseCase
import com.swipy.domain.usecase.KeepPhotoUseCase
import com.swipy.domain.usecase.SnoozePhotoUseCase
import com.swipy.domain.usecase.UndoSwipeUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.toPersistentList
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
 *
 * Owns Keep/Delete/Snooze/Undo only. Permanent deletion (createDeleteRequest/PendingIntent)
 * is ReviewBinViewModel's job — see android/CLAUDE.md "Deletion & Trash" for why that logic
 * moved out of this class once :feature:reviewbin existed to host it properly.
 */
@HiltViewModel
class PhotoStackViewModel @Inject constructor(
    private val getPhotoStackPageUseCase: GetPhotoStackPageUseCase,
    private val keepPhotoUseCase: KeepPhotoUseCase,
    private val deletePhotoUseCase: DeletePhotoUseCase,
    private val snoozePhotoUseCase: SnoozePhotoUseCase,
    private val undoSwipeUseCase: UndoSwipeUseCase,
    private val activateShuffleUseCase: ActivateShuffleUseCase,
    private val deactivateShuffleUseCase: DeactivateShuffleUseCase,
    private val photoStateRepository: PhotoStateRepository,
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
    private var currentFilter: FilterCategory = FilterCategory.All

    // Shuffle Mode state — see android/CLAUDE.md and ActivateShuffleUseCase's doc for why this
    // is a random SEEK (snapshot + saved offset), not a full shuffled-index map.
    // Snapshot of the stack at the moment shuffle was first activated — restored on exit.
    private var preShuffleStack: List<PhotoItem>? = null
    // nextOffset at the moment shuffle was first activated — restored on exit.
    private var savedOffset = 0

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
            PhotoStackIntent.ActivateShuffle -> handleActivateShuffle()
            PhotoStackIntent.DeactivateShuffle -> exitShuffle(silent = false)
            is PhotoStackIntent.LoadPhotos -> handleLoadPhotos(intent.filter)
        }
    }

    private fun handleSwipe(item: PhotoItem, action: SwipeAction) {
        excludedIds += item.id
        lastSwipe = LastSwipe(item, action)
        // Optimistic, synchronous removal — the use-case call below is async, but the card
        // must leave the stack immediately so a shake/undo during that window always targets
        // the swipe just made. Mirrors iOS's beginSwipe-before-the-exit-delay ordering.
        _uiState.update { state ->
            state.copy(
                stack = state.stack.remove(item),
                canUndo = true,
                sessionSpaceSavedMB = if (action == SwipeAction.Delete) {
                    state.sessionSpaceSavedMB + item.fileSizeBytes.toMbDelta()
                } else {
                    state.sessionSpaceSavedMB
                },
            )
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
            state.copy(
                stack = state.stack.add(0, last.item),
                canUndo = false,
                sessionSpaceSavedMB = if (last.action == SwipeAction.Delete) {
                    (state.sessionSpaceSavedMB - last.item.fileSizeBytes.toMbDelta()).coerceAtLeast(0.0)
                } else {
                    state.sessionSpaceSavedMB
                },
            )
        }
        viewModelScope.launch { undoSwipeUseCase(last.item, last.action) }
    }

    private suspend fun maybeLoadMore() {
        val state = _uiState.value
        if (state.stack.size > WATERMARK) return
        // Shuffle segment exhausted (ran off the end of the library from the random seek) —
        // silently return to the linear stream, mirroring iOS shuffleExhausted().
        if (state.isShuffleModeActive && !hasMore && state.stack.isEmpty()) {
            exitShuffle(silent = true)
            return
        }
        loadPage(minCount = PAGE_SIZE)
    }

    // Shuffle Mode

    /** User-triggered: jump to a random point in the timeline. */
    private fun handleActivateShuffle() {
        val alreadyActive = _uiState.value.isShuffleModeActive
        if (!alreadyActive) {
            // Save the snapshot/offset only on first activation — re-shuffling while already
            // active must not overwrite the original position the user will return to.
            preShuffleStack = _uiState.value.stack
            savedOffset = nextOffset
        }
        lastSwipe = null
        _uiState.update { it.copy(canUndo = false, isLoading = true) }

        viewModelScope.launch {
            val randomOffset = activateShuffleUseCase(currentFilter)
            if (randomOffset == null) {
                // Empty library — matches iOS's `guard totalAssetCount > 0`; nothing to seek into.
                _uiState.update { it.copy(isLoading = false) }
                return@launch
            }

            _uiState.update { it.copy(stack = it.stack.clear()) }
            isFetching = false
            nextOffset = randomOffset
            hasMore = true
            loadPage(minCount = INITIAL_LOAD)

            // Wrap around once if the random landing spot turned up nothing.
            if (_uiState.value.stack.isEmpty() && randomOffset > 0) {
                nextOffset = 0
                hasMore = true
                loadPage(minCount = INITIAL_LOAD)
            }

            val landedStack = _uiState.value.stack
            if (landedStack.isEmpty()) {
                // Still empty after wraparound — no unprocessed items anywhere; exit gracefully.
                exitShuffle(silent = true)
            } else {
                _uiState.update { it.copy(isShuffleModeActive = true, isLoading = false) }
                _effects.trySend(PhotoStackEffect.ShuffleLanded(landedStack.first().dateAddedEpochSeconds))
            }
        }
    }

    /**
     * Exits shuffle mode, restoring the pre-shuffle snapshot. [silent] distinguishes the
     * user-tapped exit (fires [PhotoStackEffect.ShuffleLanded] so the screen can show a
     * "back home" indicator) from an auto-triggered one — either shuffle never found any
     * matching items to land on, or the shuffled segment ran off the end of the library
     * (see [maybeLoadMore]) — where no extra chrome should appear.
     */
    private fun exitShuffle(silent: Boolean) {
        val snapshot = preShuffleStack
        val restored = if (snapshot != null) {
            deactivateShuffleUseCase(snapshot, excludedIds).toPersistentList()
        } else {
            _uiState.value.stack.clear()
        }
        nextOffset = savedOffset
        hasMore = true
        isFetching = false
        preShuffleStack = null
        lastSwipe = null
        _uiState.update {
            it.copy(isShuffleModeActive = false, isLoading = false, stack = restored, canUndo = false)
        }
        if (!silent) {
            _effects.trySend(PhotoStackEffect.ShuffleLanded(landedAtEpochSeconds = null))
        }
        viewModelScope.launch { maybeLoadMore() }
    }

    /**
     * Selected from the Categories screen — the port of iOS `resetAndLoad(filter:)`. A filter
     * change wholesale-replaces the stack context, so shuffle and any pending undo are reset
     * exactly like [exitShuffle]/a fresh cold start would, not merely swapped in place.
     */
    private fun handleLoadPhotos(filter: FilterCategory) {
        currentFilter = filter
        nextOffset = 0
        hasMore = true
        isFetching = false
        preShuffleStack = null
        savedOffset = 0
        lastSwipe = null
        _uiState.update {
            it.copy(
                isLoading = true,
                stack = it.stack.clear(),
                canUndo = false,
                isShuffleModeActive = false,
            )
        }
        viewModelScope.launch {
            loadPage(minCount = INITIAL_LOAD)
            _uiState.update { it.copy(isLoading = false) }
        }
    }

    private suspend fun loadPage(minCount: Int) {
        if (isFetching || !hasMore) return
        isFetching = true
        try {
            val collected = mutableListOf<PhotoItem>()
            var attempts = 0
            while (collected.size < minCount && hasMore && attempts < MAX_FETCH_ATTEMPTS) {
                val page = getPhotoStackPageUseCase(currentFilter, nextOffset, PAGE_SIZE)
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

private const val BYTES_PER_MB = 1_048_576.0

private fun Long.toMbDelta(): Double = this / BYTES_PER_MB
