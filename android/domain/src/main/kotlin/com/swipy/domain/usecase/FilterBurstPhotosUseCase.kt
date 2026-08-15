package com.swipy.domain.usecase

import com.swipy.domain.model.PhotoItem
import com.swipy.domain.repository.BlurBurstAnalysisRepository
import javax.inject.Inject

class FilterBurstPhotosUseCase @Inject constructor(
    private val blurBurstAnalysisRepository: BlurBurstAnalysisRepository,
) {
    suspend operator fun invoke(items: List<PhotoItem>): List<PhotoItem> =
        blurBurstAnalysisRepository.filterBurstMembers(items)
}
