package com.swipy.app

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.theme.OnboardingBackground
import kotlinx.coroutines.delay

private const val SPLASH_TOTAL_DURATION_MS = 1300L
private const val SPLASH_FADE_IN_DURATION_MS = 1000

/** Port of iOS SplashScreenView's branded entrance (icon + wordmark, fade+scale from 0.7/0.4
 * to 1.0/1.0 over 1s, then a fixed 1.3s total hold before handing off) — see
 * SplashScreenView.swift:38-97. The category-counts-refresh deferral iOS documents there has no
 * Android equivalent yet (Smart Filters counts already only compute on-demand from that
 * screen's own `.task`, per FilterCategoriesViewModel — nothing to defer here). */
@Composable
fun SplashScreen(onFinished: () -> Unit) {
    var animateIn by remember { mutableStateOf(false) }
    val targetScale by animateFloatAsState(if (animateIn) 1f else 0.7f, tween(SPLASH_FADE_IN_DURATION_MS), label = "splashScale")
    // Named to avoid shadowing GraphicsLayerScope's own `alpha` property inside the
    // graphicsLayer{} lambda below — `this.alpha = alpha` there would silently resolve its
    // right-hand side to the receiver's own property (a self-assigning no-op), not this value.
    val targetAlpha by animateFloatAsState(if (animateIn) 1f else 0.4f, tween(SPLASH_FADE_IN_DURATION_MS), label = "splashAlpha")

    LaunchedEffect(Unit) {
        animateIn = true
        delay(SPLASH_TOTAL_DURATION_MS)
        onFinished()
    }

    Box(modifier = Modifier.fillMaxSize().background(OnboardingBackground), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.graphicsLayer { scaleX = targetScale; scaleY = targetScale; alpha = targetAlpha },
        ) {
            Box(modifier = Modifier.clip(RoundedCornerShape(30.dp)).background(MaterialTheme.colorScheme.primary)) {
                Text(
                    text = "S",
                    color = Color.White,
                    fontSize = 72.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(24.dp),
                )
            }
            Spacer(Modifier.height(20.dp))
            Text(text = "Swipy", color = Color.White, fontSize = 32.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text(text = "Declutter your memories", color = Color.Gray, fontSize = 14.sp)
        }
    }
}
