package com.swipy.feature.reviewbin

import android.app.PendingIntent

sealed interface ReviewBinEffect {
    data class LaunchDeleteConfirmation(val pendingIntent: PendingIntent) : ReviewBinEffect

    /** Permanent deletion succeeded — the screen shows the Trash Celebration overlay. */
    data class EmptyTrashCompleted(val spaceSavedBytes: Long, val itemCount: Int) : ReviewBinEffect
}
