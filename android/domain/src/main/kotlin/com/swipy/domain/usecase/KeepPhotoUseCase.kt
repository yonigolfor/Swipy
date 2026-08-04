package com.swipy.domain.usecase

import com.swipy.domain.repository.PhotoStateRepository
import javax.inject.Inject

class KeepPhotoUseCase @Inject constructor(
    private val photoStateRepository: PhotoStateRepository,
) {
    suspend operator fun invoke(id: Long) = photoStateRepository.markKept(id)
}
