package com.swipy.domain.usecase

import com.swipy.domain.repository.PhotoStateRepository
import javax.inject.Inject

class RestoreFromReviewBinUseCase @Inject constructor(
    private val photoStateRepository: PhotoStateRepository,
) {
    suspend operator fun invoke(id: Long) = photoStateRepository.restoreFromReviewBin(id)
}
