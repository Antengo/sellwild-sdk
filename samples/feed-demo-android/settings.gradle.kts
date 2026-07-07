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
        maven { url = uri("https://jitpack.io") }
        // Local Maven for namespace-shaded Prebid Mobile fork (dev only)
        mavenLocal()
    }
}

rootProject.name = "feed-demo-android"
include(":app")
