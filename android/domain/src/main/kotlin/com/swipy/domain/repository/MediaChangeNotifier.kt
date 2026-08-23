package com.swipy.domain.repository

import kotlinx.coroutines.flow.Flow

/**
 * Signals that the device media library changed externally — the Android analogue of iOS's
 * `PHPhotoLibraryChangeObserver`. Kept in `:domain` (not `:data`) so consumers like
 * `:core:notifications` (photo-burst detection) can depend on it the same way they already
 * depend on [PhotoStateRepository], without a hard module dependency on the `:data:mediastore`
 * implementation — Hilt resolves the binding via the app-level aggregated graph.
 *
 * Emits one [Unit] per underlying change event with no debouncing — this is a pure signal
 * source; coalescing rapid-fire events (e.g. a bulk photo import) is each consumer's own
 * responsibility, since different consumers may want different windows.
 */
interface MediaChangeNotifier {
    fun observeChanges(): Flow<Unit>
}
