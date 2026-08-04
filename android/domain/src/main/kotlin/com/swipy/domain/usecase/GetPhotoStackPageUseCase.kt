package com.swipy.domain.usecase

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.repository.PhotoRepository
import javax.inject.Inject

class GetPhotoStackPageUseCase @Inject constructor(
    private val photoRepository: PhotoRepository,
) {
    suspend operator fun invoke(filter: FilterCategory, offset: Int, limit: Int): List<PhotoItem> =
        photoRepository.fetchPage(filter, offset, limit)
}
