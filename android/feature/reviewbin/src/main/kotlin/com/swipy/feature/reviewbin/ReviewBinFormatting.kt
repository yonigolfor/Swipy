package com.swipy.feature.reviewbin

/** Port of iOS PhotoStackViewModel.formatBytes — same 1 MiB = 1_048_576 bytes divisor. */
internal fun formatSpaceSaved(bytes: Long): String {
    val megabytes = bytes / 1_048_576.0
    return if (megabytes < 1024) {
        "%.1f MB".format(megabytes)
    } else {
        "%.2f GB".format(megabytes / 1024)
    }
}

internal fun formatDuration(durationMs: Long): String {
    val totalSeconds = durationMs / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%d:%02d".format(minutes, seconds)
}
