package com.swipy.domain.repository

import com.swipy.domain.model.PhotoItem

/**
 * On-device blur/burst analysis — the Android port of iOS's BlurDetector/BurstAnalyzer/
 * BlurBurstScanEngine. Implemented in :data:vision using hand-rolled algorithms (no ML Kit,
 * no network) — see that module's own docs for why the underlying techniques (variance-of-
 * Laplacian, difference-hash) are honest platform-appropriate substitutes for iOS's
 * CIEdges/VNGenerateImageFeaturePrintRequest, not literal ports.
 */
interface BlurBurstAnalysisRepository {

    /**
     * Cache-first blur verdict for one item. Null means "not analyzable this pass" (video, or
     * a decode failure) — callers must not treat null as "not blurry", since caching a false
     * verdict here would permanently hide a photo whose bitmap just isn't available yet.
     */
    suspend fun blurVerdict(item: PhotoItem): Boolean?

    /**
     * Filters [items] down to the ones that are actually blurry, analyzed with bounded
     * concurrency ([maxConcurrency] concurrent decodes at once — never all of [items] at once).
     */
    suspend fun filterBlurry(items: List<PhotoItem>, maxConcurrency: Int = DEFAULT_CONCURRENCY): List<PhotoItem>

    /**
     * Filters [items] — a single chronologically-orderable batch — down to the members of a
     * burst cluster: gap <= 30s AND perceptual-hash similarity, chain-compared consecutively,
     * minimum group size 5. Unlike iOS, there is no native "same burst ID" fast path — Android's
     * MediaStore exposes no OS-level burst-grouping metadata, so every grouping decision here
     * goes through the time+hash check.
     */
    suspend fun filterBurstMembers(items: List<PhotoItem>, maxConcurrency: Int = DEFAULT_CONCURRENCY): List<PhotoItem>

    /** Drops cached verdicts/hashes for assets that were removed or edited externally. */
    suspend fun invalidate(assetIds: Set<Long>)

    companion object {
        const val DEFAULT_CONCURRENCY = 6
    }
}
