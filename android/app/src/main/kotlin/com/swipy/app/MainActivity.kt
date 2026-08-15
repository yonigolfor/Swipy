package com.swipy.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.swipy.feature.filters.FilterCategoriesScreen
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
                    PermissionGate()
                }
            }
        }
    }
}

private fun mediaPermissions(): Array<String> =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
    } else {
        arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

private fun hasMediaPermission(context: Context): Boolean =
    mediaPermissions().any {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

private const val ROUTE_FILTERS = "filters"
private const val ROUTE_SWIPE = "swipe"
private const val ROUTE_REVIEW_BIN = "reviewbin"

/** Gates SwipyNavHost behind the media permission prompt. */
@Composable
private fun PermissionGate() {
    val context = LocalContext.current
    var hasPermission by remember { mutableStateOf(hasMediaPermission(context)) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { results ->
        hasPermission = results.values.any { it }
    }

    if (hasPermission) {
        SwipyNavHost()
    } else {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Swipy needs access to your photos and videos", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(16.dp))
            Button(onClick = { permissionLauncher.launch(mediaPermissions()) }) {
                Text("Grant photo access")
            }
        }
    }
}

/**
 * Three destinations (filters -> swipe <-> review bin) — see android/CLAUDE.md "Navigation".
 * No bottom nav chrome yet (still just Compose Navigation's back-stack) — this is the plumbing
 * milestone, tab-bar UI is a separate concern.
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

    NavHost(navController = navController, startDestination = ROUTE_FILTERS) {
        composable(ROUTE_FILTERS) {
            FilterCategoriesScreen(
                onCategorySelected = { filter ->
                    photoStackViewModel.onIntent(PhotoStackIntent.LoadPhotos(filter))
                    navController.navigate(ROUTE_SWIPE)
                },
            )
        }
        composable(ROUTE_SWIPE) {
            SwipeStackScreen(
                onNavigateToReviewBin = { navController.navigate(ROUTE_REVIEW_BIN) },
                viewModel = photoStackViewModel,
            )
        }
        composable(ROUTE_REVIEW_BIN) {
            ReviewBinScreen(onBack = { navController.popBackStack() })
        }
    }
}
