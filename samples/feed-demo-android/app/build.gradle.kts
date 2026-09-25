plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("io.gitlab.arturbosch.detekt")
}

// The SDK version android/ publishes (its build.gradle.kts), so the sample always
// gets the build just published, never an older one left in mavenLocal. A copy of
// this app outside the repo pins a released version from maven.sellwild.com instead.
val sellwildSdkVersion: String = rootDir.resolve("../../android/build.gradle.kts").readText()
    .let { Regex("""version = "([^"]+)"""").find(it)?.groupValues?.get(1) }
    ?: error("No publication version in android/build.gradle.kts")

android {
    namespace = "com.sellwild.sample"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.sellwild.sample"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
        allWarningsAsErrors = true
    }

    buildFeatures {
        compose = true
        // BuildConfig.DEBUG turns on WebView debugging in debug builds only.
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    lint {
        // ./gradlew lintDebug: any warning fails, as in the SDK.
        lintConfig = file("lint.xml")
        abortOnError = true
        warningsAsErrors = true
    }
}

detekt {
    // The SDK's rules (android/config/detekt), on the sample's sources, then the
    // sample's Compose changes (detekt.yml next to this file).
    config.setFrom(rootDir.resolve("../../android/config/detekt/detekt.yml"), file("detekt.yml"))
    buildUponDefaultConfig = true
}
// detekt 1.23.8 runs only on the Kotlin compiler it was built with: keep this
// build's Kotlin 2.1.20 off its classpath (android/build.gradle.kts does the same).
configurations.matching { it.name == "detekt" || it.name == "detektPlugins" }.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlin") {
            useVersion(io.gitlab.arturbosch.detekt.getSupportedKotlinVersion())
        }
    }
}

dependencies {
    // The SDK as checked out, from mavenLocal (settings.gradle.kts). Its POM brings
    // Prebid Mobile, Google Mobile Ads, RecyclerView and the rest.
    implementation("com.sellwild:sdk:$sellwildSdkVersion")

    // Compose 1.6.8: the version the SDK's Compose wrapper (SellwildFeed) builds against.
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.7.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.6.2")

    detektPlugins("io.gitlab.arturbosch.detekt:detekt-formatting:1.23.8")
}
