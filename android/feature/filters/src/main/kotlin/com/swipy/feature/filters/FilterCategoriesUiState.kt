package com.swipy.feature.filters

import com.swipy.domain.model.FilterCategory

/**
 * [counts] absence of a key means "never loaded yet" (shimmer) — mirrors iOS's
 * `categoryCounts[category] == nil` check exactly, see PhotoStackViewModel.swift.
 * [categoriesRecalculating] is always empty in this milestone — Phase 2 has nothing to verify
 * yet on Android (LargeVideos' MediaStore SIZE column is already exact from Phase 1; Blurry/
 * BurstPhotos need :data:vision, not built yet) — kept wired so a real Phase 2 slots in later
 * without a state-shape change.
 */
data class FilterCategoriesUiState(
    val counts: Map<FilterCategory, Int> = emptyMap(),
    val categoriesRecalculating: Set<FilterCategory> = emptySet(),
)
