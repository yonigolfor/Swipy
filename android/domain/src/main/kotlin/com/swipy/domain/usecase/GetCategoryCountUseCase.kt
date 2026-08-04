package com.swipy.domain.usecase

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.repository.PhotoRepository
import javax.inject.Inject

class GetCategoryCountUseCase @Inject constructor(
    private val photoRepository: PhotoRepository,
) {
    suspend operator fun invoke(filter: FilterCategory, cap: Int = 100): Int =
        photoRepository.countForCategory(filter, cap)
}
