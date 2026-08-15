package com.swipy.feature.filters

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.domain.model.FilterCategory
import com.swipy.domain.repository.CategoryCountCacheRepository
import com.swipy.domain.repository.PhotoStateRepository
import com.swipy.domain.usecase.GetCategoryCountUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Owns the Categories screen's counts — deliberately separate from PhotoStackViewModel, the
 * same Android-idiomatic split already established by ReviewBinViewModel (iOS keeps the
 * equivalent state on its one shared VM; this app already deviates from that for Review Bin).
 *
 * Trigger discipline is simplified vs. iOS: counts recompute once per ViewModel instance
 * (`init`) plus on an explicit [FilterCategoriesIntent.Refresh] — no cross-ViewModel
 * "hasPendingCountUpdate" signal from PhotoStackViewModel's swipes, since Phase 1 here is
 * cheap/capped and self-correcting on every visit; wiring an event bus between two ViewModels
 * wasn't worth it for this milestone.
 */
@HiltViewModel
class FilterCategoriesViewModel @Inject constructor(
    private val getCategoryCountUseCase: GetCategoryCountUseCase,
    private val categoryCountCacheRepository: CategoryCountCacheRepository,
    private val photoStateRepository: PhotoStateRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(FilterCategoriesUiState())
    val uiState: StateFlow<FilterCategoriesUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            // Warm cache first so a returning user sees last-known numbers instantly,
            // before the fresh Phase 1 pass below (still triggered unconditionally) lands.
            val cached = categoryCountCacheRepository.cachedCounts.first()
            if (cached.isNotEmpty()) {
                _uiState.update { it.copy(counts = cached) }
            }
        }
        refresh()
    }

    fun onIntent(intent: FilterCategoriesIntent) {
        when (intent) {
            FilterCategoriesIntent.Refresh -> refresh()
        }
    }

    private fun refresh() {
        viewModelScope.launch {
            val excludedIds = buildSet {
                addAll(photoStateRepository.keptPhotoIds.first())
                addAll(photoStateRepository.reviewBinIds.first())
                addAll(photoStateRepository.snoozedPhotos.first().keys)
            }
            val counts = coroutineScope {
                FilterCategory.entries
                    .map { category -> async { category to getCategoryCountUseCase(category, CAP, excludedIds) } }
                    .awaitAll()
                    .toMap()
            }
            _uiState.update { it.copy(counts = counts) }
            categoryCountCacheRepository.saveCounts(counts)
        }
    }

    private companion object {
        const val CAP = 100
    }
}
