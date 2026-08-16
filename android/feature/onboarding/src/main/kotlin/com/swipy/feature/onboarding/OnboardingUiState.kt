package com.swipy.feature.onboarding

data class OnboardingUiState(
    val currentStep: OnboardingStep = OnboardingStep.VisualHook,
    /** True after the user denies (or is restricted from) media access — swaps the Permission
     * step's CTA to a Settings deep link instead of re-prompting. */
    val isPermissionDenied: Boolean = false,
    /** Real counts once the scan completes; null beforehand (Scan step shows its "scanning"
     * pulsing-dots state per row until each count populates). Unlike iOS, Android has no
     * animation-in-progress vs settled distinction to track separately — MediaStore counts
     * resolve in one fast batch, so there's no "arrived after the screen appeared" race to
     * handle the way iOS's PHAsset-based scan has. */
    val scanCounts: ScanCountsUi? = null,
)

data class ScanCountsUi(
    val photoCount: Int,
    val videoCount: Int,
    val largeVideoCount: Int,
)
