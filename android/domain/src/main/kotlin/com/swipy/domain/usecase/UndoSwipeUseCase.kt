package com.swipy.domain.usecase

import com.swipy.domain.model.PhotoItem
import com.swipy.domain.model.SwipeAction
import com.swipy.domain.repository.PhotoStateRepository
import javax.inject.Inject

/**
 * Reverses exactly one prior swipe decision — only a single step of undo is supported (the
 * ViewModel enforces this by only ever holding one "last swipe" at a time; this use case has
 * no notion of a history stack).
 */
class UndoSwipeUseCase @Inject constructor(
    private val photoStateRepository: PhotoStateRepository,
) {
    suspend operator fun invoke(item: PhotoItem, action: SwipeAction) {
        when (action) {
            SwipeAction.Keep -> photoStateRepository.unmarkKept(item.id)
            SwipeAction.Delete -> photoStateRepository.restoreFromReviewBin(item.id)
            SwipeAction.Snooze -> photoStateRepository.clearSnooze(item.id)
            SwipeAction.Undo -> Unit
        }
    }
}
