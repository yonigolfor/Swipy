package com.swipy.feature.paywall

import com.swipy.domain.model.PremiumTier
import com.swipy.domain.model.TierOffer
import kotlinx.collections.immutable.ImmutableMap
import kotlinx.collections.immutable.persistentMapOf

/** Single immutable state object — see android/CLAUDE.md "Architecture". */
data class PaywallUiState(
    val tiers: ImmutableMap<PremiumTier, TierOffer> = persistentMapOf(),
    val selectedTier: PremiumTier = PremiumTier.Yearly,
    val isPurchasing: Boolean = false,
    val errorMessage: String? = null,
    val hasActiveSubscription: Boolean = false,
    val hasSharedToday: Boolean = false,
    /** Screens observe this to auto-dismiss — mirrors iOS `.onChange(of: premiumManager.isPremium)`. */
    val isPremium: Boolean = false,
)
