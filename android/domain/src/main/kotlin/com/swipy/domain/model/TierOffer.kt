package com.swipy.domain.model

/**
 * A resolved, display-ready price for one [PremiumTier] — the domain-safe stand-in for StoreKit's
 * `Product`/Play Billing's `ProductDetails`, neither of which :domain may reference. [formattedPrice]
 * is null until the underlying billing query resolves (mirrors iOS's `premiumManager.products[tier]`
 * being absent pre-resolution — the pricing card still renders, only the CTA price is unavailable).
 */
data class TierOffer(
    val tier: PremiumTier,
    val formattedPrice: String?,
)
