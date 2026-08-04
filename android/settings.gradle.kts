pluginManagement {
    includeBuild("build-logic")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "swipy-android"

include(":app")

include(":core:designsystem")
include(":core:common")
include(":core:testing")

include(":domain")

include(":data:mediastore")
include(":data:datastore")
include(":data:cache")
include(":data:vision")

include(":feature:swipe")
include(":feature:filters")
include(":feature:reviewbin")
include(":feature:paywall")
include(":feature:onboarding")
