package com.swipy.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.swipy.core.designsystem.theme.OnboardingBackground
import com.swipy.core.notifications.SwipyNotificationManager
import com.swipy.domain.model.FilterCategory
import com.swipy.feature.filters.FilterCategoriesScreen
import com.swipy.feature.onboarding.OnboardingScreen
import com.swipy.feature.paywall.PaywallContext
import com.swipy.feature.paywall.PaywallScreen
import com.swipy.feature.reviewbin.ReviewBinScreen
import com.swipy.feature.swipe.PhotoStackIntent
import com.swipy.feature.swipe.PhotoStackViewModel
import com.swipy.feature.swipe.SwipeStackScreen
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    /** Activity-level so both `onCreate` (cold start) and `onNewIntent` (tapped a notification
     * while already running — MainActivity is the app's only Activity, so `FLAG_ACTIVITY_
     * CLEAR_TOP` redelivers here via `onNewIntent` rather than spawning a second instance) can
     * push into the same composition. */
    private val pendingDeepLinkRoute = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingDeepLinkRoute.value = intent?.getStringExtra(SwipyNotificationManager.EXTRA_DEEP_LINK_ROUTE)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AppRoot(
                        pendingDeepLinkRoute = pendingDeepLinkRoute.value,
                        onDeepLinkConsumed = { pendingDeepLinkRoute.value = null },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingDeepLinkRoute.value = intent.getStringExtra(SwipyNotificationManager.EXTRA_DEEP_LINK_ROUTE)
    }
}

private const val ROUTE_FILTERS = "filters"
private const val ROUTE_SWIPE = "swipe"
private const val ROUTE_REVIEW_BIN = "reviewbin"

/** Pushed on top of the back stack from [ROUTE_SWIPE] when the daily swipe quota blocks a Keep/
 * Delete — deliberately not a bottom-nav tab, not in [KNOWN_ROUTES]/deep-link-reachable. See
 * android/TODO.md item 8 "Paywall Presentation Wiring" for why the `.postOnboarding` context is
 * handled separately in [AppRoot] instead of a NavHost destination. */
private const val ROUTE_PAYWALL = "paywall"

/** Guards against a malformed/unexpected `SwipyNotificationManager.EXTRA_DEEP_LINK_ROUTE` value
 * crashing `NavHost` with "no destination found" — must be kept in sync with the 3
 * `composable(...)` registrations below and with `NotificationTrigger.deepLinkRoute`'s values
 * in `:core:notifications` (duplicated by necessity, see that enum's own doc comment). */
