package com.swipy.data.datastore

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.swipy.domain.model.FilterCategory
import com.swipy.domain.repository.CategoryCountCacheRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Stored as `Map<String, Int>` (enum name -> count) rather than a serialized
 * `Map<FilterCategory, Int>` directly — :domain has no kotlinx-serialization dependency
 * (FilterCategory carries no @Serializable annotation), so the String<->FilterCategory
 * mapping happens entirely in this data-layer class.
 */
class DataStoreCategoryCountCacheRepository @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) : CategoryCountCacheRepository {

    override val cachedCounts: Flow<Map<FilterCategory, Int>> = dataStore.data.map { prefs ->
        val raw = prefs[CATEGORY_COUNTS]?.let { json.decodeFromString<Map<String, Int>>(it) } ?: emptyMap()
        raw.mapNotNull { (name, count) ->
            FilterCategory.entries.find { it.name == name }?.let { it to count }
        }.toMap()
    }

    override suspend fun saveCounts(counts: Map<FilterCategory, Int>) {
        dataStore.edit { prefs ->
            prefs[CATEGORY_COUNTS] = json.encodeToString(counts.mapKeys { it.key.name })
        }
    }

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
        val CATEGORY_COUNTS = stringPreferencesKey("category_counts")
    }
}
