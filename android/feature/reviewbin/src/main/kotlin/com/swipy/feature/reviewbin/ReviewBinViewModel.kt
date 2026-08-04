package com.swipy.feature.reviewbin

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.data.mediastore.MediaStoreDeletionRequests
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

    private var pendingLegacyDeleteId: Long? = null

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
    }

    fun onIntent(intent: ReviewBinIntent) {
        when (intent) {
            is ReviewBinIntent.Restore -> viewModelScope.launch { restoreFromReviewBinUseCase(intent.item.id) }
            ReviewBinIntent.RequestEmptyTrash -> handleRequestEmptyTrash()
            ReviewBinIntent.ConfirmEmptyTrash -> handleConfirmEmptyTrash()
        }
    }

    private fun handleRequestEmptyTrash() {
        viewModelScope.launch {
            val ids = photoStateRepository.reviewBinIds.first()
            if (ids.isEmpty()) return@launch

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val pendingIntent = deletionRequests.createBatchDeleteRequest(ids)
                _effects.trySend(ReviewBinEffect.LaunchDeleteConfirmation(pendingIntent))
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
            _effects.trySend(ReviewBinEffect.ReviewBinEmpty)
            return
        }
        val recoveryIntent = deletionRequests.deleteOrGetRecoveryIntent(id)
        if (recoveryIntent == null) {
            photoStateRepository.removeFromReviewBinPermanently(id)
            deleteNextLegacyItem(remainingIds.drop(1))
        } else {
            pendingLegacyDeleteId = id
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
            } else {
                photoStateRepository.emptyReviewBin()
            }
            _effects.trySend(ReviewBinEffect.ReviewBinEmpty)
        }
    }
}
