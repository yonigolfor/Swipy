// :data:vision — On-device blur/burst analysis engine (no network calls, no third-party ML
// SDK — see android/CLAUDE.md Core Tech Stack, "On-device ML"). Blur detection is a hand-rolled
// variance-of-Laplacian filter; burst similarity is a hand-rolled difference-hash (dHash) —
// both deliberate, documented substitutes for iOS's CIEdges and VNGenerateImageFeaturePrintRequest,
// which have no on-device Android equivalent outside ML Kit (not used here, matching this
// project's zero-network/zero-third-party-ML stance).

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.swipy.data.vision"
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
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.core)

    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)

    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
}
