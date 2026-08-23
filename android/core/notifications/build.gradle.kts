// :core:notifications — SwipyNotificationManager, AlarmManager-backed exact scheduling for the
// swipe-limit-reset/weekly-cleanup/inactivity triggers, and a WorkManager-backed periodic
// worker for the review-bin/milestone/burst checks. See android/TODO.md item 7 for the full
// iOS-parity trigger map this ports (NOTIFICATIONS.md).

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.swipy.core.notifications"
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

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.androidx.lifecycle.process)
    // Only the type (DataStore<Preferences>) is needed here — the actual @Provides binding
    // lives in :data:datastore's DataStoreProvidesModule and resolves via Hilt's app-level
    // aggregated graph; no project(":data:datastore") dependency needed for that to work.
    implementation(libs.androidx.datastore.preferences)

    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)
    implementation(libs.androidx.hilt.work)
    ksp(libs.androidx.hilt.compiler)

    implementation(libs.kotlinx.coroutines.android)
}
