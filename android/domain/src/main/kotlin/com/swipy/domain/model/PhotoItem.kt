package com.swipy.domain.model

/**
 * Every field is resolved eagerly by the repository at fetch time — never compute a field
 * lazily from a getter here. See android/CLAUDE.md "The Strict Equality / Stability Rule":
 * a data class's structural equals()/hashCode() must never trigger a ContentResolver query.
 *
 * [uriString] holds android.net.Uri's string form rather than the platform type itself —
 * :domain must compile without android.jar, so callers reconstruct the real Uri
 * (Uri.parse(uriString)) at the point of use in :data/:feature, where it's available.
 *
 * Every field here is a Compose-stable primitive/String on purpose — not just [id]/[uriString]
 * but also [dateAddedEpochSeconds] (a Long, not java.time.Instant): the Compose compiler's
 * default stability inference only recognizes a fixed set of "obviously stable" foreign
 * types, and a general JDK type like Instant isn't on it, which would silently make this
 * whole class infer as unstable — defeating CardStackLayer's skip-recomposition path (see
 * android/CLAUDE.md "Gesture Engine & Card Stack Performance") for a reason that's easy to
 * miss in review. Sticking to primitives here sidesteps that without needing an @Immutable
 * annotation (which would also mean pulling androidx.compose.runtime into this
 * android.jar-free module just for one annotation).
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
    val dateAddedEpochSeconds: Long,
)
