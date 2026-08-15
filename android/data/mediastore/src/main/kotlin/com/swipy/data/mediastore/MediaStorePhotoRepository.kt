package com.swipy.data.mediastore

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.repository.PhotoRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * See android/CLAUDE.md "MediaStore Querying — Pagination & Performance": queries only the
 * columns actually needed, treats the Cursor as a lazy one-directional walk (never reads
 * cursor.count to eagerly materialize a full result set outside the capped count path
 * below), and never holds a Cursor open longer than the single fetch.
 */
class MediaStorePhotoRepository @Inject constructor(
    @ApplicationContext private val context: Context,
) : PhotoRepository {

    private val collectionUri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)

    private val pageProjection = arrayOf(
        MediaStore.Files.FileColumns._ID,
        MediaStore.Files.FileColumns.MEDIA_TYPE,
        MediaStore.Files.FileColumns.SIZE,
        MediaStore.Files.FileColumns.MIME_TYPE,
        MediaStore.Files.FileColumns.WIDTH,
        MediaStore.Files.FileColumns.HEIGHT,
        MediaStore.Files.FileColumns.DURATION,
        MediaStore.Files.FileColumns.DATE_ADDED,
    )

    override suspend fun fetchPage(
        filter: FilterCategory,
        offset: Int,
        limit: Int,
    ): List<PhotoItem> = withContext(Dispatchers.IO) {
        val spec = MediaStoreQueryBuilder.forCategory(filter)
        val sortColumn = MediaStore.Files.FileColumns.DATE_ADDED

        val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val args = Bundle().apply {
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, spec.selection)
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, spec.selectionArgs)
                putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, "$sortColumn DESC")
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
            }
            context.contentResolver.query(collectionUri, pageProjection, args, null)
        } else {
            // API 29 predates Bundle-based LIMIT/OFFSET query args (added in API 30) —
            // fall back to the raw SQL sortOrder string trick.
            val sortOrder = "$sortColumn DESC LIMIT $limit OFFSET $offset"
            context.contentResolver.query(
                collectionUri,
                pageProjection,
                spec.selection,
                spec.selectionArgs,
                sortOrder,
            )
        }

        cursor?.use(::readPhotoItems) ?: emptyList()
    }

    override suspend fun fetchByIds(ids: List<Long>): List<PhotoItem> = withContext(Dispatchers.IO) {
        if (ids.isEmpty()) return@withContext emptyList()

        val placeholders = ids.joinToString(",") { "?" }
        val selection = "${MediaStore.Files.FileColumns._ID} IN ($placeholders)"
        val selectionArgs = ids.map { it.toString() }.toTypedArray()

        val cursor = context.contentResolver.query(collectionUri, pageProjection, selection, selectionArgs, null)
        cursor?.use(::readPhotoItems) ?: emptyList()
    }

    private fun readPhotoItems(c: android.database.Cursor): List<PhotoItem> {
        val idCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
        val mediaTypeCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MEDIA_TYPE)
        val sizeCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
        val mimeCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)
        val widthCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.WIDTH)
        val heightCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.HEIGHT)
        val durationCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DURATION)
        val dateAddedCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_ADDED)

        val items = mutableListOf<PhotoItem>()
        while (c.moveToNext()) {
            val id = c.getLong(idCol)
            items += PhotoItem(
                id = id,
                uriString = ContentUris.withAppendedId(collectionUri, id).toString(),
                fileSizeBytes = c.getLong(sizeCol),
                mimeType = c.getString(mimeCol) ?: "",
                isVideo = c.getInt(mediaTypeCol) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO,
                width = c.getInt(widthCol),
                height = c.getInt(heightCol),
                durationMs = c.getLong(durationCol),
                // MediaStore's DATE_ADDED is epoch SECONDS (DATE_TAKEN, notoriously, is
                // milliseconds instead) — do not treat this value as epoch millis.
                dateAddedEpochSeconds = c.getLong(dateAddedCol),
            )
        }
        return items
    }

    override suspend fun countForCategory(
        filter: FilterCategory,
        cap: Int,
        excludedIds: Set<Long>,
    ): Int = withContext(Dispatchers.IO) {
        val spec = MediaStoreQueryBuilder.forCategory(filter)

        if (excludedIds.isEmpty()) {
            // Fast path — MediaStore's ContentProvider exposes no aggregate COUNT(*), so the
            // cheapest cap-respecting count is a single LIMIT-bounded id-only cursor.
            val cursor = queryIdBatch(spec, offset = 0, limit = cap)
            return@withContext cursor.size
        }

        // Exclusion-aware path — walk in bounded batches, skipping already-swiped ids, until
        // `cap` real matches are found or the result set is exhausted. Never an unbounded walk:
        // each batch is itself LIMIT-bounded, same convention as fetchPage.
        var offset = 0
        var matched = 0
        val batchSize = cap.coerceAtLeast(1) * 2
        while (matched < cap) {
            val batchIds = queryIdBatch(spec, offset, batchSize)
            if (batchIds.isEmpty()) break
            matched += batchIds.count { it !in excludedIds }
            offset += batchIds.size
        }
        matched.coerceAtMost(cap)
    }

    /** Id-only cursor walk, reused by [countForCategory]'s exclusion-aware batching. */
    private fun queryIdBatch(spec: MediaStoreQuerySpec, offset: Int, limit: Int): List<Long> {
        val idOnlyProjection = arrayOf(MediaStore.Files.FileColumns._ID)
        val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val args = Bundle().apply {
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, spec.selection)
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, spec.selectionArgs)
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
            }
            context.contentResolver.query(collectionUri, idOnlyProjection, args, null)
        } else {
            val sortOrder = "${MediaStore.Files.FileColumns.DATE_ADDED} DESC LIMIT $limit OFFSET $offset"
            context.contentResolver.query(collectionUri, idOnlyProjection, spec.selection, spec.selectionArgs, sortOrder)
        }

        return cursor?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            buildList { while (c.moveToNext()) add(c.getLong(idCol)) }
        } ?: emptyList()
    }

    override suspend fun totalCount(filter: FilterCategory): Int = withContext(Dispatchers.IO) {
        val spec = MediaStoreQueryBuilder.forCategory(filter)
        val idOnlyProjection = arrayOf(MediaStore.Files.FileColumns._ID)
        context.contentResolver
            .query(collectionUri, idOnlyProjection, spec.selection, spec.selectionArgs, null)
            ?.use { it.count } ?: 0
    }
}
