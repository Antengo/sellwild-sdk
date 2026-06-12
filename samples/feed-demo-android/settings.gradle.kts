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
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Prebid Mobile is mirrored on Maven Central, but the canonical release
        // bucket lives here too. Either resolves; mavenCentral first wins.
        maven { url = uri("https://jitpack.io") }
    }
}

rootProject.name = "feed-demo-android"
include(":app")
