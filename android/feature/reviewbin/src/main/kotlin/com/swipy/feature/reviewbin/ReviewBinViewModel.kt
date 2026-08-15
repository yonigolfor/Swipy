package com.swipy.feature.reviewbin

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.data.mediastore.MediaStoreDeletionRequests
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.repository.PhotoStateRepository
import com.swipy.domain.usecase.GetReviewBinItemsUseCase
import com.swipy.domain.usecase.RestoreFromReviewBinUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Owns permanent deletion — the Scoped Storage createDeleteRequest/PendingIntent flow that
 * used to live in PhotoStackViewModel before this module existed. See android/CLAUDE.md
 * "Deletion & Trash" for the full API 30+/29 split this ports 1:1 from that earlier version.
 */
@HiltViewModel
class ReviewBinViewModel @Inject constructor(
    private val getReviewBinItemsUseCase: GetReviewBinItemsUseCase,
    private val restoreFromReviewBinUseCase: RestoreFromReviewBinUseCase,
    private val photoStateRepository: PhotoStateRepository,
    private val deletionRequests: MediaStoreDeletionRequests,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ReviewBinUiState())
    val uiState: StateFlow<ReviewBinUiState> = _uiState.asStateFlow()

    private val _effects = Channel<ReviewBinEffect>(Channel.BUFFERED)
    val effects = _effects.receiveAsFlow()

    // API 30+ batch path — captured at request time so the celebration summary reflects
    // what's about to be deleted, read back once the system dialog reports RESULT_OK.
    private var pendingBatchSummary: Pair<Long, Int>? = null

    // API 29 legacy path — see deleteNextLegacyItem's doc for why this can span at most one
    // pending confirmation per "Empty Trash" tap.
    private var pendingLegacyDeleteId: Long? = null
    private var pendingLegacyFileSize: Long = 0L
    private var pendingLegacySoFarBytes: Long = 0L
    private var pendingLegacySoFarCount: Int = 0

    init {
        viewModelScope.launch {
            combine(
                photoStateRepository.reviewBinIds,
                photoStateRepository.reviewBinSpaceSaved,
            ) { ids, spaceSaved -> ids to spaceSaved }
                .collect { (ids, spaceSaved) ->
                    _uiState.update { it.copy(isLoading = true) }
                    val items = getReviewBinItemsUseCase(ids)
                    _uiState.update {
                        it.copy(isLoading = false, items = items.toPersistentList(), totalSpaceSaved = spaceSaved)
                    }
                }
        }
        viewModelScope.launch {
            photoStateRepository.totalSpaceSavedLifetime.collect { lifetime ->
                _uiState.update { it.copy(lifetimeSpaceSaved = lifetime) }
            }
        }
    }

    fun onIntent(intent: ReviewBinIntent) {
        when (intent) {
            is ReviewBinIntent.Restore -> handleRestore(intent.item)
            ReviewBinIntent.RequestEmptyTrash -> handleRequestEmptyTrash()
            ReviewBinIntent.ConfirmEmptyTrash -> handleConfirmEmptyTrash()
            is ReviewBinIntent.SelectItem -> _uiState.update { it.copy(selectedItem = intent.item) }
            ReviewBinIntent.DismissPreview -> _uiState.update { it.copy(selectedItem = null) }
        }
    }

    private fun handleRestore(item: PhotoItem) {
        if (_uiState.value.selectedItem?.id == item.id) {
            _uiState.update { it.copy(selectedItem = null) }
        }
        viewModelScope.launch { restoreFromReviewBinUseCase(item.id) }
    }

    private fun handleRequestEmptyTrash() {
        viewModelScope.launch {
            val ids = photoStateRepository.reviewBinIds.first()
            if (ids.isEmpty()) return@launch

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pendingBatchSummary = _uiState.value.totalSpaceSaved to ids.size
                val pendingIntent = deletionRequests.createBatchDeleteRequest(ids)
                _effects.trySend(ReviewBinEffect.LaunchDeleteConfirmation(pendingIntent))
            } else {
                val fileSizes = photoStateRepository.reviewBinFileSizes.first()
                deleteNextLegacyItem(ids, fileSizes, soFarBytes = 0L, soFarCount = 0)
            }
        }
    }

    /**
     * API 29 fallback — resolves items that don't need confirmation automatically, then
     * pauses at the first one that does (see MediaStoreDeletionRequests) rather than chaining
     * further confirmations within one "Empty Trash" tap — a deliberate, documented
     * simplification, not an oversight. [soFarBytes]/[soFarCount] accumulate what THIS tap
     * actually deletes, since a single tap on this path doesn't necessarily clear the whole bin.
     */
    private suspend fun deleteNextLegacyItem(
        remainingIds: List<Long>,
        fileSizes: Map<Long, Long>,
        soFarBytes: Long,
        soFarCount: Int,
    ) {
        val id = remainingIds.firstOrNull() ?: run {
            if (soFarCount > 0) {
                _effects.trySend(ReviewBinEffect.EmptyTrashCompleted(soFarBytes, soFarCount))
            }
            return
        }
        val recoveryIntent = deletionRequests.deleteOrGetRecoveryIntent(id)
        if (recoveryIntent == null) {
            photoStateRepository.removeFromReviewBinPermanently(id)
            deleteNextLegacyItem(
                remainingIds.drop(1),
                fileSizes,
                soFarBytes = soFarBytes + (fileSizes[id] ?: 0L),
                soFarCount = soFarCount + 1,
            )
        } else {
            pendingLegacyDeleteId = id
            pendingLegacyFileSize = fileSizes[id] ?: 0L
            pendingLegacySoFarBytes = soFarBytes
            pendingLegacySoFarCount = soFarCount
            _effects.trySend(ReviewBinEffect.LaunchDeleteConfirmation(recoveryIntent))
        }
    }

    private fun handleConfirmEmptyTrash() {
        viewModelScope.launch {
            val legacyId = pendingLegacyDeleteId
            if (legacyId != null) {
                pendingLegacyDeleteId = null
                // The recovery intent only grants permission — the delete must be retried.
                deletionRequests.deleteOrGetRecoveryIntent(legacyId)
                photoStateRepository.removeFromReviewBinPermanently(legacyId)
                _effects.trySend(
                    ReviewBinEffect.EmptyTrashCompleted(
                        spaceSavedBytes = pendingLegacySoFarBytes + pendingLegacyFileSize,
                        itemCount = pendingLegacySoFarCount + 1,
                    ),
                )
            } else {
                val summary = pendingBatchSummary
                    ?: (_uiState.value.totalSpaceSaved to _uiState.value.items.size)
                pendingBatchSummary = null
                photoStateRepository.emptyReviewBin()
                _effects.trySend(ReviewBinEffect.EmptyTrashCompleted(summary.first, summary.second))
            }
        }
    }
}
