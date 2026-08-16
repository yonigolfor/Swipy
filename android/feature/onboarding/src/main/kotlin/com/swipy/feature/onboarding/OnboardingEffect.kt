package com.swipy.feature.onboarding

/** One-shot events the ViewModel can't perform itself (launching a system UI surface needs a
 * Composable-side launcher) — never modeled as state, same convention as PhotoStackEffect. */
sealed interface OnboardingEffect {
    data object LaunchPermissionRequest : OnboardingEffect
    data object OpenAppSettings : OnboardingEffect
}
