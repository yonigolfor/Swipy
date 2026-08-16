package com.swipy.core.designsystem.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.haptics.rememberHapticManager
import com.swipy.core.designsystem.theme.OnboardingGoldEnd
import com.swipy.core.designsystem.theme.OnboardingGoldShadow
import com.swipy.core.designsystem.theme.OnboardingGoldStart

/**
 * The gold-gradient capsule CTA used on every Onboarding step — port of iOS's shared CTA token
 * (ONBOARDING.md "Shared Design Tokens" → "CTA Button (all steps)"). Compose's `Modifier.shadow`
 * has no x/y offset parameter the way SwiftUI's does (see PhotoCardComposable's own note on the
 * same gap) — the y:5 offset from `.shadow(color:radius:15,y:5)` isn't literally reproduced.
 *
 * Fires [HapticManager.mediumTap] on every tap, matching iOS's shared `haptic` generator
 * ("`UIImpactFeedbackGenerator(style: .medium)` — all CTA taps", root `CLAUDE.md` "Haptics") —
 * wired here once rather than at each individual onboarding step's `onClick`.
 */
@Composable
fun GoldCapsuleButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val hapticManager = rememberHapticManager()
    Text(
        text = text,
        color = Color.Black,
        fontSize = 17.sp,
        fontWeight = FontWeight.SemiBold,
        textAlign = TextAlign.Center,
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                elevation = 15.dp,
                shape = CircleShape,
                ambientColor = OnboardingGoldShadow.copy(alpha = 0.5f),
                spotColor = OnboardingGoldShadow.copy(alpha = 0.5f),
            )
            .background(Brush.horizontalGradient(listOf(OnboardingGoldStart, OnboardingGoldEnd)), CircleShape)
            .clickable(
                enabled = enabled,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = {
                    hapticManager.mediumTap()
                    onClick()
                },
            )
            .padding(vertical = 18.dp),
    )
}
