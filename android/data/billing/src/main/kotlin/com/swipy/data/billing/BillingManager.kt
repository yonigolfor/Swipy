package com.swipy.data.billing

import android.app.Activity
import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.swipy.domain.model.PremiumTier
import com.swipy.domain.model.TierOffer
import com.swipy.domain.repository.PremiumRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private const val SUBSCRIPTION_PRODUCT_ID = "swipy_premium_subscription"
private const val MONTHLY_BASE_PLAN_ID = "monthly"
private const val YEARLY_BASE_PLAN_ID = "yearly"
private const val LIFETIME_PRODUCT_ID = "swipy_lifetime_purchase"

/**
 * Play Billing Library implementation of [PremiumRepository] — the port of iOS `PremiumManager`.
 * Both product ids above are Play Console configuration this class assumes already exists (see
 * android/TODO.md item 8): one subscription product with two base plans (`monthly`/`yearly` —
 * Play's recommended shape for letting a user upgrade/downgrade between them, the equivalent of
 * iOS's two flat product ids sharing one subscription *group*), and one separate one-time
 * product for Lifetime.
 *
 * Exposes far more than [PremiumRepository]'s three state flows (tiers, isPurchasing,
 * errorMessage, [launchPurchaseFlow]) — those are injected directly and concretely by
 * `:feature:paywall` only, never through the `:domain` interface, since they're either
 * Activity-shaped or UI-only. See `PremiumRepository`'s own doc comment for why.
 */
