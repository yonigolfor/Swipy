package com.swipy.data.mediastore

import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Builds the PendingIntent(s) for permanently deleting Review Bin contents — see
 * android/CLAUDE.md "Deletion & Trash — Scoped Storage Compliance". This is deliberately a
 * plain class, not exposed through the :domain PhotoRepository interface: PendingIntent is an
 * Android-only type with no pure-Kotlin equivalent, and launching it requires an Activity
 * (rememberLauncherForActivityResult), so this is inherently UI-layer-coupled — callers inject
 * it directly, the same way iOS's equivalent flow lives at the ViewModel/UI boundary, not in a
 * platform-agnostic service.
 */
class MediaStoreDeletionRequests @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val filesCollectionUri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)

    /**
     * MediaStore.createDeleteRequest/RecoverableSecurityException both reject the generic
     * Files collection URI (content://media/external/file/<id>) that PhotoRepository's own
     * fetch path uses for reads — ContentResolver.openInputStream doesn't care, but the
     * delete-request system APIs strictly validate collection membership and throw
     * "All requested items must be Media items" otherwise (found by actually exercising this
     * on-device, not in docs). Deletion needs the type-specific Images/Video collection URI,
     * which requires knowing each id's media type — hence the query here.
     */
    private suspend fun typedUriFor(id: Long): Uri = withContext(Dispatchers.IO) {
        val isVideo = context.contentResolver.query(
            filesCollectionUri,
            arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE),
            "${MediaStore.Files.FileColumns._ID} = ?",
            arrayOf(id.toString()),
            null,
        )?.use { cursor ->
            cursor.moveToFirst() &&
                cursor.getInt(0) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
        } ?: false

        val typedCollection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        ContentUris.withAppendedId(typedCollection, id)
    }

    /**
     * API 30+ only — a single confirmation dialog covers every id in [ids]. Always call this
     * with the full Review Bin contents at once; never loop it per item.
     */
    @RequiresApi(Build.VERSION_CODES.R)
    suspend fun createBatchDeleteRequest(ids: List<Long>): PendingIntent {
        val uris = ids.map { typedUriFor(it) }
        return withContext(Dispatchers.IO) {
            MediaStore.createDeleteRequest(context.contentResolver, uris)
        }
    }

    /**
     * API 29 fallback — createDeleteRequest doesn't exist yet, and Scoped Storage on 29
     * requires a *separate* system confirmation per foreign-app item (RecoverableSecurityException),
     * not one batched dialog. Attempts a direct delete; returns the recovery PendingIntent if
     * the system requires confirmation, or null if the delete already succeeded outright.
     *
     * Given API 29's shrinking real-world share, this deliberately does not chain multiple
     * per-item confirmations automatically — it surfaces one at a time, and the caller
     * (ViewModel) re-invokes emptyReviewBin for any remaining ids after each confirmation
     * returns, rather than this class queuing a multi-step sequence itself.
     */
    suspend fun deleteOrGetRecoveryIntent(id: Long): PendingIntent? {
        val uri = typedUriFor(id)
        return withContext(Dispatchers.IO) {
            try {
                context.contentResolver.delete(uri, null, null)
                null
            } catch (e: RecoverableSecurityException) {
                e.userAction.actionIntent
            }
        }
    }
}
