package com.swipy.data.vision

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Loads a downsampled bitmap for blur/burst analysis — never full-resolution then scaled down
 * in memory, per android/CLAUDE.md's decode-time-downsampling rule (`BitmapFactory.Options
 * .inSampleSize`, computed from a bounds-only first pass). No network access is requested;
 * `ContentResolver.openInputStream` only ever serves what's already local. This is a smaller
 * platform gap than it looks — unlike iOS's PHAsset, which can represent an iCloud-only
 * placeholder that legitimately needs a network fetch, MediaStore on Android generally only
 * indexes files that already exist locally, so there's no real "offline analyzable" branch to
 * handle here the way iOS's `isNetworkAccessAllowed = false` guards against one.
 */
class AnalysisBitmapLoader @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    suspend fun loadForAnalysis(uriString: String, targetSize: Int = ANALYSIS_SIZE): Bitmap? =
        withContext(Dispatchers.IO) {
            runCatching {
                val uri = Uri.parse(uriString)

                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                context.contentResolver.openInputStream(uri)?.use {
                    BitmapFactory.decodeStream(it, null, bounds)
                }
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@runCatching null

                val decodeOptions = BitmapFactory.Options().apply {
                    inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, targetSize)
                }
                context.contentResolver.openInputStream(uri)?.use { stream ->
                    BitmapFactory.decodeStream(stream, null, decodeOptions)
                }
            }.getOrNull()
        }

    private fun calculateInSampleSize(width: Int, height: Int, targetSize: Int): Int {
        var sampleSize = 1
        var w = width
        var h = height
        while (w / 2 >= targetSize && h / 2 >= targetSize) {
            w /= 2
            h /= 2
            sampleSize *= 2
        }
        return sampleSize
    }

    companion object {
        /** Matches iOS BlurDetector's thumbnailSize (200x200). */
        const val ANALYSIS_SIZE = 200
    }
}
