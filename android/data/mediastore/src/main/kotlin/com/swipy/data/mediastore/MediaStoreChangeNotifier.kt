package com.swipy.data.mediastore

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.swipy.domain.repository.MediaChangeNotifier
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * Registers a single [ContentObserver] on the same collection [MediaStorePhotoRepository]
 * itself queries (`MediaStore.Files`, external volume) — this collection already receives a
 * change notification for image/video inserts, updates, and deletes, so no separate
 * Images/Video collection registration is needed.
 */
class MediaStoreChangeNotifier @Inject constructor(
    @ApplicationContext private val context: Context,
) : MediaChangeNotifier {

    override fun observeChanges(): Flow<Unit> = callbackFlow {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                trySend(Unit)
            }
        }
        context.contentResolver.registerContentObserver(
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL),
            true,
            observer,
        )
        awaitClose { context.contentResolver.unregisterContentObserver(observer) }
    }
}
