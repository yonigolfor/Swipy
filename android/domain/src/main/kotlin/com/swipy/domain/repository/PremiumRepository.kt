package com.swipy.domain.repository

import kotlinx.coroutines.flow.StateFlow

/**
 * Entitlement state only — the port of iOS `PremiumManager`'s three `@Published` flags that
 * `PhotoStackViewModel`'s swipe-block gate actually reads. Deliberately excludes
 * products/purchase/restore/isPurchasing/errorMessage: those are Activity-shaped or UI-only
 * concerns that would force an `android.app.Activity` reference into this zero-Android-SDK
 * module (`BillingClient.launchBillingFlow` requires one). That surface lives instead on
 * `:data:billing`'s concrete `BillingManager`, injected directly by `:feature:paywall` only —
 * see android/TODO.md item 8 "Why two repositories."
 *
 * Implemented by `:data:billing`'s `BillingManager`.
 */
interface PremiumRepository {

    /**
     * Seeded synchronously from a cached DataStore boolean at construction (mirrors iOS
     * `PersistenceService.cachedIsPremium`) so a returning subscriber reads `true` before Play
     * Billing's own async entitlement query resolves. Not a security boundary — Play Billing's
     * purchase verification remains the source of truth; this only prevents a paywall flicker.
     */
    val isPremium: StateFlow<Boolean>

    /** True while any auto-renewable subscription (Monthly or Yearly) is currently active. */
    val hasActiveSubscription: StateFlow<Boolean>

    /**
     * True once the first entitlement query has actually completed this process. Lets a caller
     * distinguish "confirmed not premium" from "not resolved yet" — see
     * `PhotoStackViewModel.shouldBlockSwipeForPaywall`'s exact iOS analogue for why this guard
     * exists (a fresh-install cold-start race must never block a real subscriber).
     */
    val hasResolvedEntitlements: StateFlow<Boolean>
}
