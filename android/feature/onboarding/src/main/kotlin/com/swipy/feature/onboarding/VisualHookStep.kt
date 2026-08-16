package com.swipy.feature.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.component.GoldCapsuleButton

/** Port of iOS `step1_VisualHook` (OnboardingView.swift:103-206) — a fanned stack of 5 mock
 * cards + a top card carrying the "10,000+ photos & videos" hook, gold CTA jumps straight to
 * Permission. */
@Composable
fun VisualHookStep(onNext: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(Modifier.weight(1f))

        Box(
            modifier = Modifier.fillMaxWidth().height(320.dp).padding(bottom = 20.dp),
            contentAlignment = Alignment.Center,
        ) {
            for (i in 0 until 5) {
                val white = 0.25f - i * 0.03f
                val bottomWhite = 0.18f - i * 0.02f
                OnboardingMockCardBackground(
                    topWhite = white,
                    bottomWhite = bottomWhite,
                    modifier = Modifier
                        .size(220.dp, 280.dp)
                        .graphicsLayer {
                            rotationZ = (i - 2) * 6f
                            translationY = i * 6.dp.toPx()
                        },
                )
            }

            Box(modifier = Modifier.size(220.dp, 280.dp)) {
                OnboardingMockCardBackground(topWhite = 0.28f, bottomWhite = 0.20f, modifier = Modifier.fillMaxSize())
                Column(
                    modifier = Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        text = "🖼️",
                        fontSize = 60.sp,
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = stringResource(R.string.onboarding_hook_stat_number),
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                    Text(text = stringResource(R.string.onboarding_hook_stat_label), fontSize = 14.sp, color = Color.Gray)
                }
            }
        }

        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = stringResource(R.string.onboarding_hook_title),
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                textAlign = TextAlign.Center,
                lineHeight = 38.sp,
            )
            Spacer(Modifier.height(16.dp))
            Text(
                text = stringResource(R.string.onboarding_hook_subtitle),
                fontSize = 14.sp,
                color = Color.Gray,
                textAlign = TextAlign.Center,
            )
        }

        Spacer(Modifier.weight(1f))

        GoldCapsuleButton(
            text = stringResource(R.string.onboarding_hook_cta),
            onClick = onNext,
            modifier = Modifier.padding(start = 32.dp, end = 32.dp, bottom = 48.dp),
        )
    }
}
