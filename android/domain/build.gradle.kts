// :domain — Pure Kotlin module. MUST compile without android.jar (no Android SDK
// dependency) — models, repository interfaces, use cases only. Apply the Kotlin JVM
// plugin here, never the Android library plugin. See android/CLAUDE.md
// "Module dependency rule".
//
// Platform types with no pure-Kotlin equivalent (android.net.Uri, etc.) are represented
// here as primitives (e.g. a raw URI String) — the data/feature layers reconstruct the
// real platform type at the point of use, where android.jar is actually available.

plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.javax.inject)

    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
}
