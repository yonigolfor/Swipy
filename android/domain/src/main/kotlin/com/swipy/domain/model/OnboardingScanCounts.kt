package com.swipy.domain.model

/** Real (not estimated) counts for the onboarding Scan step. Unlike iOS's `duration > 10`
 * quick-estimate proxy for the large-video counter (a workaround for PHAsset.fileSize needing
 * per-asset PHAssetResource inspection), Android needs no such shortcut — MediaStore's SIZE
 * column is already exact and index-queryable, so [largeVideoCount] is a real count from the
 * start, not a refined-in-place estimate. */
data class OnboardingScanCounts(
    val photoCount: Int,
    val videoCount: Int,
    val largeVideoCount: Int,
)
