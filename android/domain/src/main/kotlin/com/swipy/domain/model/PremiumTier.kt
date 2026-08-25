package com.swipy.domain.model

/**
 * The 3 pricing tiers — port of iOS `PremiumTier` (PremiumManager.swift). Monthly/Yearly map to
 * one Play Billing subscription product with two base plans (Play's recommended shape for
 * upgrade/downgrade between them, the analogue of iOS's "same subscription group"); Lifetime
 * maps to a separate one-time product. See android/TODO.md item 8 for the Play Console
 * product/base-plan ids these correspond to.
 */
enum class PremiumTier {
    Monthly,
    Yearly,
    Lifetime,
}
