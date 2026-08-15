package com.swipy.domain.usecase

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.repository.PhotoRepository
import javax.inject.Inject

class GetCategoryCountUseCase @Inject constructor(
    private val photoRepository: PhotoRepository,
) {
    suspend operator fun invoke(filter: FilterCategory, cap: Int = 100, excludedIds: Set<Long> = emptySet()): Int =
        photoRepository.countForCategory(filter, cap, excludedIds)
}
