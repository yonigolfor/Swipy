package com.swipy.feature.onboarding

/**
 * Display order, not iOS's `currentStep` case-number scheme — iOS's cases jump around
 * (0->3->2->5->1->4) purely as an artifact of incremental feature history (see
 * ONBOARDING.md "Display Order" table); there's no reason to replicate that confusion here
 * when a plain ordered enum expresses the exact same 6-step flow more clearly.
 */
enum class OnboardingStep {
    VisualHook,
    Permission,
    SwipeDemo,
    SnoozeIntro,
    Scan,
    QuickWin,
}
