package com.swipy.domain.usecase

import com.swipy.domain.model.PhotoItem
import javax.inject.Inject

/**
 * Restores the stack to show after exiting shuffle mode — the Android port of iOS
 * `restoreLinearStack()`. Uses the snapshot taken at the moment shuffle was first activated,
 * dropping anything the user actioned (kept/deleted/snoozed) during the shuffle detour. Pure
 * computation, no repository/Android dependency — mirrors why the iOS equivalent is a plain
 * private helper, kept here as a real use-case class only for naming/testing symmetry with
 * [ActivateShuffleUseCase].
 */
class DeactivateShuffleUseCase @Inject constructor() {
    operator fun invoke(preShuffleStack: List<PhotoItem>, excludedIds: Set<Long>): List<PhotoItem> =
        preShuffleStack.filterNot { it.id in excludedIds }
}
