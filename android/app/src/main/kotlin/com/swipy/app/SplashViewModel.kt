package com.swipy.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.domain.repository.OnboardingStateRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

/** Small enough to not warrant its own :feature module — just exposes the one flag AppRoot
 * needs to route between OnboardingScreen and the main SwipyNavHost. Null means "DataStore
 * hasn't delivered its first value yet", not "false" — AppRoot treats it as "keep waiting"
 * rather than momentarily flashing the onboarding flow for a returning user. */
@HiltViewModel
class SplashViewModel @Inject constructor(
    onboardingStateRepository: OnboardingStateRepository,
) : ViewModel() {
    val hasCompletedOnboarding: StateFlow<Boolean?> =
        onboardingStateRepository.hasCompletedOnboarding
            .stateIn(viewModelScope, SharingStarted.Eagerly, null)
}
