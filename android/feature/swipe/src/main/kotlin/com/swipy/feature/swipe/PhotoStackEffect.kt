package com.swipy.feature.swipe

/** One-shot events — never modeled as state. See android/CLAUDE.md "Architecture". */
sealed interface PhotoStackEffect {
    data object NothingToUndo : PhotoStackEffect

    /**
     * Fired once a shuffle jump/return lands — the Compose analogue of iOS's
     * `timeIndicatorView` + delayed `HapticService.shared.shuffleLand()`. [landedAtEpochSeconds]
     * is the new top card's date (activation) or null when returning home (deactivation) —
     * the screen decides which copy/format to show from that, this effect only carries data.
     */
    data class ShuffleLanded(val landedAtEpochSeconds: Long?) : PhotoStackEffect

    /**
     * Fired when a Keep/Delete swipe is blocked by `SwipeQuotaRepository.canSwipe` — the exact
     * "navigate to paywall" example android/CLAUDE.md's Architecture section names as the
     * canonical thing that must be an Effect, never a `showPaywall: Boolean` in
     * [PhotoStackUiState]. The screen owns what "show the paywall" actually means for its host
     * (a nav-controller push) — this module has zero dependency on `:feature:paywall`.
     */
    data object ShowPaywall : PhotoStackEffect
}
