// :core:designsystem — Compose theme, color tokens (ported 1:1 from the iOS palette),
// typography, shared components. See android/CLAUDE.md "Color Palette".

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.swipy.core.designsystem"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }

    buildFeatures {
        compose = true
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
    implementation(libs.androidx.core.ktx)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.bundles.compose)
    implementation(libs.kotlinx.coroutines.core)

    // HapticManager (haptics/) needs @Singleton/@Inject/@ApplicationContext — this module had
    // no Hilt dependency before that class existed.
    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)
}
