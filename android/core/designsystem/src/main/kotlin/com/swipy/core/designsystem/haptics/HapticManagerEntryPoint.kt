package com.swipy.core.designsystem.haptics

import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/** Lets a plain (non-Hilt-managed) Composable fetch the @Singleton HapticManager — same
 * pattern as :data:mediastore's VideoPlayerPoolEntryPoint. Unlike that one, the Compose-side
 * bridge ([rememberHapticManager]) lives right alongside this in the same module, since
 * :core:designsystem (unlike :data:mediastore) already has a Compose dependency. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface HapticManagerEntryPoint {
    fun hapticManager(): HapticManager
}
