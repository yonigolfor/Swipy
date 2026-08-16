package com.swipy.core.designsystem.theme

import androidx.compose.ui.graphics.Color

// Ported 1:1 from the iOS palette (View+Extensions.swift / FilterCategory.swift) — see
// android/CLAUDE.md "Color Palette". Do not invent a Material-default palette here.

// Swipe Action Colors
val SwipeGreen = Color(0xFF33CC66) // keep
val SwipeRed = Color(0xFFF24D4D) // delete
val SwipeBlue = Color(0xFF408CF2) // snooze ("Later")
val SwipeYellow = Color(0xFFFFCC33) // celebration particles only

// Filter Category Colors
val FilterAll = Color(0xFF9E9E9E)
val FilterScreenshots = Color(0xFF2196F3)
val FilterScreenRecordings = Color(0xFF9C27B0)
val FilterLargeVideos = Color(0xFFFF9800)
val FilterBlurryPhotos = Color(0xFFF44336)
val FilterBurstPhotos = Color(0xFF00BCD4)

// Shuffle Accent Gradient (Phase 2 chrome will consume this too — defined now since the
// savings bar's own gradients already establish the module's color-token pattern)
val ShuffleAccentStart = Color(0xFF3380FF)
val ShuffleAccentEnd = Color(0xFF8033E6)

// Savings Bar — progress track gradient (SessionSavingsBarView.swift progressSection)
val SavingsBarGradientStart = Color(0xFF4DA6FF)
val SavingsBarGradientEnd = Color(0xFF8C4DF2)

// Savings Bar — lava-star fill gradient (SessionSavingsBarView.swift starSection)
val LavaGradientBottom = Color(0xFFFFB700)
val LavaGradientTop = Color(0xFFFFE026)

// Onboarding — dark premium background + gold CTA gradient (OnboardingView.swift, matches
// SplashScreenView's own background exactly). Other onboarding accent colors (lock icon blue,
// checkmark green, scan-row blue/purple/orange) deliberately reuse the tokens above
// (FilterScreenshots, FilterScreenRecordings, FilterLargeVideos, SwipeGreen) rather than adding
// near-duplicate near-identical hex values — only the two colors with no existing analogue
// (background, gold) are new.
val OnboardingBackground = Color(0xFF14141A) // rgb(0.08, 0.08, 0.10)
val OnboardingGoldStart = Color(0xFFFFD94D) // rgb(1, 0.85, 0.3)
val OnboardingGoldEnd = Color(0xFFFFA61A) // rgb(1, 0.65, 0.1)
val OnboardingGoldShadow = Color(0xFFFFB333) // rgb(1, 0.7, 0.2)
