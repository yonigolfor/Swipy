package com.swipy.feature.onboarding

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.domain.repository.OnboardingStateRepository
import com.swipy.domain.usecase.ScanLibraryForOnboardingUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * MVI ViewModel for the 6-step onboarding flow — the Android port of iOS OnboardingView's
 * `currentStep`-driven state machine. See android/CLAUDE.md "Architecture" for why a single
 * immutable UiState + sealed Intent/Effect beats several independent StateFlows here too.
 */
@HiltViewModel
class OnboardingViewModel @Inject constructor(
    private val scanLibraryForOnboardingUseCase: ScanLibraryForOnboardingUseCase,
    private val onboardingStateRepository: OnboardingStateRepository,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    // Restores the in-progress step across process death (not just rotation, which the
    // ViewModel already survives on its own) — most likely to matter for exactly the step
    // that requires backgrounding to Settings and back (RecheckPermissionOnResume), the
    // scenario most likely to get the process reclaimed.
    private val _uiState = MutableStateFlow(
        OnboardingUiState(
            currentStep = savedStateHandle.get<String>(KEY_CURRENT_STEP)
                ?.let { runCatching { OnboardingStep.valueOf(it) }.getOrNull() }
                ?: OnboardingStep.VisualHook,
        ),
    )
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()

    private val _effects = Channel<OnboardingEffect>(Channel.BUFFERED)
    val effects = _effects.receiveAsFlow()

    fun onIntent(intent: OnboardingIntent) {
        when (intent) {
            OnboardingIntent.StartFromHook -> goTo(OnboardingStep.Permission)
            OnboardingIntent.RequestPermission -> _effects.trySend(OnboardingEffect.LaunchPermissionRequest)
            is OnboardingIntent.PermissionResult -> handlePermissionResult(intent.granted)
            is OnboardingIntent.RecheckPermissionOnResume -> handleResumeRecheck(intent.granted)
            OnboardingIntent.OpenSettings -> _effects.trySend(OnboardingEffect.OpenAppSettings)
            OnboardingIntent.NextFromDemo -> goTo(OnboardingStep.SnoozeIntro)
            OnboardingIntent.NextFromSnoozeIntro -> goTo(OnboardingStep.Scan)
            OnboardingIntent.NextFromScan -> goTo(OnboardingStep.QuickWin)
            OnboardingIntent.Complete -> viewModelScope.launch { onboardingStateRepository.setOnboardingCompleted() }
        }
    }

    /** Grant -> advance to the Swipe Demo immediately, scan runs in the background so real
     * counts are ready by the time the user reaches the Scan step (mirrors iOS exactly —
     * `requestPermission()`'s `.authorized/.limited` branch, PhotoStackViewModel.swift:872-881).
     * Deny/restricted -> stay on Permission, flip [OnboardingUiState.isPermissionDenied]. */
    private fun handlePermissionResult(granted: Boolean) {
        if (granted) {
            goTo(OnboardingStep.SwipeDemo)
            _uiState.update { it.copy(isPermissionDenied = false) }
            startBackgroundScan()
        } else {
            _uiState.update { it.copy(isPermissionDenied = true) }
        }
    }

    /** Silent recovery when the user grants access from Settings and returns — the direct
     * analogue of iOS's `scenePhase == .active` check (OnboardingView.swift:87-98). Only acts
     * if the user was actually stuck on the denied screen; an ordinary resume is a no-op. */
    private fun handleResumeRecheck(granted: Boolean) {
        if (!_uiState.value.isPermissionDenied || !granted) return
        _uiState.update { it.copy(isPermissionDenied = false) }
        goTo(OnboardingStep.SwipeDemo)
        startBackgroundScan()
    }

    private fun startBackgroundScan() {
        viewModelScope.launch {
            val counts = scanLibraryForOnboardingUseCase()
            _uiState.update {
                it.copy(scanCounts = ScanCountsUi(counts.photoCount, counts.videoCount, counts.largeVideoCount))
            }
        }
    }

    private fun goTo(step: OnboardingStep) {
        savedStateHandle[KEY_CURRENT_STEP] = step.name
        _uiState.update { it.copy(currentStep = step) }
    }

    private companion object {
        const val KEY_CURRENT_STEP = "current_step"
    }
}
