plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.1.20"
    id("maven-publish")
}

android {
    namespace = "com.sellwild.sdk"
    compileSdk = 36

    defaultConfig {
        // 1.3.0+: minSdk bumped 21 → 23 because the GMA SDK that ships with
        // Prebid Mobile 3.x requires API 23. Native auction is the default
        // ad path; falling back to API 21 is no longer supported.
        minSdk = 23
        targetSdk = 35

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Native ad path (1.3.0+): Prebid Mobile runs the auction, GMA renders.
    // Both are required dependencies — there is no WebView fallback.
    implementation("org.prebid:prebid-mobile-sdk:3.3.0")
    implementation("com.google.android.gms:play-services-ads:24.7.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "com.sellwild"
            artifactId = "sdk"
            version = "1.3.0-SNAPSHOT"

            afterEvaluate {
                from(components["release"])
            }

            pom {
                name.set("Sellwild SDK")
                description.set("Sellwild mobile advertising SDK for Android")
                url.set("https://github.com/sellwild/sdk-android")
            }
        }
    }
}
