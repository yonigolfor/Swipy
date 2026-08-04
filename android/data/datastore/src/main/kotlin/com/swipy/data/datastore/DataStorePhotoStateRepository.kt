package com.swipy.data.datastore

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import com.swipy.domain.repository.PhotoStateRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class DataStorePhotoStateRepository @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) : PhotoStateRepository {

    override val keptPhotoIds: Flow<Set<Long>> = dataStore.data.map { prefs ->
        prefs[KEPT_PHOTO_IDS].orEmpty().mapNotNullTo(mutableSetOf()) { it.toLongOrNull() }
    }

    override suspend fun markKept(id: Long) {
        dataStore.edit { prefs ->
            prefs[KEPT_PHOTO_IDS] = prefs[KEPT_PHOTO_IDS].orEmpty() + id.toString()
        }
    }

    override val reviewBinIds: Flow<List<Long>> = dataStore.data.map { it.reviewBinIds() }

    override val reviewBinFileSizes: Flow<Map<Long, Long>> = dataStore.data.map { it.reviewBinFileSizes() }

    override val reviewBinSpaceSaved: Flow<Long> = reviewBinFileSizes.map { it.values.sum() }

    override val totalSpaceSavedLifetime: Flow<Long> = dataStore.data.map { prefs ->
        prefs[TOTAL_SPACE_SAVED_LIFETIME] ?: 0L
    }

    override suspend fun addToReviewBin(id: Long, fileSizeBytes: Long) {
        dataStore.edit { prefs ->
            val ids = prefs.reviewBinIds()
            if (id !in ids) {
                prefs[REVIEW_BIN_IDS] = json.encodeToString(ids + id)
            }
            prefs[REVIEW_BIN_FILE_SIZES] = json.encodeToString(prefs.reviewBinFileSizes() + (id to fileSizeBytes))
        }
    }

    override suspend fun restoreFromReviewBin(id: Long) {
        dataStore.edit { prefs ->
            prefs[REVIEW_BIN_IDS] = json.encodeToString(prefs.reviewBinIds() - id)
            prefs[REVIEW_BIN_FILE_SIZES] = json.encodeToString(prefs.reviewBinFileSizes() - id)
        }
    }

    override suspend fun emptyReviewBin() {
        dataStore.edit { prefs ->
            val freedBytes = prefs.reviewBinFileSizes().values.sum()
            prefs[TOTAL_SPACE_SAVED_LIFETIME] = (prefs[TOTAL_SPACE_SAVED_LIFETIME] ?: 0L) + freedBytes
            prefs[REVIEW_BIN_IDS] = json.encodeToString(emptyList<Long>())
            prefs[REVIEW_BIN_FILE_SIZES] = json.encodeToString(emptyMap<Long, Long>())
        }
    }

    override val snoozedPhotos: Flow<Map<Long, Int>> = dataStore.data.map { it.snoozedPhotos() }

    override suspend fun snoozePhoto(id: Long, count: Int) {
        dataStore.edit { prefs ->
            prefs[SNOOZED_PHOTOS] = json.encodeToString(prefs.snoozedPhotos() + (id to count))
        }
    }

    override suspend fun clearSnooze(id: Long) {
        dataStore.edit { prefs ->
            prefs[SNOOZED_PHOTOS] = json.encodeToString(prefs.snoozedPhotos() - id)
        }
    }

    private fun Preferences.reviewBinIds(): List<Long> =
        this[REVIEW_BIN_IDS]?.let { json.decodeFromString(it) } ?: emptyList()

    private fun Preferences.reviewBinFileSizes(): Map<Long, Long> =
        this[REVIEW_BIN_FILE_SIZES]?.let { json.decodeFromString(it) } ?: emptyMap()

    private fun Preferences.snoozedPhotos(): Map<Long, Int> =
        this[SNOOZED_PHOTOS]?.let { json.decodeFromString(it) } ?: emptyMap()

    private companion object {
        val json = Json { ignoreUnknownKeys = true }

        val KEPT_PHOTO_IDS = stringSetPreferencesKey("kept_photo_ids")
        val REVIEW_BIN_IDS = stringPreferencesKey("review_bin_ids")
        val REVIEW_BIN_FILE_SIZES = stringPreferencesKey("review_bin_file_sizes")
        val TOTAL_SPACE_SAVED_LIFETIME = longPreferencesKey("total_space_saved_lifetime")
        val SNOOZED_PHOTOS = stringPreferencesKey("snoozed_photos")
    }
}
