package com.swipy.data.vision

import android.graphics.Bitmap

/**
 * Variance-of-Laplacian blur detection — the classical, well-documented technique (the same
 * family OpenCV's `cv2.Laplacian().var()` recipe uses). This is a deliberate, honest substitute
 * for iOS BlurDetector's CIEdges+CIPhotoEffectMono pipeline, not a literal port: Android has no
 * CoreImage-equivalent edge filter without RenderScript (deprecated, removed API 31+) or a
 * third-party CV library (rejected — zero third-party dependencies, see android/CLAUDE.md).
 *
 * [BLURRY_THRESHOLD] is NOT iOS's calibrated value (300.0, tuned against real photos through
 * CIEdges) — a different edge algorithm produces variance on a different scale entirely.
 * 100.0 is a reasonable starting point from the well-known variance-of-Laplacian literature
 * range, not device-calibrated against this app's own library the way iOS's constant was.
 * Needs real on-device tuning against a labeled photo set before shipping — flagged here
 * explicitly rather than presented as already-correct.
 */
object BlurDetector {
    const val BLURRY_THRESHOLD = 100.0

    fun isBlurry(bitmap: Bitmap, threshold: Double = BLURRY_THRESHOLD): Boolean =
        laplacianVariance(bitmap) < threshold

    /**
     * 3x3 Laplacian kernel [0,1,0; 1,-4,1; 0,1,0] applied to luminance, variance of the
     * response. High variance = many sharp edges = in focus; low variance = blurry.
     */
    fun laplacianVariance(bitmap: Bitmap): Double {
        val width = bitmap.width
        val height = bitmap.height
        if (width < 3 || height < 3) return Double.MAX_VALUE

        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        // Rec. 601 luma — matches the perceptual weighting CIPhotoEffectMono-style
        // grayscale conversion targets, avoiding color-edge noise inflating variance.
        val luma = DoubleArray(width * height) { i ->
            val p = pixels[i]
            0.299 * ((p shr 16) and 0xFF) + 0.587 * ((p shr 8) and 0xFF) + 0.114 * (p and 0xFF)
        }

        var sum = 0.0
        var sumSquared = 0.0
        var count = 0
        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                val idx = y * width + x
                val response = -4 * luma[idx] +
                    luma[idx - 1] + luma[idx + 1] +
                    luma[idx - width] + luma[idx + width]
                sum += response
                sumSquared += response * response
                count++
            }
        }
        if (count == 0) return Double.MAX_VALUE
        val mean = sum / count
        return (sumSquared / count) - mean * mean
    }
}
