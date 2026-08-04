package com.swipy.feature.swipe

/** One-shot events — never modeled as state. See android/CLAUDE.md "Architecture". */
sealed interface PhotoStackEffect {
    data object NothingToUndo : PhotoStackEffect
}
