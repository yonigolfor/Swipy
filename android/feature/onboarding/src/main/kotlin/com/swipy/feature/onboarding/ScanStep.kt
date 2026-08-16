package com.swipy.feature.onboarding

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.StartOffsetType
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.component.GlassSurface
import com.swipy.core.designsystem.component.GoldCapsuleButton
import com.swipy.core.designsystem.theme.FilterLargeVideos
import com.swipy.core.designsystem.theme.FilterScreenRecordings
import com.swipy.core.designsystem.theme.FilterScreenshots
import kotlinx.coroutines.delay

private const val SCAN_ANIMATION_DURATION_MS = 1100

/** Port of iOS `step2_Scan` (OnboardingView.swift:210-347) — glassmorphic card with 3 animated
 * counters. Simplified vs iOS's manual 20-step/55ms loop + "arrived after screen appeared"
 * race handling: Android's MediaStore counts resolve in one fast batch (see
 * ScanLibraryForOnboardingUseCase), so `animateIntAsState` alone covers the same count-up feel
 * without needing iOS's two-phase estimate/refine dance. */
@Composable
fun ScanStep(scanCounts: ScanCountsUi?, onNext: () -> Unit) {
    var ctaReady by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(SCAN_ANIMATION_DURATION_MS.toLong())
        ctaReady = true
    }

    val displayedPhoto by animateIntAsState(scanCounts?.photoCount ?: 0, tween(SCAN_ANIMATION_DURATION_MS), label = "photoCount")
    val displayedVideo by animateIntAsState(scanCounts?.videoCount ?: 0, tween(SCAN_ANIMATION_DURATION_MS), label = "videoCount")
    val displayedLarge by animateIntAsState(scanCounts?.largeVideoCount ?: 0, tween(600), label = "largeVideoCount")

    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(Modifier.weight(1f))

        GlassSurface(
            shape = RoundedCornerShape(24.dp),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
        ) {
            Column(modifier = Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text = "🔍", fontSize = 20.sp)
                    Spacer(Modifier.width(8.dp))
                    Text(text = "Scanning your gallery…", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    Spacer(Modifier.weight(1f))
                    if (scanCounts != null) {
                        Text(text = "✅", fontSize = 16.sp)
                    }
                }
                Spacer(Modifier.height(16.dp))
                HorizontalDivider(color = Color.White.copy(alpha = 0.15f))
                Spacer(Modifier.height(16.dp))
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    ScanRow(glyph = "📷", label = "Photos", value = displayedPhoto, isScanning = scanCounts == null, color = FilterScreenshots)
                    ScanRow(glyph = "🎬", label = "Videos", value = displayedVideo, isScanning = scanCounts == null, color = FilterScreenRecordings)
                    ScanRow(glyph = "🎞️", label = "Large Videos", value = displayedLarge, isScanning = scanCounts == null, color = FilterLargeVideos)
                }
            }
        }

        Spacer(Modifier.height(16.dp))

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            Text(text = "🔒", fontSize = 11.sp)
            Spacer(Modifier.width(6.dp))
            Text(text = "Everything stays private, on your device", fontSize = 11.sp, color = Color.Gray)
        }

        Spacer(Modifier.weight(1f))

        if (ctaReady) {
            GoldCapsuleButton(text = "Let's Clean Up!", onClick = onNext, modifier = Modifier.padding(start = 32.dp, end = 32.dp, bottom = 48.dp))
        } else {
            Text(
                text = "Skip for now",
                fontSize = 14.sp,
                color = Color.Gray,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 48.dp)
                    .padding(vertical = 12.dp),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun ScanRow(glyph: String, label: String, value: Int, isScanning: Boolean, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(modifier = Modifier.width(24.dp), contentAlignment = Alignment.Center) {
            Text(text = glyph, fontSize = 15.sp)
        }
        Spacer(Modifier.width(8.dp))
        Text(text = label, fontSize = 14.sp, color = Color.White.copy(alpha = 0.8f))
        Spacer(Modifier.weight(1f))
        if (isScanning) {
            ScanningDots(color = color)
        } else {
            Text(text = "$value", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Color.White)
        }
    }
}

@Composable
private fun ScanningDots(color: Color) {
    val transition = rememberInfiniteTransition(label = "scanningDots")
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        repeat(3) { index ->
            val scale by transition.animateFloat(
                initialValue = 0.4f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(600, easing = LinearEasing),
                    repeatMode = RepeatMode.Reverse,
                    initialStartOffset = StartOffset(index * 200, StartOffsetType.Delay),
                ),
                label = "dot$index",
            )
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .background(color.copy(alpha = scale), CircleShape),
            )
        }
    }
}
