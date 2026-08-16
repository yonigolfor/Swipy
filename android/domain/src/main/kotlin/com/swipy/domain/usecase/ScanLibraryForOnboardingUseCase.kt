package com.swipy.domain.usecase

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.OnboardingScanCounts
import com.swipy.domain.repository.PhotoRepository
import javax.inject.Inject
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** Port of iOS `startOnboardingScan()`'s counting phase (PhotoStackViewModel.swift:535-575) —
 * the background prescan trigger it also kicks off has no Android equivalent yet (:data:vision
 * has no background-prescan entry point built), so this use case is scoped to the counts only. */
class ScanLibraryForOnboardingUseCase @Inject constructor(
    private val photoRepository: PhotoRepository,
) {
    suspend operator fun invoke(): OnboardingScanCounts = coroutineScope {
        val photoCount = async { photoRepository.totalImageCount() }
        val videoCount = async { photoRepository.totalVideoCount() }
        val largeVideoCount = async { photoRepository.totalCount(FilterCategory.LargeVideos) }
        OnboardingScanCounts(
            photoCount = photoCount.await(),
            videoCount = videoCount.await(),
            largeVideoCount = largeVideoCount.await(),
        )
    }
}
