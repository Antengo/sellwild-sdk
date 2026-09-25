// Sellwild Sample (Android). It builds against the SDK in this repo, published to
// mavenLocal first (README.md):
//   cd android && ./gradlew publishReleasePublicationToMavenLocal
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.application") version "8.7.3"
        id("org.jetbrains.kotlin.android") version "2.1.20"
        id("org.jetbrains.kotlin.plugin.compose") version "2.1.20"
        // The SDK's Kotlin linter and version, run on the sample: ./gradlew detekt
        id("io.gitlab.arturbosch.detekt") version "1.23.8"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // com.sellwild:sdk comes only from mavenLocal: never a released build of the
        // same version from maven.sellwild.com, and nothing else from mavenLocal.
        exclusiveContent {
            forRepository { mavenLocal() }
            filter { includeModule("com.sellwild", "sdk") }
        }
        google()
        mavenCentral()
        // The SDK's Prebid Mobile fork (com.github.Antengo.prebid-mobile-android).
        maven { url = uri("https://jitpack.io") }
        // com.sellwild:omsdk-android, which the Prebid fork needs.
        maven { url = uri("https://maven.sellwild.com/releases") }
    }
}

rootProject.name = "sellwild-sample-android"
include(":app")
