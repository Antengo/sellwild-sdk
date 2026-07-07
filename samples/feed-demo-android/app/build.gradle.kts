plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.sellwild.feeddemo"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.sellwild.feeddemo"
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
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    // Local AAR — copied from android/build/outputs/aar/sellwild-sdk-release.aar
    implementation(files("libs/sellwild-sdk.aar"))

    // Transitive deps the SDK AAR expects on the consumer classpath.
    // (Local-AAR consumption means we have to declare them by hand;
    // Maven publish wires these up automatically.)
    // Using namespace-shaded Prebid from local Maven (com.sellwild instead of org.prebid)
    implementation("com.sellwild:PrebidMobile-core:3.3.2")
    implementation("com.sellwild:PrebidMobile-gamEventHandlers:3.3.2")
    implementation("com.google.android.gms:play-services-ads:23.6.0")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
    implementation("androidx.browser:browser:1.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // App-side deps
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")

    val composeBom = platform("androidx.compose:compose-bom:2024.09.02")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.foundation:foundation")
}
