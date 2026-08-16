package com.swipy.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.component.GoldCapsuleButton
import com.swipy.core.designsystem.theme.SwipeGreen

/** Port of iOS `step5_QuickWin` (OnboardingView.swift:574-632) — completes onboarding directly
 * in this pass (no paywall step — see the confirmed Pass 1 scope). */
@Composable
fun QuickWinStep(onComplete: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(Modifier.weight(1f))

        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Box(modifier = Modifier.size(180.dp).background(SwipeGreen.copy(alpha = 0.08f), CircleShape))
            Box(modifier = Modifier.size(140.dp).background(SwipeGreen.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                Text(text = "✅", fontSize = 80.sp)
            }
        }

        Spacer(Modifier.height(32.dp))

        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(text = "You're all set!", fontSize = 36.sp, fontWeight = FontWeight.Bold, color = Color.White, textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp))
            Text(text = "Time to reclaim your storage.", fontSize = 15.sp, color = Color.Gray, textAlign = TextAlign.Center)
        }

        Spacer(Modifier.weight(1f))

        GoldCapsuleButton(text = "Start Swiping", onClick = onComplete, modifier = Modifier.padding(start = 32.dp, end = 32.dp, bottom = 48.dp))
    }
}
