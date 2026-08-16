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
     * "Smart Filter Counting (2-Phase)". [excludedIds] (already-swiped items) are filtered
     * client-side in bounded batches — never pushed into a SQL "NOT IN", same convention as
     * [fetchPage]'s own exclusion handling.
     */
    suspend fun countForCategory(filter: FilterCategory, cap: Int, excludedIds: Set<Long> = emptySet()): Int

    /**
     * Uncapped row count for [filter] — used by Shuffle to pick a random valid offset
     * (`Random.nextInt(totalCount(...))`). Unlike [countForCategory] this is never capped;
     * it still avoids materializing PhotoItems (only the id column is projected), matching
     * the "no eager full enumeration" spirit for the expensive part — row-to-object mapping —
     * even though the underlying query does walk the full result set to produce a real count.
     */
    suspend fun totalCount(filter: FilterCategory): Int

    /**
     * Plain per-media-type totals — used only by the onboarding Scan step's counters.
     * Unlike [totalCount], neither has a [FilterCategory] equivalent ([FilterCategory.All]
     * combines both media types into one number) so these are their own repository methods
     * rather than a new enum case that nothing else would use.
     */
    suspend fun totalImageCount(): Int
    suspend fun totalVideoCount(): Int
}
