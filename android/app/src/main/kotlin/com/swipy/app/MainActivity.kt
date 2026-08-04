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
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.swipy.feature.reviewbin.ReviewBinScreen
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
 * Two destinations for now (swipe <-> review bin) — see android/CLAUDE.md "Navigation" for
 * where this grows into a bottom-nav SwipyNavHost once :feature:filters exists too.
 */
@Composable
private fun SwipyNavHost() {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = ROUTE_SWIPE) {
        composable(ROUTE_SWIPE) {
            SwipeStackScreen(onNavigateToReviewBin = { navController.navigate(ROUTE_REVIEW_BIN) })
        }
        composable(ROUTE_REVIEW_BIN) {
            ReviewBinScreen(onBack = { navController.popBackStack() })
        }
    }
}
