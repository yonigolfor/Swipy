package com.swipy.feature.swipe

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.swipy.data.mediastore.VideoPlayerPool
import com.swipy.data.mediastore.VideoPlayerPoolEntryPoint
import dagger.hilt.android.EntryPointAccessors

/**
 * VideoPlayerPool is a @Singleton Hilt binding, not a ViewModel — EntryPointAccessors is the
 * standard Hilt mechanism for reaching a Hilt-managed singleton from a plain Composable. See
 * VideoPlayerPoolEntryPoint (:data:mediastore) for why the interface itself lives there.
 */
@Composable
fun rememberVideoPlayerPool(): VideoPlayerPool {
    val appContext = LocalContext.current.applicationContext
    return remember {
        EntryPointAccessors.fromApplication(appContext, VideoPlayerPoolEntryPoint::class.java).videoPlayerPool()
    }
}
