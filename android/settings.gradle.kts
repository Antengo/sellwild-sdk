pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    // Pin plugin versions here so the module's build.gradle.kts can use
    // `id("...") apply true` without `version` — that lets the same module
    // be included as a subproject of another build (e.g. the RN demo-app)
    // without "plugin already on classpath with unknown version" conflicts.
    plugins {
        id("com.android.library") version "8.7.3"
        id("org.jetbrains.kotlin.android") version "2.1.20"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "sellwild-sdk"
