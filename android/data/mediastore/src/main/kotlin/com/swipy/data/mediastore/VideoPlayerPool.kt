package com.swipy.data.mediastore

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Bounded pool of ExoPlayer instances — the direct Kotlin port of iOS's VideoPlayerPool. See
 * android/CLAUDE.md "Video via Media3 ExoPlayer, pooled". Players are paused, never released,
 * on navigation away from a video card so playback resumes instantly on return; [drainAll] is
 * reserved for right before a MediaStore delete/trash request (see "Deletion & Trash" — "Video
 * safety"), not called from ordinary navigation.
 *
 * Placement note: this lives in :data:mediastore (not a dedicated module) because both
 * :feature:swipe and :feature:reviewbin need it and neither can depend on the other (feature
 * modules are siblings, not allowed to depend on each other per the module dependency rule) —
 * :data:mediastore is the nearest shared dependency both already have. Revisit as a dedicated
 * :core:media/:data:video module if this pool grows real complexity beyond pooling.
 */
@Singleton
class VideoPlayerPool @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private data class PooledPlayer(val player: ExoPlayer, var uriString: String?, var lastUsedAtMs: Long)

    private val pool = mutableListOf<PooledPlayer>()

    /** Returns a player already prepared for [uriString], reusing a pooled instance by LRU. */
    @Synchronized
    fun playerFor(uriString: String): ExoPlayer {
        pool.find { it.uriString == uriString }?.let {
            it.lastUsedAtMs = System.currentTimeMillis()
            return it.player
        }

        val slot = if (pool.size < MAX_POOL_SIZE) {
            PooledPlayer(ExoPlayer.Builder(context).build(), null, 0L).also { pool += it }
        } else {
            pool.minBy { it.lastUsedAtMs }
        }

        slot.player.setMediaItem(MediaItem.fromUri(uriString))
        slot.player.prepare()
        slot.uriString = uriString
        slot.lastUsedAtMs = System.currentTimeMillis()
        return slot.player
    }

    @Synchronized
    fun pauseAll() {
        pool.forEach { it.player.pause() }
    }

    /** Releases every pooled player — call only right before a delete/trash request. */
    @Synchronized
    fun drainAll() {
        pool.forEach { it.player.release() }
        pool.clear()
    }

    private companion object {
        const val MAX_POOL_SIZE = 3
    }
}
