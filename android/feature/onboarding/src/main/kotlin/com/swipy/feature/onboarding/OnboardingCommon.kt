package com.swipy.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.swipy.core.designsystem.theme.OnboardingBackground

/** Full-bleed dark background shared by every onboarding step — matches SplashScreenView's
 * identical background color (OnboardingView.swift:63, ONBOARDING.md "Shared Design Tokens"). */
@Composable
fun OnboardingBackgroundBox(content: @Composable BoxScope.() -> Unit) {
    Box(modifier = Modifier.fillMaxSize().background(OnboardingBackground), content = content)
}

/** The greyscale-gradient mock card used by VisualHook, SwipeDemo, and SnoozeIntro — decorative
 * placeholders standing in for real photos in the demo, not real PhotoItem content. */
internal val OnboardingCardCornerRadius = 20.dp
internal val OnboardingCardShadowColor = Color.Black.copy(alpha = 0.4f)

@Composable
internal fun OnboardingMockCardBackground(topWhite: Float, bottomWhite: Float, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .shadow(
                elevation = 15.dp,
                shape = RoundedCornerShape(OnboardingCardCornerRadius),
                ambientColor = OnboardingCardShadowColor,
                spotColor = OnboardingCardShadowColor,
            )
            .background(
                Brush.linearGradient(listOf(Color(topWhite, topWhite, topWhite), Color(bottomWhite, bottomWhite, bottomWhite))),
                RoundedCornerShape(OnboardingCardCornerRadius),
            ),
    )
}
