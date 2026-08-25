package com.swipy.feature.paywall

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.data.billing.BillingManager
import com.swipy.domain.model.PremiumTier
import com.swipy.domain.model.TierOffer
import com.swipy.domain.repository.SwipeQuotaRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.collections.immutable.toImmutableMap
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * `BillingManager` is injected concretely (not through `:domain`'s `PremiumRepository`) — this
 * screen needs its Activity-taking purchase flow and its products/isPurchasing/errorMessage
 * state, none of which belong on the domain-safe interface. See `PremiumRepository`'s own doc
 * comment and android/TODO.md item 8 "Why two repositories."
 */
@HiltViewModel
class PaywallViewModel @Inject constructor(
    private val billingManager: BillingManager,
    private val swipeQuotaRepository: SwipeQuotaRepository,
) : ViewModel() {

    private val selectedTier = MutableStateFlow(PremiumTier.Yearly)

    @Suppress("UNCHECKED_CAST")
    val uiState: StateFlow<PaywallUiState> = combine(
        billingManager.tiers,
        selectedTier,
        billingManager.isPurchasing,
        billingManager.errorMessage,
        billingManager.hasActiveSubscription,
        swipeQuotaRepository.hasSharedToday,
        billingManager.isPremium,
    ) { values ->
        PaywallUiState(
            tiers = (values[0] as Map<PremiumTier, TierOffer>).toImmutableMap(),
            selectedTier = values[1] as PremiumTier,
            isPurchasing = values[2] as Boolean,
            errorMessage = values[3] as String?,
            hasActiveSubscription = values[4] as Boolean,
            hasSharedToday = values[5] as Boolean,
            isPremium = values[6] as Boolean,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PaywallUiState())

    fun onIntent(intent: PaywallIntent) {
        when (intent) {
            is PaywallIntent.SelectTier -> selectedTier.value = intent.tier
            is PaywallIntent.Purchase -> billingManager.launchPurchaseFlow(intent.activity, selectedTier.value)
            PaywallIntent.Restore -> viewModelScope.launch { billingManager.restorePurchases() }
            PaywallIntent.ShareCompleted -> viewModelScope.launch { swipeQuotaRepository.applyShareBonus() }
        }
    }
}
