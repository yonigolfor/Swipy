package com.swipy.data.vision

import com.swipy.domain.model.PhotoItem
import com.swipy.domain.repository.BlurBurstAnalysisRepository
import javax.inject.Inject
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/**
 * Nonisolated, bounded-concurrency scan engine — the Android port of iOS BlurBurstScanEngine +
 * BurstAnalyzer, cache-first via [BlurBurstCacheStore]. [maxConcurrency] bounds concurrent
 * bitmap decodes so a large candidate page doesn't decode dozens of images at once.
 *
 * Callers pass an already page-bounded [items] list (see FilterCategoriesViewModel/
 * PhotoStackViewModel's paginated scan loops) — this class doesn't paginate on its own, mirroring
 * iOS's BlurBurstScanEngine/BurstAnalyzer, which likewise operate on one caller-provided batch
 * at a time.
 */
class BlurBurstAnalysisRepositoryImpl @Inject constructor(
    private val bitmapLoader: AnalysisBitmapLoader,
    private val cache: BlurBurstCacheStore,
) : BlurBurstAnalysisRepository {

    override suspend fun blurVerdict(item: PhotoItem): Boolean? {
        cache.blurVerdict(item.id)?.let { return it }
        if (item.isVideo) return null
        val bitmap = bitmapLoader.loadForAnalysis(item.uriString) ?: return null
        val verdict = try {
            BlurDetector.isBlurry(bitmap)
        } finally {
            bitmap.recycle()
        }
        cache.setBlurVerdict(item.id, verdict)
        return verdict
    }

    override suspend fun filterBlurry(items: List<PhotoItem>, maxConcurrency: Int): List<PhotoItem> {
        if (items.isEmpty()) return emptyList()
        val semaphore = Semaphore(maxConcurrency)
        return coroutineScope {
            items
                .map { item -> async { semaphore.withPermit { if (blurVerdict(item) == true) item else null } } }
                .awaitAll()
                .filterNotNull()
        }
    }

    override suspend fun filterBurstMembers(items: List<PhotoItem>, maxConcurrency: Int): List<PhotoItem> {
        if (items.size < MIN_GROUP_SIZE) return emptyList()

        // Every item that might be grouped may need its hash — precompute all of them
        // concurrently up front, same rationale as iOS's featurePrints() precompute pass: the
        // grouping walk below is then pure CPU (map lookups + Hamming distance), no sequential
        // per-photo I/O waits.
        val sorted = items.sortedBy { it.dateAddedEpochSeconds }
        val hashes = computeHashes(sorted, maxConcurrency)

        val result = mutableListOf<PhotoItem>()
        var group = mutableListOf(sorted[0])
        for (i in 1 until sorted.size) {
            val prev = sorted[i - 1]
            val curr = sorted[i]
            val gapSeconds = curr.dateAddedEpochSeconds - prev.dateAddedEpochSeconds

            val shouldGroup = if (gapSeconds <= TIME_GAP_THRESHOLD_SECONDS) {
                val prevHash = hashes[prev.id]
                val currHash = hashes[curr.id]
                if (prevHash != null && currHash != null) {
                    ImageHasher.normalizedDistance(prevHash, currHash) < VISUAL_DISTANCE_THRESHOLD
                } else {
                    // Hash unavailable (video, or a decode failure) — fall back to time,
                    // mirrors iOS's same fallback when a feature print can't be computed.
                    true
                }
            } else {
                false
            }

            if (shouldGroup) {
                group.add(curr)
            } else {
                if (group.size >= MIN_GROUP_SIZE) result += group
                group = mutableListOf(curr)
            }
        }
        if (group.size >= MIN_GROUP_SIZE) result += group
        return result
    }

    override suspend fun invalidate(assetIds: Set<Long>) = cache.invalidate(assetIds)

    private suspend fun computeHashes(items: List<PhotoItem>, maxConcurrency: Int): Map<Long, Long> {
        val semaphore = Semaphore(maxConcurrency)
        return coroutineScope {
            items
                .map { item ->
                    async {
                        cache.imageHash(item.id)?.let { return@async item.id to it }
                        if (item.isVideo) return@async null
                        semaphore.withPermit {
                            val bitmap = bitmapLoader.loadForAnalysis(item.uriString) ?: return@withPermit null
                            val hash = try {
                                ImageHasher.computeHash(bitmap)
                            } finally {
                                bitmap.recycle()
                            }
                            cache.setImageHash(item.id, hash)
                            item.id to hash
                        }
                    }
                }
                .awaitAll()
                .filterNotNull()
                .toMap()
        }
    }

    private companion object {
        const val TIME_GAP_THRESHOLD_SECONDS = 30L
        const val VISUAL_DISTANCE_THRESHOLD = 0.85f
        const val MIN_GROUP_SIZE = 5
    }
}
