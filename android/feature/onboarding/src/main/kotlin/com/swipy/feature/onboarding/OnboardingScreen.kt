package com.swipy.feature.onboarding

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle

private fun mediaPermissions(): Array<String> =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
    } else {
        arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

private fun hasMediaPermission(context: android.content.Context): Boolean =
    mediaPermissions().any { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }

/**
 * Router + permission plumbing for the 6-step onboarding flow — the Android port of iOS
 * OnboardingView's top-level body (OnboardingView.swift:60-99): step switch, the system
 * permission dialog, and the silent onResume recheck that recovers automatically if the user
 * granted access from Settings and returned (the exact analogue of iOS's `scenePhase == .active`
 * handler). Step transitions are a plain Compose recomposition here rather than iOS's explicit
 * `.pushForward` transition + `.id(currentStep)` — a deliberate simplification for this pass,
 * not a parity gap that needs closing later unless the lack of a slide animation is felt.
 */
@Composable
fun OnboardingScreen(
    onComplete: () -> Unit,
    viewModel: OnboardingViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { results ->
        viewModel.onIntent(OnboardingIntent.PermissionResult(results.values.any { it }))
    }

    LaunchedEffect(Unit) {
        viewModel.effects.collect { effect ->
            when (effect) {
                OnboardingEffect.LaunchPermissionRequest -> permissionLauncher.launch(mediaPermissions())
                OnboardingEffect.OpenAppSettings -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", context.packageName, null),
                    )
                    context.startActivity(intent)
                }
            }
        }
    }

    // Silent recovery when returning from Settings — mirrors iOS's scenePhase observer exactly:
    // only meaningful while stuck on the denied screen, a no-op on every ordinary resume.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.onIntent(OnboardingIntent.RecheckPermissionOnResume(hasMediaPermission(context)))
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    OnboardingBackgroundBox {
        when (uiState.currentStep) {
            OnboardingStep.VisualHook -> VisualHookStep(
                onNext = { viewModel.onIntent(OnboardingIntent.StartFromHook) },
            )
            OnboardingStep.Permission -> PermissionStep(
                isPermissionDenied = uiState.isPermissionDenied,
                onRequestPermission = { viewModel.onIntent(OnboardingIntent.RequestPermission) },
                onOpenSettings = { viewModel.onIntent(OnboardingIntent.OpenSettings) },
            )
            OnboardingStep.SwipeDemo -> SwipeDemoStep(
                onNext = { viewModel.onIntent(OnboardingIntent.NextFromDemo) },
            )
            OnboardingStep.SnoozeIntro -> SnoozeIntroStep(
                onNext = { viewModel.onIntent(OnboardingIntent.NextFromSnoozeIntro) },
            )
            OnboardingStep.Scan -> ScanStep(
                scanCounts = uiState.scanCounts,
                onNext = { viewModel.onIntent(OnboardingIntent.NextFromScan) },
            )
            OnboardingStep.QuickWin -> QuickWinStep(
                onComplete = {
                    viewModel.onIntent(OnboardingIntent.Complete)
                    onComplete()
                },
            )
        }
    }
}
