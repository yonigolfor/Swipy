package com.swipy.feature.filters

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.repository.CategoryCountCacheRepository
import com.swipy.domain.repository.PhotoStateRepository
import com.swipy.domain.usecase.FilterBlurryPhotosUseCase
import com.swipy.domain.usecase.FilterBurstPhotosUseCase
import com.swipy.domain.usecase.GetCategoryCountUseCase
import com.swipy.domain.usecase.GetPhotoStackPageUseCase
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
    private val getPhotoStackPageUseCase: GetPhotoStackPageUseCase,
    private val filterBlurryPhotosUseCase: FilterBlurryPhotosUseCase,
    private val filterBurstPhotosUseCase: FilterBurstPhotosUseCase,
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

            // Phase 2 — real accurate counts for Blurry/Burst via :data:vision, replacing the
            // Phase 1 candidate-pool estimate. LargeVideos needs no separate pass on Android —
            // MediaStore's SIZE column is already exact from Phase 1 (see android/CLAUDE.md).
            //
            // Simplification vs iOS: the dim+spinner shows on every recompute here, not only
            // the first-ever one — telling "first computation" from "silent re-verify" would
            // need a cache-schema change (tracking which persisted counts were Phase-2-verified)
            // that's out of scope for standing up the analysis engine itself.
            _uiState.update {
                it.copy(categoriesRecalculating = setOf(FilterCategory.BlurryPhotos, FilterCategory.BurstPhotos))
            }
            val accurateBlurryDeferred = async {
                accurateCount(FilterCategory.BlurryPhotos, excludedIds) { filterBlurryPhotosUseCase(it) }
            }
            val accurateBurstDeferred = async {
                accurateCount(FilterCategory.BurstPhotos, excludedIds) { filterBurstPhotosUseCase(it) }
            }
            val accurateBlurry = accurateBlurryDeferred.await()
            val accurateBurst = accurateBurstDeferred.await()

            val updatedCounts = counts + mapOf(
                FilterCategory.BlurryPhotos to accurateBlurry,
                FilterCategory.BurstPhotos to accurateBurst,
            )
            _uiState.update { it.copy(counts = updatedCounts, categoriesRecalculating = emptySet()) }
            categoryCountCacheRepository.saveCounts(updatedCounts)
        }
    }

    /**
     * Pages through [filter]'s candidate pool, running [analyze] (FilterBlurryPhotosUseCase or
     * FilterBurstPhotosUseCase) over each batch, until [CAP] matches are found or candidates
     * run out. Mirrors iOS's accurateBlurryCount/accurateBurstCount paginated-scan structure —
     * SCAN_PAGE_SIZE (300) matches iOS's own batch size for this exact scan.
     */
    private suspend fun accurateCount(
        filter: FilterCategory,
        excludedIds: Set<Long>,
        analyze: suspend (List<PhotoItem>) -> List<PhotoItem>,
    ): Int {
        var offset = 0
        var count = 0
        var attempts = 0
        while (count < CAP && attempts < MAX_SCAN_ATTEMPTS) {
            val page = getPhotoStackPageUseCase(filter, offset, SCAN_PAGE_SIZE)
            attempts++
            if (page.isEmpty()) break
            offset += page.size
            val candidates = page.filterNot { it.id in excludedIds }
            if (candidates.isNotEmpty()) {
                count += analyze(candidates).size
            }
        }
        return count.coerceAtMost(CAP)
    }

    private companion object {
        const val CAP = 100
        const val SCAN_PAGE_SIZE = 300
        const val MAX_SCAN_ATTEMPTS = 20
    }
}
