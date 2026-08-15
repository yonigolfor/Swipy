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
import com.swipy.domain.usecase.FilterBlurryPhotosUseCase
import com.swipy.domain.usecase.FilterBurstPhotosUseCase
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
    private val filterBlurryPhotosUseCase: FilterBlurryPhotosUseCase,
    private val filterBurstPhotosUseCase: FilterBurstPhotosUseCase,
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
            val keptIds = photoStateRepository.keptPhotoIds.first()
            val binIds = photoStateRepository.reviewBinIds.first()
            val snoozedIds = photoStateRepository.snoozedPhotos.first().keys
            excludedIds += keptIds
            excludedIds += binIds
            excludedIds += snoozedIds
            loadPage(minCount = INITIAL_LOAD)
            _uiState.update { it.copy(isLoading = false) }

            // Reactive reconciliation from here on — an id that drops out of the bin (restored
            // from the Review Bin's full-screen viewer, or via single-swipe Undo) must resurface
            // via pagination; excludedIds is otherwise a plain in-memory set with no other way
            // to learn about a Review Bin restore. Seeded with the snapshot just taken above so
            // this collector's first emission (the current bin, unchanged) is a no-op.
            var previousBinIds = binIds.toSet()
            photoStateRepository.reviewBinIds.collect { ids ->
                val currentBinIds = ids.toSet()
                excludedIds -= (previousBinIds - currentBinIds)
                excludedIds += (currentBinIds - previousBinIds)
                previousBinIds = currentBinIds
                _uiState.update { it.copy(reviewBinCount = ids.size) }
            }
        }
        viewModelScope.launch {
            // sessionSpaceSavedMB mirrors the Review Bin's CURRENT pending size, not a
            // monotonic session counter — see android/CLAUDE.md. Deriving it from this Flow
            // (instead of hand-mutating it in handleSwipe/handleUndo) makes it automatically
            // correct across delete-swipe, undo, Review Bin restore, and empty-trash alike,
            // since reviewBinSpaceSaved is already reactively derived from reviewBinFileSizes.
            photoStateRepository.reviewBinSpaceSaved.collect { bytes ->
                _uiState.update { it.copy(sessionSpaceSavedMB = bytes.toMb()) }
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
        // sessionSpaceSavedMB is NOT set here — it's derived reactively from
        // photoStateRepository.reviewBinSpaceSaved (see init), which updates once
        // deletePhotoUseCase's addToReviewBin call below actually persists.
        _uiState.update { state -> state.copy(stack = state.stack.remove(item), canUndo = true) }

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
        // sessionSpaceSavedMB again derives reactively from reviewBinSpaceSaved — undoing a
        // delete calls restoreFromReviewBin below, which the collector in init picks up.
        _uiState.update { state -> state.copy(stack = state.stack.add(0, last.item), canUndo = false) }
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
            // Blurry/Burst need a wider window per MediaStore fetch than the default page size —
            // burst chain analysis in particular needs real chronological context to find
            // clusters, matching iOS's own larger initial/batch sizes for these two filters
            // (200/500 — see android/CLAUDE.md "Pagination & Image Loading"). Using the plain
            // PAGE_SIZE here would starve the analyzer of enough candidates per fetch to ever
            // find a burst.
            val fetchPageSize = when (currentFilter) {
                FilterCategory.BurstPhotos -> BURST_FETCH_PAGE_SIZE
                FilterCategory.BlurryPhotos -> BLURRY_FETCH_PAGE_SIZE
                else -> PAGE_SIZE
            }

            val collected = mutableListOf<PhotoItem>()
            var attempts = 0
            while (collected.size < minCount && hasMore && attempts < MAX_FETCH_ATTEMPTS) {
                val page = getPhotoStackPageUseCase(currentFilter, nextOffset, fetchPageSize)
                attempts++
                if (page.isEmpty()) {
                    hasMore = false
                    break
                }
                nextOffset += page.size
                val candidates = page.filterNot { it.id in excludedIds }
                // Real analysis, not just the MediaStore candidate-pool query — without this,
                // selecting "Blurry Photos"/"Burst Photos" would show every non-screenshot
                // photo, not just the ones actually verified blurry/part of a burst.
                val matched = when (currentFilter) {
                    FilterCategory.BlurryPhotos -> filterBlurryPhotosUseCase(candidates)
                    FilterCategory.BurstPhotos -> filterBurstPhotosUseCase(candidates)
                    else -> candidates
                }
                collected += matched
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
        const val BLURRY_FETCH_PAGE_SIZE = 200
        const val BURST_FETCH_PAGE_SIZE = 500
        const val WATERMARK = 15
        const val MAX_FETCH_ATTEMPTS = 20
    }
}

private const val BYTES_PER_MB = 1_048_576.0

private fun Long.toMb(): Double = this / BYTES_PER_MB