private val KNOWN_ROUTES = setOf(ROUTE_FILTERS, ROUTE_SWIPE, ROUTE_REVIEW_BIN)

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
private fun AppRoot(pendingDeepLinkRoute: String?, onDeepLinkConsumed: () -> Unit) {
    var showSplash by remember { mutableStateOf(true) }
    val splashViewModel: SplashViewModel = hiltViewModel()
    val hasCompletedOnboarding by splashViewModel.hasCompletedOnboarding.collectAsStateWithLifecycle()

    // One-shot: shown exactly once, immediately after onboarding completes — the Android
    // orchestration equivalent of iOS embedding PaywallView as onboarding's own literal last
    // page. Kept here (not inside :feature:onboarding) so no feature module needs to depend on
    // :feature:paywall; :app already owns this sequencing (Splash -> Onboarding -> NavHost).
    var showPostOnboardingPaywall by remember { mutableStateOf(false) }

    when {
        showSplash -> SplashScreen(onFinished = { showSplash = false })
        hasCompletedOnboarding == false -> OnboardingScreen(onComplete = { showPostOnboardingPaywall = true })
        hasCompletedOnboarding == true && showPostOnboardingPaywall -> PaywallScreen(
            context = PaywallContext.PostOnboarding,
            onDismiss = { showPostOnboardingPaywall = false },
        )
        hasCompletedOnboarding == true -> SwipyNavHost(
            pendingDeepLinkRoute = pendingDeepLinkRoute,
            onDeepLinkConsumed = onDeepLinkConsumed,
        )
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
 *
 * [pendingDeepLinkRoute] is the tab a notification tap wants to open (see
 * `SwipyNotificationManager.EXTRA_DEEP_LINK_ROUTE`/`NotificationTrigger.deepLinkRoute`) — used
 * as the initial `startDestination` on a cold start, and as an explicit `navigateToTab` call
 * for a warm start (tapping a notification while the app is already running doesn't recompose
 * `NavHost` with a new `startDestination`; that param is only read at first composition —
 * changing it afterward makes Navigation Compose rebuild the whole graph, wiping the back
 * stack, so [initialRoute] below deliberately captures it once via a keyless `remember` and
 * never lets the live parameter feed back into `startDestination`).
 */
@Composable
private fun SwipyNavHost(pendingDeepLinkRoute: String?, onDeepLinkConsumed: () -> Unit) {
    val navController = rememberNavController()
    val photoStackViewModel: PhotoStackViewModel = hiltViewModel()
    val stackUiState by photoStackViewModel.uiState.collectAsStateWithLifecycle()
    val initialRoute = remember { pendingDeepLinkRoute.takeIf { it in KNOWN_ROUTES } ?: ROUTE_SWIPE }

    // POST_NOTIFICATIONS (API 33+) — requested here, not inside OnboardingScreen, matching
    // iOS's own HIG-driven choice to ask from ContentView.onAppear (i.e. the first time the
    // *main* app screen is reached, after onboarding, not during it — see NOTIFICATIONS.md's
    // "why not in didFinishLaunching" note). `SwipyNavHost` is entered once per app process
    // lifetime in practice (its parent `when` branch in AppRoot only re-enters this composable
    // if `hasCompletedOnboarding` itself changes, which doesn't happen mid-session), so this
    // LaunchedEffect(Unit) fires once per cold start — the same granularity as iOS's onAppear.
    // No manual "already asked" tracking needed: below API 33 this permission doesn't exist,
    // and on 33+ the OS itself silently stops showing the dialog after the user denies twice
    // (or checks "Don't ask again" on the first denial) — calling `launch()` unconditionally on
    // a permission that's already granted or permanently denied is a documented no-op, so this
    // can't turn into the "re-prompt in a loop" anti-pattern the media-permission flow
    // explicitly avoids via its Settings-deep-link fallback.
    val context = LocalContext.current
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* No in-app UI reacts to the result — notifications are a background enhancement, not
          a blocking gate like gallery access, so there's no dedicated recovery screen here,
          matching iOS's own fire-and-forget requestAuthorization call. */ }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // PhotoStackViewModel never auto-loads on init (it stays empty until LoadPhotos is sent,
    // normally triggered by tapping a Filters category) — now that Swipe is the start
    // destination (see android/TODO.md item 4), a first-time landing needs its own trigger or
    // the user would see a permanently empty stack with no way to populate it. Guarded on the
    // stack actually being empty so this never re-fires a redundant load on recomposition or
    // after a real LoadPhotos already ran.
    LaunchedEffect(Unit) {
        if (stackUiState.stack.isEmpty()) {
            photoStackViewModel.onIntent(PhotoStackIntent.LoadPhotos(FilterCategory.All))
        }
    }

    // Warm-start re-navigation only — the cold-start case is already covered by [initialRoute]
    // above, so this redundantly (harmlessly) re-navigates to the same tab on first composition.
    LaunchedEffect(pendingDeepLinkRoute) {
        if (pendingDeepLinkRoute != null && pendingDeepLinkRoute in KNOWN_ROUTES) {
            navController.navigateToTab(pendingDeepLinkRoute)
        }
        if (pendingDeepLinkRoute != null) onDeepLinkConsumed()
    }

    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = currentRoute == ROUTE_FILTERS,
                    onClick = { navController.navigateToTab(ROUTE_FILTERS) },
                    icon = { Text("🔍") },
                    label = { Text(stringResource(R.string.nav_tab_filters)) },
                )
                NavigationBarItem(
                    selected = currentRoute == ROUTE_SWIPE,
                    onClick = { navController.navigateToTab(ROUTE_SWIPE) },
                    icon = { Text("🗂️") },
                    label = { Text(stringResource(R.string.nav_tab_swipe)) },
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
                    // Reuses :feature:reviewbin's own top-bar title string rather than a
                    // separate :app-local duplicate — same word, one source of truth.
                    label = { Text(stringResource(com.swipy.feature.reviewbin.R.string.reviewbin_top_bar_title)) },
                )
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = initialRoute,
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
                    viewModel = photoStackViewModel,
                    onShowPaywall = { navController.navigate(ROUTE_PAYWALL) },
                )
            }
            composable(ROUTE_REVIEW_BIN) {
                ReviewBinScreen(onBack = { navController.navigateToTab(ROUTE_SWIPE) })
            }
            composable(ROUTE_PAYWALL) {
                PaywallScreen(
                    context = PaywallContext.SwipeLimitReached,
                    onDismiss = { navController.popBackStack() },
                )
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
