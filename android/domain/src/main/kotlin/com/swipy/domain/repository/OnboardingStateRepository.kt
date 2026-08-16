package com.swipy.domain.repository

import kotlinx.coroutines.flow.Flow

/**
 * Persisted onboarding-completion flag — the Android analogue of iOS's
 * `@AppStorage("hasCompletedOnboarding")`. A single boolean, backed by Preferences DataStore
 * (see android/CLAUDE.md "Persistence").
 */
interface OnboardingStateRepository {
    val hasCompletedOnboarding: Flow<Boolean>
    suspend fun setOnboardingCompleted()
}