@Singleton
class BillingManager @Inject constructor(
    @ApplicationContext context: Context,
    private val dataStore: DataStore<Preferences>,
) : PremiumRepository {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Volatile private var productDetailsCache: Map<PremiumTier, ProductDetails> = emptyMap()
    @Volatile private var offerTokens: Map<PremiumTier, String> = emptyMap()

    private val purchasesUpdatedListener = PurchasesUpdatedListener { billingResult, purchases ->
        if (billingResult.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            scope.launch {
                purchases.forEach { handlePurchase(it) }
                _isPurchasing.value = false
            }
        } else {
            _errorMessage.value = billingResult.debugMessage
            _isPurchasing.value = false
        }
    }

    private val billingClient: BillingClient = BillingClient.newBuilder(context)
        .setListener(purchasesUpdatedListener)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    // Seeded false, then set from the cached DataStore value as soon as that first (near-
    // instant, but not literally synchronous — DataStore has no sync read API) collection lands
    // in initialize() below. This is the closest achievable Android analogue of iOS's literal
    // `= PersistenceService.shared.cachedIsPremium` synchronous seed — see android/TODO.md item 8.
    private val _isPremium = MutableStateFlow(false)
    override val isPremium: StateFlow<Boolean> = _isPremium.asStateFlow()

    private val _hasActiveSubscription = MutableStateFlow(false)
    override val hasActiveSubscription: StateFlow<Boolean> = _hasActiveSubscription.asStateFlow()

    private val _hasResolvedEntitlements = MutableStateFlow(false)
    override val hasResolvedEntitlements: StateFlow<Boolean> = _hasResolvedEntitlements.asStateFlow()

    private val _tiers = MutableStateFlow<Map<PremiumTier, TierOffer>>(emptyMap())
    val tiers: StateFlow<Map<PremiumTier, TierOffer>> = _tiers.asStateFlow()

    private val _isPurchasing = MutableStateFlow(false)
    val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    /** Call once from `SwipyApplication.onCreate()` — mirrors iOS touching `PremiumManager.shared`
     * at `didFinishLaunchingWithOptions` so entitlement resolution races the launch pipeline
     * instead of the user's first interactive purchase attempt. */
    fun initialize() {
        scope.launch {
            _isPremium.value = dataStore.data.first()[CACHED_IS_PREMIUM] ?: false
        }
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    // No in-app recovery path for a broken Play Store connection — resolve to
                    // "not premium" rather than hang the swipe-block guard forever.
                    _hasResolvedEntitlements.value = true
                    return
                }
                // Run concurrently, not sequentially — same fix as iOS's own documented
                // hasResolvedEntitlements timing bug (a slow product-catalog fetch must never
                // gate entitlement resolution).
                scope.launch { queryProductDetails() }
                scope.launch { queryPurchases() }
            }

            override fun onBillingServiceDisconnected() {
                // BillingClient recommends a retry-with-backoff reconnect; not implemented here —
                // the next explicit purchase()/restorePurchases() call surfaces a clear error via
                // billingClient's own response code instead of silently retrying in the background.
            }
        })
    }

    private suspend fun queryProductDetails() {
        val subResult = billingClient.queryProductDetails(
            QueryProductDetailsParams.newBuilder()
                .setProductList(
                    listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(SUBSCRIPTION_PRODUCT_ID)
                            .setProductType(BillingClient.ProductType.SUBS)
                            .build(),
                    ),
                )
                .build(),
        )
        val lifetimeResult = billingClient.queryProductDetails(
            QueryProductDetailsParams.newBuilder()
                .setProductList(
                    listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(LIFETIME_PRODUCT_ID)
                            .setProductType(BillingClient.ProductType.INAPP)
                            .build(),
                    ),
                )
                .build(),
        )

        val newProductDetails = mutableMapOf<PremiumTier, ProductDetails>()
        val newOfferTokens = mutableMapOf<PremiumTier, String>()
        val newTiers = mutableMapOf<PremiumTier, TierOffer>()

        subResult.productDetailsList?.firstOrNull()?.let { details ->
            details.subscriptionOfferDetails?.forEach { offer ->
                val tier = when (offer.basePlanId) {
                    MONTHLY_BASE_PLAN_ID -> PremiumTier.Monthly
                    YEARLY_BASE_PLAN_ID -> PremiumTier.Yearly
                    else -> return@forEach
                }
                val price = offer.pricingPhases.pricingPhaseList.firstOrNull()?.formattedPrice
                newProductDetails[tier] = details
                newOfferTokens[tier] = offer.offerToken
                newTiers[tier] = TierOffer(tier, price)
            }
        }
        lifetimeResult.productDetailsList?.firstOrNull()?.let { details ->
            newProductDetails[PremiumTier.Lifetime] = details
            newTiers[PremiumTier.Lifetime] = TierOffer(PremiumTier.Lifetime, details.oneTimePurchaseOfferDetails?.formattedPrice)
        }

        productDetailsCache = newProductDetails
        offerTokens = newOfferTokens
        _tiers.value = newTiers
    }

    private suspend fun queryPurchases() {
        val subs = billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build(),
        )
        val inapp = billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build(),
        )

        var hasPremium = false
        var hasSubscription = false
        for (purchase in subs.purchasesList + inapp.purchasesList) {
            if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) continue
            if (!purchase.isAcknowledged) acknowledge(purchase)
            if (purchase.products.contains(SUBSCRIPTION_PRODUCT_ID)) {
                hasPremium = true
                hasSubscription = true
            } else if (purchase.products.contains(LIFETIME_PRODUCT_ID)) {
                hasPremium = true
            }
        }

        _isPremium.value = hasPremium
        _hasActiveSubscription.value = hasSubscription
        _hasResolvedEntitlements.value = true
        // Every write site for isPremium routes through here, keeping this cache authoritative
        // in both directions — flips true on purchase/restore, self-heals stale-true on
        // expiry/refund/revocation. Same "not a security boundary" caveat as iOS's
        // PersistenceService.cachedIsPremium — Play Billing's own verification is the real source
        // of truth, this only prevents a UI flicker on the next cold start.
        dataStore.edit { it[CACHED_IS_PREMIUM] = hasPremium }
    }

    private suspend fun handlePurchase(purchase: Purchase) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return
        if (!purchase.isAcknowledged) acknowledge(purchase)
        queryPurchases()
    }

    private suspend fun acknowledge(purchase: Purchase) {
        billingClient.acknowledgePurchase(
            AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build(),
        )
    }

    /** [activity] is required by `BillingClient.launchBillingFlow` itself — this is why this
     * method lives here and not on the `:domain` [PremiumRepository] interface. */
    fun launchPurchaseFlow(activity: Activity, tier: PremiumTier) {
        val details = productDetailsCache[tier] ?: return
        _isPurchasing.value = true
        _errorMessage.value = null

        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details)
        if (tier != PremiumTier.Lifetime) {
            val offerToken = offerTokens[tier] ?: run {
                _isPurchasing.value = false
                return
            }
            productParams.setOfferToken(offerToken)
        }

        billingClient.launchBillingFlow(
            activity,
            BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(productParams.build())).build(),
        )
    }

    suspend fun restorePurchases() {
        _isPurchasing.value = true
        _errorMessage.value = null
        queryPurchases()
        _isPurchasing.value = false
    }

    private companion object {
        val CACHED_IS_PREMIUM = booleanPreferencesKey("cached_is_premium")
    }
}
