package com.swipy.domain.usecase

import com.swipy.domain.repository.PhotoStateRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.first

/**
 * Persists the snooze decision and increments its count for backoff-aware badges next time.
 *
 * This intentionally does NOT yet implement the full absolute-milestone re-injection
 * schedule from SNOOZE_FEATURE.md (stagingMilestone/targetMilestone against a persisted
 * globalActionCounter) — a snoozed card is hidden from the stack and its count persists
 * across sessions, but nothing currently re-injects it after N keep/delete swipes. Porting
 * that scheduling algorithm is a deliberate follow-up, scoped out of this pass so the
 * MVI pipeline, gesture engine, and deletion wiring got full attention instead.
 */
class SnoozePhotoUseCase @Inject constructor(
    private val photoStateRepository: PhotoStateRepository,
) {
    suspend operator fun invoke(id: Long) {
        val currentCount = photoStateRepository.snoozedPhotos.first()[id] ?: 0
        photoStateRepository.snoozePhoto(id, currentCount + 1)
    }
}
