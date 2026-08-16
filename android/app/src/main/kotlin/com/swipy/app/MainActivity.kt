package com.swipy.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.swipy.core.designsystem.theme.OnboardingBackground
import com.swipy.feature.filters.FilterCategoriesScreen
import com.swipy.feature.onboarding.OnboardingScreen
import com.swipy.feature.reviewbin.ReviewBinScreen
import com.swipy.feature.swipe.PhotoStackIntent
import com.swipy.feature.swipe.PhotoStackViewModel
import com.swipy.feature.swipe.SwipeStackScreen
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AppRoot()
                }
            }
        }
    }
}

private const val ROUTE_FILTERS = "filters"
private const val ROUTE_SWIPE = "swipe"
private const val ROUTE_REVIEW_BIN = "reviewbin"

/**
 * Splash -> Onboarding OR SwipyNavHost, gated purely on `hasCompletedOnboarding` — the direct
 * port of iOS SplashScreenView's own routing (SplashScreenView.swift:38-53). Unlike iOS, which
 * needs a manual `showMainApp` @State mirror of the @AppStorage flag (a documented SwiftUI
 * gotcha: @AppStorage mutations don't reliably participate in a withAnimation transaction),
 * Compose's plain reactive recomposition needs no such mirror — SplashViewModel's StateFlow
 * naturally recomposes AppRoot into SwipyNavHost the instant OnboardingScreen persists the flag,
 * so `onComplete` below is a no-op; the real signal is DataStore's own emission.
 *
 * No standalone media-permission gate here (the old PermissionGate) — permission is requested
 * inside OnboardingScreen's own Permission step before a first-time user ever reaches
 * SwipyNavHost. A returning user whose permission was later revoked isn't re-gated at this
 * level, matching iOS's own top-level routing exactly; that recovery path (per root CLAUDE.md's
 * "Photos permission denied/restricted: Never a dead end") belongs inside the Swipe screen
 * itself, out of scope for this pass.
 */
@Composable
private fun AppRoot() {
    var showSplash by remember { mutableStateOf(true) }
    val splashViewModel: SplashViewModel = hiltViewModel()
    val hasCompletedOnboarding by splashViewModel.hasCompletedOnboarding.collectAsStateWithLifecycle()

    when {
        showSplash -> SplashScreen(onFinished = { showSplash = false })
        hasCompletedOnboarding == false -> OnboardingScreen(onComplete = {})
        hasCompletedOnboarding == true -> SwipyNavHost()
        else -> {
            // null: DataStore hasn't delivered its first value yet (in practice this window
            // closes well before the splash's own 1.3s timer elapses) — keep the splash's own
            // background up rather than flash onboarding for what's likely a returning user.
            Box(modifier = Modifier.fillMaxSize().background(OnboardingBackground))
        }
    }
}

/**
 * Three destinations (filters / swipe / review bin), all reachable at will via a bottom
 * NavigationBar — the Material 3, Android-idiomatic equivalent of iOS's floating-capsule
 * TabView (see android/CLAUDE.md "Navigation": "do NOT attempt to pixel-clone the iOS
 * floating capsule — that fights Android's platform conventions"). Review Bin's tab carries a
 * native badge with the pending count, matching iOS's `.badge(reviewBin.count)`.
 *
 * PhotoStackViewModel is obtained ONCE here, at NavHost's own composable scope (which resolves
 * against the Activity, the nearest ViewModelStoreOwner) — never via each destination's own
 * default `hiltViewModel()`, which would scope to that destination's NavBackStackEntry and
 * hand Filters and Swipe two different instances. Selecting a category would then silently do
 * nothing, since LoadPhotos would land on a PhotoStackViewModel nobody is observing. This is
 * the direct Android analogue of iOS's single @EnvironmentObject VM shared by SmartFiltersView
 * and SwipeStackView.
 */
@Composable
private fun SwipyNavHost() {
    val navController = rememberNavController()
    val photoStackViewModel: PhotoStackViewModel = hiltViewModel()
    val stackUiState by photoStackViewModel.uiState.collectAsStateWithLifecycle()

    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = currentRoute == ROUTE_FILTERS,
                    onClick = { navController.navigateToTab(ROUTE_FILTERS) },
                    icon = { Text("🔍") },
                    label = { Text("Filters") },
                )
                NavigationBarItem(
                    selected = currentRoute == ROUTE_SWIPE,
                    onClick = { navController.navigateToTab(ROUTE_SWIPE) },
                    icon = { Text("🗂️") },
                    label = { Text("Swipe") },
                )
                NavigationBarItem(
                    selected = currentRoute == ROUTE_REVIEW_BIN,
                    onClick = { navController.navigateToTab(ROUTE_REVIEW_BIN) },
                    icon = {
                        BadgedBox(
                            badge = {
                                if (stackUiState.reviewBinCount > 0) {
                                    Badge { Text("${stackUiState.reviewBinCount}") }
                                }
                            },
                        ) {
                            Text("🗑️")
                        }
                    },
                    label = { Text("Review Bin") },
                )
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = ROUTE_FILTERS,
            modifier = Modifier.padding(padding),
        ) {
            composable(ROUTE_FILTERS) {
                FilterCategoriesScreen(
                    onCategorySelected = { filter ->
                        photoStackViewModel.onIntent(PhotoStackIntent.LoadPhotos(filter))
                        navController.navigateToTab(ROUTE_SWIPE)
                    },
                )
            }
            composable(ROUTE_SWIPE) {
                SwipeStackScreen(
                    onNavigateToReviewBin = { navController.navigateToTab(ROUTE_REVIEW_BIN) },
                    viewModel = photoStackViewModel,
                )
            }
            composable(ROUTE_REVIEW_BIN) {
                ReviewBinScreen(onBack = { navController.navigateToTab(ROUTE_SWIPE) })
            }
        }
    }
}

/**
 * Tab-switch: fully clears the back stack and pushes [route] as the only entry. The usual
 * bottom-nav pattern (`popUpTo(startDestination) { saveState = true }` + `restoreState = true`)
 * was tried first and produced a real, reproducible bug — the Filters destination (start
 * destination AND popUpTo anchor) is never actually popped (popUpTo excludes its anchor by
 * default), so it stayed alive underneath every other tab and visibly bled through (duplicate
 * "Space saved"/"Review Bin" text stacked behind the current screen, stable across full app
 * restarts — not a transient animation/capture artifact, confirmed by taking two screenshots
 * back to back and finding them pixel-identical). None of the three screens has scroll position
 * or other UI state worth preserving across a tab switch — Review Bin/Filters re-derive their
 * state from repositories on ViewModel init regardless, and PhotoStackViewModel is hoisted
 * outside the NavHost already — so trading that minor nicety for eliminating the bug outright
 * is the right call here, not a workaround masking a problem that still needs solving.
 */
private fun NavHostController.navigateToTab(route: String) {
    navigate(route) {
        popUpTo(graph.id) { inclusive = true }
        launchSingleTop = true
    }
}
