package com.swipy.domain.usecase

import com.swipy.domain.model.PhotoItem
import com.swipy.domain.repository.PhotoStateRepository
import javax.inject.Inject

/**
 * A left swipe moves a photo to the Review Bin — a silent, local-only operation with no
 * MediaStore/system interaction. Nothing is actually deleted from the device until the user
 * explicitly empties the bin (a single batched MediaStore.createDeleteRequest — see
 * android/CLAUDE.md "Deletion & Trash"). Calling any OS trash/delete API per-swipe would pop
 * a system confirmation dialog on every left swipe, which breaks the continuous-swipe UX this
 * app depends on — do not "fix" this to call MediaStore here.
 */
class DeletePhotoUseCase @Inject constructor(
    private val photoStateRepository: PhotoStateRepository,
) {
    suspend operator fun invoke(item: PhotoItem) =
        photoStateRepository.addToReviewBin(item.id, item.fileSizeBytes)
}
