// :data:billing — Play Billing Library implementation of PremiumRepository (StoreKit 2
// analogue). See android/CLAUDE.md "Core Tech Stack" → "Billing".

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.swipy.data.billing"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(project(":domain"))

    implementation(libs.android.billing.ktx)

    // ProcessLifecycleOwner — re-checks entitlements/reconnects on every app foreground (Play
    // Billing's PurchasesUpdatedListener has no equivalent of iOS's always-live Transaction.updates
    // for purchases that resolve outside the current launchBillingFlow call). Same dependency
    // :core:notifications already uses for its own foreground coordinator.
    implementation(libs.androidx.lifecycle.process)

    // DataStore<Preferences> type only — resolves against :data:datastore's app-wide
    // @Provides binding via Hilt's aggregated graph, same pattern NotificationStateStore
    // already uses. No project(":data:datastore") dependency needed for this.
    implementation(libs.androidx.datastore.preferences)

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.core)

    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)

    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
}
