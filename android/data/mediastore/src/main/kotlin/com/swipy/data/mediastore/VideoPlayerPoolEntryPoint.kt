package com.swipy.data.mediastore

import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Lets a plain (non-Hilt-managed) Composable fetch the @Singleton VideoPlayerPool — the
 * standard Hilt pattern for injecting into something that isn't a ViewModel/Activity/Fragment.
 * The Compose-side `rememberVideoPlayerPool()` helper that uses this lives in :feature:swipe
 * (this module has no Compose dependency).
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface VideoPlayerPoolEntryPoint {
    fun videoPlayerPool(): VideoPlayerPool
}
