// :app — Application module. Application class, NavHost graph root, DI graph root,
// manifest merge. Depends on every :feature module. See android/CLAUDE.md "Navigation".
//
// MainActivity hosts a 3-destination NavHost (filters <-> swipe <-> review bin) behind the
// media permission prompt, with PhotoStackViewModel obtained once at NavHost scope and shared
// between the Filters and Swipe destinations — the Android analogue of iOS's single
// @EnvironmentObject VM shared by SmartFiltersView and SwipeStackView.

import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.ksp)
}

// Release signing — credentials live in keystore.properties (gitignored, see .gitignore).
// Not present in CI/fresh checkouts; the release signingConfig is only registered when found,
// so `assembleDebug`/`bundleDebug` and all Debug-variant work never require it.
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.swipy.app"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        // applicationId (Play Console package name) intentionally differs from `namespace`
        // above (Kotlin source package, unchanged — renaming it would touch every file's
        // package declaration for zero benefit). Set to match the app already created in
        // Play Console.
        applicationId = "com.yonigolfor.swipy"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 3
        versionName = "1.0.0"
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // R8 code shrinking is OFF for now — confirmed via on-device testing (debug-vs-
            // release comparison on the same emulator) that isMinifyEnabled = true causes a
            // real, reproducible crash on launch: "IllegalStateException: CompositionLocal
            // LocalLifecycleOwner not present", thrown from inside the composition triggered by
            // AndroidComposeView.setOnViewTreeOwnersAvailable — i.e. R8 shrinking is corrupting
            // something in the Compose/Hilt/activity-compose ViewTreeLifecycleOwner wiring at
            // Activity startup. Ruled out android.enableR8.fullMode=false (still crashed after a
            // full --rerun-tasks clean rebuild), so this isn't the common "full mode class
            // merging" issue — it's a genuine missing-keep-rule-shaped bug that needs proper R8
            // dump/-printusage investigation, not a guess under time pressure. Play Store does
            // not require shrinking; correctness of an uploadable build outweighs the download-
            // size win here. Revisit with isMinifyEnabled = true once the real cause is found —
            // proguard-rules.pro already exists for that work.
            isMinifyEnabled = false
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
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
    implementation(project(":domain"))
    implementation(project(":core:designsystem"))
    implementation(project(":data:mediastore"))
    implementation(project(":data:datastore"))
    implementation(project(":data:vision"))
    implementation(project(":feature:swipe"))
    implementation(project(":feature:reviewbin"))
    implementation(project(":feature:filters"))
    implementation(project(":feature:onboarding"))
    implementation(project(":feature:paywall"))
    implementation(project(":core:notifications"))
    implementation(project(":data:billing"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.hilt.navigation.compose)
    implementation(libs.androidx.navigation.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.bundles.compose)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)
    implementation(libs.androidx.hilt.work)
    implementation(libs.androidx.work.runtime.ktx)

    implementation(libs.kotlinx.coroutines.android)
    // PhotoStackUiState.stack is a PersistentList (see feature:swipe's own doc comment) — needed
    // here too now that SwipyNavHost reads it directly to decide whether to trigger an initial
    // LoadPhotos. :feature:swipe declares this as `implementation`, which doesn't propagate to
    // this module's compile classpath.
    implementation(libs.kotlinx.collections.immutable)
}
