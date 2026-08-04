package com.swipy.domain.model

import java.time.Instant

/**
 * Every field is resolved eagerly by the repository at fetch time — never compute a field
 * lazily from a getter here. See android/CLAUDE.md "The Strict Equality / Stability Rule":
 * a data class's structural equals()/hashCode() must never trigger a ContentResolver query.
 *
 * [uriString] holds android.net.Uri's string form rather than the platform type itself —
 * :domain must compile without android.jar, so callers reconstruct the real Uri
 * (Uri.parse(uriString)) at the point of use in :data/:feature, where it's available.
 */
data class PhotoItem(
    val id: Long,
    val uriString: String,
    val fileSizeBytes: Long,
    val mimeType: String,
    val isVideo: Boolean,
    val width: Int,
    val height: Int,
    val durationMs: Long,
    val dateAdded: Instant,
)
