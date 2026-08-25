package com.swipy.feature.paywall

import android.app.Activity
import com.swipy.domain.model.PremiumTier

sealed interface PaywallIntent {
    data class SelectTier(val tier: PremiumTier) : PaywallIntent

    /** [activity] is required by `BillingClient.launchBillingFlow` itself. */
    data class Purchase(val activity: Activity) : PaywallIntent
    data object Restore : PaywallIntent

    /**
     * Fired when the share chooser Intent returns control to the app. Unlike iOS's
     * `UIActivityViewController` completion handler, Android's `Intent.createChooser` gives no
     * reliable "user actually completed the share" signal — this fires optimistically the moment
     * control returns, same as the caller's `ActivityResultLauncher` callback firing regardless
     * of which target (if any) was picked. Documented platform limitation, not an oversight.
     */
    data object ShareCompleted : PaywallIntent
}
