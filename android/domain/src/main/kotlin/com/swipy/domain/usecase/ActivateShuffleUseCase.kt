package com.swipy.domain.usecase

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.repository.PhotoRepository
import javax.inject.Inject
import kotlin.random.Random

/**
 * Picks a random valid page offset within [filter]'s current total row count — the Android
 * port of iOS's `Int.random(in: 0..<photoService.totalAssetCount)`. Shuffle is a random SEEK
 * into the existing chronological result set, not a full randomize-everything or a separate
 * shuffled index map: the ViewModel pages forward linearly from whatever offset this returns,
 * exactly like normal pagination. Returns null when the library is empty (nothing to seek into).
 */
class ActivateShuffleUseCase @Inject constructor(
    private val photoRepository: PhotoRepository,
) {
    suspend operator fun invoke(filter: FilterCategory): Int? {
        val total = photoRepository.totalCount(filter)
        if (total <= 0) return null
        return Random.nextInt(total)
    }
}
