package com.swipy.feature.onboarding

sealed interface OnboardingIntent {
    /** Visual Hook's CTA — jumps straight to Permission, matching iOS's `currentStep = 3`. */
    data object StartFromHook : OnboardingIntent

    /** Permission step's CTA when not yet denied — fires [OnboardingEffect.LaunchPermissionRequest]. */
    data object RequestPermission : OnboardingIntent

    /** The system permission dialog's result. */
    data class PermissionResult(val granted: Boolean) : OnboardingIntent

    /** Silent re-check on `onResume()` — the Android analogue of iOS's `scenePhase == .active`
     * recovery; only acts if [OnboardingUiState.isPermissionDenied] is currently true. */
    data class RecheckPermissionOnResume(val granted: Boolean) : OnboardingIntent

    /** Permission step's CTA once denied — fires [OnboardingEffect.OpenAppSettings]. */
    data object OpenSettings : OnboardingIntent

    data object NextFromDemo : OnboardingIntent
    data object NextFromSnoozeIntro : OnboardingIntent
    data object NextFromScan : OnboardingIntent

    /** Quick Win's CTA — completes onboarding directly (no paywall step in this pass). */
    data object Complete : OnboardingIntent
}
