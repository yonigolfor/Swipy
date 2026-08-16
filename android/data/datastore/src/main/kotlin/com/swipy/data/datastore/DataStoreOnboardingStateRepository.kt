package com.swipy.data.datastore

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import com.swipy.domain.repository.OnboardingStateRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class DataStoreOnboardingStateRepository @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) : OnboardingStateRepository {

    override val hasCompletedOnboarding: Flow<Boolean> =
        dataStore.data.map { it[HAS_COMPLETED_ONBOARDING] ?: false }

    override suspend fun setOnboardingCompleted() {
        dataStore.edit { it[HAS_COMPLETED_ONBOARDING] = true }
    }

    private companion object {
        val HAS_COMPLETED_ONBOARDING = booleanPreferencesKey("has_completed_onboarding")
    }
}
