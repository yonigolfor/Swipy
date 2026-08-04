package com.swipy.feature.swipe

import android.app.PendingIntent

/** One-shot events — never modeled as state. See android/CLAUDE.md "Architecture". */
sealed interface PhotoStackEffect {
    data class LaunchDeleteConfirmation(val pendingIntent: PendingIntent) : PhotoStackEffect
    data object NothingToUndo : PhotoStackEffect
    data object ReviewBinEmpty : PhotoStackEffect
}
