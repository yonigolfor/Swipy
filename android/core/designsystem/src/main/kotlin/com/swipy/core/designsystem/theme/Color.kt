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
