package com.swipy.domain.usecase

import com.swipy.domain.model.PhotoItem
import com.swipy.domain.repository.PhotoRepository
import com.swipy.domain.repository.PhotoStateRepository
import javax.inject.Inject

/**
 * Resolves the Review Bin's persisted ids into full [PhotoItem]s, preserving bin order (the
 * underlying MediaStore query has no guaranteed row order for an arbitrary id list). Any id
 * with no matching row (asset deleted externally, e.g. via the system Photos app) is silently
 * dropped and its bin bookkeeping cleaned up via [PhotoStateRepository.restoreFromReviewBin] —
 * not credited as space saved, since nothing was actually deleted through Swipy. Mirrors iOS's
 * restoreBinFromDisk() self-healing reconciliation.
 */
class GetReviewBinItemsUseCase @Inject constructor(
    private val photoRepository: PhotoRepository,
    private val photoStateRepository: PhotoStateRepository,
) {
    suspend operator fun invoke(ids: List<Long>): List<PhotoItem> {
        if (ids.isEmpty()) return emptyList()

        val found = photoRepository.fetchByIds(ids).associateBy { it.id }
        val missingIds = ids.filterNot { it in found }
        missingIds.forEach { photoStateRepository.restoreFromReviewBin(it) }

        return ids.mapNotNull { found[it] }
    }
}
