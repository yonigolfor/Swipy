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
     * Phase-1 fast count for Smart Filters — a cheap COUNT(*) projection, capped at [cap]
     * (matches the "99+" display ceiling). For BlurryPhotos/BurstPhotos this is only a
     * candidate-pool estimate, not a verified match count — see android/CLAUDE.md
     * "Smart Filter Counting (2-Phase)".
     */
    suspend fun countForCategory(filter: FilterCategory, cap: Int): Int
}
