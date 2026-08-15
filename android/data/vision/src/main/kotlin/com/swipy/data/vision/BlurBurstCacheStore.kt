@file:OptIn(kotlinx.coroutines.FlowPreview::class)

package com.swipy.data.vision

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Disk-backed cache of blur verdicts + perceptual hashes keyed by MediaStore row id — the
 * Android port of iOS's BlurBurstCacheService/DebouncedJSONStore. A verdict/hash, once
 * computed, is stable for the asset's lifetime, so it's only computed once. Split into two
 * separate DataStore instances (not just two keys in one) for the same reason iOS splits into
 * two files: a small verdict write must never force re-encoding the much larger, separately-
 * growing hash blob, and vice versa — Preferences DataStore's `edit {}` persists the whole
 * file on every call, so two keys in one instance would still pay that cost.
 *
 * Writes are debounced ~2s after the last mutation (via `MutableSharedFlow.debounce`, per
 * android/CLAUDE.md's documented plan for this exact port) instead of a Proto DataStore with a
 * hand-rolled schema — this project's actual established pattern for small cached maps is a
 * JSON-encoded Preferences DataStore blob (see DataStoreCategoryCountCacheRepository), and
 * introducing a new Proto DataStore/protobuf toolchain for one cache isn't worth the deviation.
 */
@Singleton
class BlurBurstCacheStore @Inject constructor(
    @BlurVerdictsStore private val verdictsDataStore: DataStore<Preferences>,
    @ImageHashesStore private val hashesDataStore: DataStore<Preferences>,
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()

    private var verdicts: MutableMap<Long, Boolean> = mutableMapOf()
    private var hashes: MutableMap<Long, Long> = mutableMapOf()
    private var loaded = false

    private val verdictsDirty = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private val hashesDirty = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    init {
        scope.launch { verdictsDirty.debounce(DEBOUNCE_MS).collect { persistVerdicts() } }
        scope.launch { hashesDirty.debounce(DEBOUNCE_MS).collect { persistHashes() } }
    }

    suspend fun blurVerdict(id: Long): Boolean? {
        ensureLoaded()
        return lock.withLock { verdicts[id] }
    }

    suspend fun setBlurVerdict(id: Long, isBlurry: Boolean) {
        ensureLoaded()
        lock.withLock { verdicts[id] = isBlurry }
        verdictsDirty.tryEmit(Unit)
    }

    suspend fun imageHash(id: Long): Long? {
        ensureLoaded()
        return lock.withLock { hashes[id] }
    }

    suspend fun setImageHash(id: Long, hash: Long) {
        ensureLoaded()
        lock.withLock { hashes[id] = hash }
        hashesDirty.tryEmit(Unit)
    }

    suspend fun invalidate(ids: Set<Long>) {
        if (ids.isEmpty()) return
        ensureLoaded()
        lock.withLock {
            ids.forEach {
                verdicts.remove(it)
                hashes.remove(it)
            }
        }
        verdictsDirty.tryEmit(Unit)
        hashesDirty.tryEmit(Unit)
    }

    private suspend fun ensureLoaded() {
        if (loaded) return
        lock.withLock {
            if (loaded) return
            verdictsDataStore.data.first()[VERDICTS_KEY]?.let {
                verdicts = json.decodeFromString<Map<Long, Boolean>>(it).toMutableMap()
            }
            hashesDataStore.data.first()[HASHES_KEY]?.let {
                hashes = json.decodeFromString<Map<Long, Long>>(it).toMutableMap()
            }
            loaded = true
        }
    }

    private suspend fun persistVerdicts() {
        val snapshot = lock.withLock { verdicts.toMap() }
        verdictsDataStore.edit { it[VERDICTS_KEY] = json.encodeToString(snapshot) }
    }

    private suspend fun persistHashes() {
        val snapshot = lock.withLock { hashes.toMap() }
        hashesDataStore.edit { it[HASHES_KEY] = json.encodeToString(snapshot) }
    }

    private companion object {
        const val DEBOUNCE_MS = 2000L
        val VERDICTS_KEY = stringPreferencesKey("blur_verdicts")
        val HASHES_KEY = stringPreferencesKey("image_hashes")
    }
}
