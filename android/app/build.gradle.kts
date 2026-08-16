// :app — Application module. Application class, NavHost graph root, DI graph root,
// manifest merge. Depends on every :feature module. See android/CLAUDE.md "Navigation".
//
// MainActivity hosts a 3-destination NavHost (filters <-> swipe <-> review bin) behind the
// media permission prompt, with PhotoStackViewModel obtained once at NavHost scope and shared
// between the Filters and Swipe destinations — the Android analogue of iOS's single
// @EnvironmentObject VM shared by SmartFiltersView and SwipeStackView.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.swipy.app"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.swipy.app"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.1.0"
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
    implementation(project(":core:notifications"))

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
