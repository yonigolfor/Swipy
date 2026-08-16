package com.swipy.feature.onboarding

import androidx.compose.animation.AnimatedContent
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.component.GoldCapsuleButton
import com.swipy.core.designsystem.theme.FilterScreenshots
import com.swipy.core.designsystem.theme.SwipeGreen

/** Port of iOS `step4_Permission` (OnboardingView.swift:494-570) — including the in-place
 * denied-state swap (subtitle + CTA text/action change, no navigation away from this step). */
@Composable
fun PermissionStep(
    isPermissionDenied: Boolean,
    onRequestPermission: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(Modifier.weight(1f))

        Box(
            modifier = Modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier.size(120.dp).background(FilterScreenshots.copy(alpha = 0.15f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = "🔒", fontSize = 60.sp)
            }
        }

        Spacer(Modifier.height(24.dp))

        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = stringResource(R.string.onboarding_permission_title),
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(16.dp))
            AnimatedContent(targetState = isPermissionDenied, label = "permissionSubtitle") { denied ->
                Text(
                    text = if (denied) {
                        stringResource(R.string.permission_denied_message)
                    } else {
                        stringResource(R.string.onboarding_permission_subtitle)
                    },
                    fontSize = 15.sp,
                    color = Color.Gray,
                    textAlign = TextAlign.Center,
                    lineHeight = 20.sp,
                )
            }
        }

        Spacer(Modifier.height(32.dp))

        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            PrivacyRow(glyph = "📱", text = stringResource(R.string.onboarding_permission_local))
            PrivacyRow(glyph = "🙈", text = stringResource(R.string.onboarding_permission_private))
            PrivacyRow(glyph = "🚫", text = stringResource(R.string.onboarding_permission_control))
        }

        Spacer(Modifier.weight(1f))

        AnimatedContent(targetState = isPermissionDenied, label = "permissionCta") { denied ->
            GoldCapsuleButton(
                text = if (denied) {
                    stringResource(R.string.permission_denied_cta)
                } else {
                    stringResource(R.string.onboarding_permission_cta)
                },
                onClick = if (denied) onOpenSettings else onRequestPermission,
                modifier = Modifier.padding(start = 32.dp, end = 32.dp, bottom = 48.dp),
            )
        }
    }
}

@Composable
private fun PrivacyRow(glyph: String, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(modifier = Modifier.width(24.dp), contentAlignment = Alignment.Center) {
            Text(text = glyph, fontSize = 16.sp, color = SwipeGreen)
        }
        Text(text = text, fontSize = 14.sp, color = Color.White.copy(alpha = 0.8f))
    }
}
