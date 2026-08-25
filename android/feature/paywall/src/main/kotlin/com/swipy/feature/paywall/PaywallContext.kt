package com.swipy.feature.paywall

/**
 * Where the paywall was triggered from — drives which headline/subtitle copy renders. Port of
 * iOS `PaywallContext` (PaywallView.swift).
 */
enum class PaywallContext {
    /** Shown once, right after onboarding completes — see `MainActivity.AppRoot`. */
    PostOnboarding,

    /** Shown when `SwipeQuotaRepository.canSwipe` blocks a Keep/Delete swipe. */
    SwipeLimitReached,
}
