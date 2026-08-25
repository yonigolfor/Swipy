package com.swipy.feature.paywall

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.swipy.core.designsystem.theme.OnboardingGoldEnd
import com.swipy.core.designsystem.theme.OnboardingGoldShadow
import com.swipy.core.designsystem.theme.OnboardingGoldStart
import com.swipy.core.designsystem.theme.SwipeGreen
import com.swipy.core.designsystem.theme.SwipeRed
import com.swipy.domain.model.PremiumTier
import com.swipy.domain.model.TierOffer
import kotlinx.coroutines.launch

private val PaywallBackgroundTop = Color(0xFF0A0A1F)
private val PaywallBackgroundBottom = Color(0xFF08050F)

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/**
 * Port of iOS `PaywallView`. See `PaywallContext` for the two presentation sites; both wire
 * [onDismiss] to whatever "close this screen" means for their host (a `NavController.popBackStack`
 * for [PaywallContext.SwipeLimitReached], a local flag flip for [PaywallContext.PostOnboarding]
 * — see `MainActivity.AppRoot`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(
    context: PaywallContext,
    onDismiss: () -> Unit,
    viewModel: PaywallViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val androidContext = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val bonusToastText = stringResource(R.string.paywall_share_bonus_toast)

    // Decided once per presentation, before first composition — avoids a post-layout flash.
    // Only meaningful for SwipeLimitReached; PostOnboarding has one fixed headline.
    val headerVariant = rememberSaveable { kotlin.random.Random.nextBoolean() }

    LaunchedEffect(uiState.isPremium) {
        if (uiState.isPremium) onDismiss()
    }

    val shareLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        // Fires the moment control returns to the app — see PaywallIntent.ShareCompleted's own
        // doc comment for why this can't distinguish "shared" from "cancelled" on Android.
        viewModel.onIntent(PaywallIntent.ShareCompleted)
        scope.launch { snackbarHostState.showSnackbar(bonusToastText) }
    }

    Scaffold(
        snackbarHost = {
            SnackbarHost(snackbarHostState) { data ->
                Snackbar(containerColor = SwipeGreen, contentColor = Color.White) {
                    Text(data.visuals.message, fontWeight = FontWeight.SemiBold)
                }
            }
        },
        bottomBar = {
            BottomCtaSection(
                uiState = uiState,
                onPurchase = {
                    androidContext.findActivity()?.let { activity ->
                        viewModel.onIntent(PaywallIntent.Purchase(activity))
                    }
                },
            )
        },
        containerColor = Color.Transparent,
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Brush.linearGradient(listOf(PaywallBackgroundTop, PaywallBackgroundBottom))),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.height(56.dp))
                HeaderSection(context = context, headerVariant = headerVariant)
                Spacer(Modifier.height(32.dp))
                BenefitsCard()
                Spacer(Modifier.height(28.dp))
                PricingRow(
                    tiers = uiState.tiers,
                    selectedTier = uiState.selectedTier,
                    isPurchasing = uiState.isPurchasing,
                    onSelect = { viewModel.onIntent(PaywallIntent.SelectTier(it)) },
                )
                Spacer(Modifier.height(16.dp))

                if (!uiState.hasSharedToday) {
                    ShareButton(
                        onClick = {
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, androidContext.getString(R.string.paywall_share_message))
                            }
                            shareLauncher.launch(Intent.createChooser(sendIntent, null))
                        },
                    )
                    Spacer(Modifier.height(16.dp))
                }

                TextButton(
                    onClick = { viewModel.onIntent(PaywallIntent.Restore) },
                    enabled = !uiState.isPurchasing,
                ) {
                    Text(
                        text = stringResource(R.string.paywall_restore),
                        fontSize = 14.sp,
                        color = Color.White.copy(alpha = 0.38f),
                    )
                }

                LegalLinksRow()
                Spacer(Modifier.height(24.dp))
            }

            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(top = 12.dp, start = 12.dp)
                    .size(44.dp)
                    .background(Color.White.copy(alpha = 0.18f), CircleShape)
                    .border(1.dp, Color.White.copy(alpha = 0.30f), CircleShape),
            ) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = Color.White)
            }
        }
    }
}

@Composable
private fun HeaderSection(context: PaywallContext, headerVariant: Boolean) {
    val infiniteTransition = rememberInfiniteTransition(label = "crownGlow")
    val glowElevation by infiniteTransition.animateFloat(
        initialValue = 15f,
        targetValue = 30f,
        animationSpec = infiniteRepeatable(tween(1600), RepeatMode.Reverse),
        label = "crownGlowElevation",
    )

    val title = when (context) {
        PaywallContext.PostOnboarding -> stringResource(R.string.paywall_title_onboarding)
        PaywallContext.SwipeLimitReached -> stringResource(if (headerVariant) R.string.paywall_title_a else R.string.paywall_title_b)
    }
    val subtitle = when (context) {
        PaywallContext.PostOnboarding -> stringResource(R.string.paywall_subtitle_onboarding)
        PaywallContext.SwipeLimitReached -> stringResource(R.string.paywall_subtitle)
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(84.dp)
                .shadow(
                    elevation = glowElevation.dp,
                    shape = CircleShape,
                    ambientColor = OnboardingGoldShadow,
                    spotColor = OnboardingGoldShadow,
                )
                .background(Brush.linearGradient(listOf(OnboardingGoldStart, OnboardingGoldEnd)), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("👑", fontSize = 34.sp)
        }
        Spacer(Modifier.height(22.dp))
        Text(
            text = title,
            fontSize = 30.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(10.dp))
        Text(
            text = subtitle,
            fontSize = 16.sp,
            color = Color.White.copy(alpha = 0.60f),
            textAlign = TextAlign.Center,
            lineHeight = 22.sp,
        )
    }
}

@Composable
private fun BenefitsCard() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.055f), RoundedCornerShape(22.dp))
            .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(22.dp))
            .padding(horizontal = 20.dp, vertical = 22.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        BenefitRow("♾️", stringResource(R.string.paywall_benefit_unlimited))
        BenefitRow("⚡", stringResource(R.string.paywall_benefit_speed))
        BenefitRow("❤️", stringResource(R.string.paywall_benefit_support))
        BenefitRow("⭐", stringResource(R.string.paywall_benefit_features))
    }
}

@Composable
private fun BenefitRow(icon: String, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(icon, fontSize = 16.sp, modifier = Modifier.width(26.dp))
        Spacer(Modifier.width(14.dp))
        Text(text, fontSize = 16.sp, color = Color.White.copy(alpha = 0.88f))
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun PricingRow(
    tiers: Map<PremiumTier, TierOffer>,
    selectedTier: PremiumTier,
    isPurchasing: Boolean,
    onSelect: (PremiumTier) -> Unit,
) {
    val listState = rememberLazyListState()
    LazyRow(
        state = listState,
        flingBehavior = rememberSnapFlingBehavior(listState),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(PremiumTier.entries.toList()) { tier ->
            PricingCard(
                tier = tier,
                offer = tiers[tier],
                isSelected = tier == selectedTier,
                isPurchasing = isPurchasing,
                onClick = { onSelect(tier) },
            )
        }
    }
}

@Composable
private fun PricingCard(
    tier: PremiumTier,
    offer: TierOffer?,
    isSelected: Boolean,
    isPurchasing: Boolean,
    onClick: () -> Unit,
) {
    val tierName = when (tier) {
        PremiumTier.Monthly -> stringResource(R.string.paywall_tier_monthly)
        PremiumTier.Yearly -> stringResource(R.string.paywall_tier_yearly)
        PremiumTier.Lifetime -> stringResource(R.string.paywall_tier_lifetime)
    }
    val background = if (isSelected) {
        Modifier.background(Brush.linearGradient(listOf(OnboardingGoldStart, OnboardingGoldEnd)), RoundedCornerShape(20.dp))
    } else {
        Modifier
            .background(Color.White.copy(alpha = 0.055f), RoundedCornerShape(20.dp))
            .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(20.dp))
    }
    val contentColor = if (isSelected) Color.Black else Color.White

    Column(
        modifier = Modifier
            .size(148.dp)
            .then(background)
            .clickable(enabled = !isPurchasing, onClick = onClick)
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (tier == PremiumTier.Yearly) {
            Text(
                text = stringResource(R.string.paywall_tier_best_value),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = if (isSelected) Color.Black.copy(alpha = 0.75f) else OnboardingGoldStart,
                modifier = Modifier
                    .background(Color.Black.copy(alpha = 0.25f), CircleShape)
                    .padding(horizontal = 12.dp, vertical = 5.dp),
            )
            Spacer(Modifier.height(8.dp))
        }
        Text(tierName, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = contentColor)
        Text(
            offer?.formattedPrice ?: "—",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = contentColor,
        )
        if (tier == PremiumTier.Yearly) {
            Text(stringResource(R.string.paywall_tier_savings), fontSize = 12.sp, color = contentColor)
        }
        if (tier == PremiumTier.Lifetime) {
            Text(stringResource(R.string.paywall_tier_lifetime_secondary), fontSize = 12.sp, color = contentColor)
        }
    }
}

@Composable
private fun ShareButton(onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .background(Color.White.copy(alpha = 0.06f), RoundedCornerShape(16.dp))
            .border(1.25.dp, Color.White.copy(alpha = 0.25f), RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.paywall_share_button),
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.80f),
        )
    }
}

@Composable
private fun LegalLinksRow() {
    val uriHandler = LocalUriHandler.current
    Row(
        modifier = Modifier.padding(top = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        TextButton(onClick = { uriHandler.openUri("https://swipy-app.netlify.app/privacy-policy.html") }) {
            Text(stringResource(R.string.paywall_legal_privacy), fontSize = 12.sp, color = Color.White.copy(alpha = 0.32f))
        }
        TextButton(onClick = { uriHandler.openUri("https://swipy-app.netlify.app/terms-of-use.html") }) {
            Text(stringResource(R.string.paywall_legal_terms), fontSize = 12.sp, color = Color.White.copy(alpha = 0.32f))
        }
    }
}

@Composable
private fun BottomCtaSection(uiState: PaywallUiState, onPurchase: () -> Unit) {
    val price: String? = uiState.tiers[uiState.selectedTier]?.formattedPrice
    val ctaText = when {
        price == null && uiState.selectedTier == PremiumTier.Lifetime -> stringResource(R.string.paywall_cta_lifetime)
        price == null -> stringResource(R.string.paywall_cta_subscribe)
        uiState.selectedTier == PremiumTier.Monthly -> stringResource(R.string.paywall_cta_subscribe_monthly_with_price, price)
        uiState.selectedTier == PremiumTier.Yearly -> stringResource(R.string.paywall_cta_subscribe_yearly_with_price, price)
        else -> stringResource(R.string.paywall_cta_lifetime_with_price, price)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF08050F))
            .padding(horizontal = 28.dp, vertical = 14.dp),
    ) {
        uiState.errorMessage?.let { error ->
            Text(error, fontSize = 12.sp, color = SwipeRed, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(6.dp))
        }
        if (uiState.selectedTier == PremiumTier.Lifetime && uiState.hasActiveSubscription) {
            Text(
                text = stringResource(R.string.paywall_tier_lifetime_double_billing_note),
                fontSize = 12.sp,
                color = Color.White.copy(alpha = 0.55f),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(6.dp))
        }
        Button(
            onClick = onPurchase,
            enabled = !uiState.isPurchasing && uiState.tiers[uiState.selectedTier] != null,
            modifier = Modifier.fillMaxWidth().height(58.dp),
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = OnboardingGoldStart, disabledContainerColor = OnboardingGoldStart.copy(alpha = 0.5f)),
        ) {
            if (uiState.isPurchasing) {
                CircularProgressIndicator(modifier = Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp)
            } else {
                Text(ctaText, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Color.Black, maxLines = 1)
            }
        }
    }
}
