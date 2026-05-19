plugins {
    // Plugin versions for standalone builds are pinned in settings.gradle.kts.
    // When this module is included as a subproject (e.g. samples/demo-app),
    // the host build's plugin classpath supplies the versions.
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
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
}

// Use new compilerOptions DSL (Kotlin 2.0+)
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        // Emit class metadata that older Kotlin compilers can still read.
        // RN 0.74 ships a Kotlin 1.9 gradle plugin, and we want a single
        // AAR that works for both 1.9 and 2.x consumers.
        languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
        apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
        freeCompilerArgs.add("-Xskip-metadata-version-check")
    }
}

android {

    lint {
        targetSdk = 35
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.isReturnDefaultValues = true
        targetSdk = 35
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Native ad path (1.3.0+): Prebid Mobile runs the auction, GMA renders.
    // Both are required dependencies — there is no WebView fallback.
    // GMA pinned to 23.6.0 for compatibility with partners on 22.x/23.x (WeatherBug).
    // Prebid Mobile 3.3.0 supports GMA 23.x.
    implementation("org.prebid:prebid-mobile-sdk:3.3.0")
    implementation("com.google.android.gms:play-services-ads:23.6.0")

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
            version = "1.3.2"

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
