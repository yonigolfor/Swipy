package com.swipy.domain.repository

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.PhotoItem

/**
 * Implemented by :data:mediastore. See android/CLAUDE.md "MediaStore Querying — Pagination
 * & Performance" — [fetchPage] must never enumerate the full media store; callers page
 * explicitly (initial load 50 / page size 30 / watermark at <=15 remaining, per that doc).
 */
interface PhotoRepository {

    suspend fun fetchPage(filter: FilterCategory, offset: Int, limit: Int): List<PhotoItem>

    /**
     * Looks up specific items by id — used by the Review Bin, whose persisted state is just
     * ids/file-sizes (see PhotoStateRepository), not full PhotoItem metadata. [ids] is
     * expected to be small (a user's un-emptied bin), so a single "_ID IN (...)" query is
     * fine here — this is not the unbounded-growth concern fetchPage's exclusion filtering
     * avoids. Silently omits ids with no matching row (asset deleted externally).
     */
    suspend fun fetchByIds(ids: List<Long>): List<PhotoItem>

    /**
     * Phase-1 fast count for Smart Filters — a cheap COUNT(*) projection, capped at [cap]
     * (matches the "99+" display ceiling). For BlurryPhotos/BurstPhotos this is only a
     * candidate-pool estimate, not a verified match count — see android/CLAUDE.md
     * "Smart Filter Counting (2-Phase)".
     */
    suspend fun countForCategory(filter: FilterCategory, cap: Int): Int
}
