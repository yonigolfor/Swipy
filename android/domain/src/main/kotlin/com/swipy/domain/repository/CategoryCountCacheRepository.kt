package com.swipy.domain.repository

import com.swipy.domain.model.FilterCategory
import kotlinx.coroutines.flow.Flow

/**
 * Disk-backed cache of the last computed Phase-1 category counts (see android/CLAUDE.md
 * "Smart Filter Counting (2-Phase)") — the Android analogue of iOS's
 * `Documents/categoryCounts.json`. Lets the Filters screen render last-known numbers
 * instantly on a cold start, before a fresh count finishes.
 */
interface CategoryCountCacheRepository {
    val cachedCounts: Flow<Map<FilterCategory, Int>>
    suspend fun saveCounts(counts: Map<FilterCategory, Int>)
}
