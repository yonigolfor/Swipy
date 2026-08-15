package com.swipy.data.vision

import android.graphics.Bitmap

/**
 * Difference hash (dHash) perceptual similarity — the honest Android substitute for iOS
 * BurstAnalyzer's `VNGenerateImageFeaturePrintRequest` (a deep-learning embedding with no
 * on-device Android equivalent outside ML Kit, which this project deliberately doesn't use —
 * see android/CLAUDE.md Core Tech Stack). dHash is a well-known, dependency-free near-duplicate-
 * image technique: downsample to 9x8 grayscale, hash = 1 bit per pixel for "brighter than its
 * right neighbor", giving exactly 64 bits.
 *
 * This is a real capability gap, not just a tuning difference: dHash captures coarse structural
 * similarity (composition/brightness pattern), not semantic content similarity, so it will
 * disagree with what Vision's feature print would judge on genuinely hard cases (same framing,
 * different subject expression or lighting flicker across a burst). It's presented here as
 * "good enough to flag near-identical burst shots," not as equivalent accuracy.
 */
object ImageHasher {
    private const val HASH_WIDTH = 9
    private const val HASH_HEIGHT = 8

    /** Packs the 64 pairwise brightness comparisons into a Long, one bit each. */
    fun computeHash(bitmap: Bitmap): Long {
        val scaled = Bitmap.createScaledBitmap(bitmap, HASH_WIDTH, HASH_HEIGHT, true)
        var hash = 0L
        var bit = 0
        for (y in 0 until HASH_HEIGHT) {
            for (x in 0 until HASH_WIDTH - 1) {
                val left = luminance(scaled.getPixel(x, y))
                val right = luminance(scaled.getPixel(x + 1, y))
                if (left > right) hash = hash or (1L shl bit)
                bit++
            }
        }
        if (scaled !== bitmap) scaled.recycle()
        return hash
    }

    /** Normalized Hamming distance in [0, 1] — 0 = identical, 1 = maximally different; the
     *  same [0,1) shape as iOS's `computeDistance`/`visualDistanceThreshold`, even though the
     *  two metrics aren't numerically equivalent (see class doc). */
    fun normalizedDistance(a: Long, b: Long): Float =
        java.lang.Long.bitCount(a xor b) / 64f

    private fun luminance(pixel: Int): Int {
        val r = (pixel shr 16) and 0xFF
        val g = (pixel shr 8) and 0xFF
        val b = pixel and 0xFF
        return (r + g + b) / 3
    }
}
