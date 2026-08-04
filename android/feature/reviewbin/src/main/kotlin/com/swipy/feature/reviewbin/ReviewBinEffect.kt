package com.swipy.feature.reviewbin

import android.app.PendingIntent

sealed interface ReviewBinEffect {
    data class LaunchDeleteConfirmation(val pendingIntent: PendingIntent) : ReviewBinEffect
    data object ReviewBinEmpty : ReviewBinEffect
}
