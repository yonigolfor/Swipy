package com.swipy.domain.usecase

import com.swipy.domain.model.FilterCategory
import com.swipy.domain.repository.PhotoRepository
import javax.inject.Inject

/** Uncapped real count for [filter] — unlike [GetCategoryCountUseCase], never returns a
 * Phase-1-capped estimate. Currently only meant for [FilterCategory.All]: iOS shows a real
 * total there instead of the shared "99+" ceiling every other category uses (a bare capped
 * number like "100" for the whole-library category reads as a precise small count, not an
 * estimate — see android/TODO.md item 5). */
class GetTotalCategoryCountUseCase @Inject constructor(
    private val photoRepository: PhotoRepository,
) {
    suspend operator fun invoke(filter: FilterCategory): Int = photoRepository.totalCount(filter)
}
