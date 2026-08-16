package com.swipy.core.designsystem.haptics

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import dagger.hilt.android.EntryPointAccessors

/** Standard Hilt EntryPointAccessors bridge for reaching the @Singleton HapticManager from a
 * plain Composable — see rememberVideoPlayerPool() in :feature:swipe for the precedent this
 * mirrors. */
@Composable
fun rememberHapticManager(): HapticManager {
    val appContext = LocalContext.current.applicationContext
    return remember {
        EntryPointAccessors.fromApplication(appContext, HapticManagerEntryPoint::class.java).hapticManager()
    }
}
