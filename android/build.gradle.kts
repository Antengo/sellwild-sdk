plugins {
    // Plugin versions for standalone builds are pinned in settings.gradle.kts.
    // When this module is included as a subproject (e.g. samples/demo-app),
    // the host build's plugin classpath supplies the versions.
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
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

    buildFeatures {
        // SellwildFeed ships an optional Compose wrapper (SellwildFeed.kt).
        // Compose deps are compileOnly — consumers that already pull Compose
        // (which is most modern apps) get the wrapper for free; consumers
        // that don't pull Compose still get a working AAR with the View-based
        // SellwildFeedView surface.
        // The Kotlin 2.x Compose Compiler plugin (applied above) replaces
        // the legacy composeOptions block.
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
        // Compile with Kotlin 2.1.20 but emit class metadata that older
        // Kotlin compilers can still read. RN 0.74 ships a Kotlin 1.9
        // gradle plugin, and we want a single AAR that works for both
        // 1.9 and 2.x consumers.
        languageVersion = "1.9"
        apiVersion = "1.9"
        freeCompilerArgs = freeCompilerArgs + listOf(
            "-Xskip-metadata-version-check",
        )
    }

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
    //
    // SDK 1.4.1+: Uses namespace-shaded Prebid Mobile fork to avoid singleton
    // conflicts with host apps that have their own Prebid implementation.
    // Package: com.sellwild.prebid (instead of org.prebid.mobile)
    // Main class: SellwildPrebid (instead of PrebidMobile)
    // Published to local Maven during development; JitPack for releases.
    // 3.3.2-sw1: Sellwild patch exposing multiformat (banner+video) on the
    // rendering BannerView so prebidOnly placements can serve outstream video
    // (see Antengo/prebid-mobile-android BannerView.setAdUnitFormats).
    implementation("com.sellwild:PrebidMobile-core:3.3.2-sw1")
    implementation("com.sellwild:PrebidMobile-gamEventHandlers:3.3.2-sw1")
    implementation("com.google.android.gms:play-services-ads:23.6.0")

    // SellwildFeed (1.4.0+) — all-in-one native feed surface.
    // RecyclerView + SwipeRefreshLayout for the list itself; Browser for the
    // Chrome Custom Tabs fallback when the partner doesn't handle onListingTap.
    // No image-loading dep — the SDK uses a small built-in URL-image loader.
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
    implementation("androidx.browser:browser:1.8.0")

    // SellwildFeed Compose wrapper — compileOnly so non-Compose consumers
    // are not forced to pull Compose into their app. Apps that want the
    // wrapper already depend on these themselves.
    compileOnly("androidx.compose.ui:ui:1.6.8")
    compileOnly("androidx.compose.foundation:foundation:1.6.8")
    compileOnly("androidx.compose.runtime:runtime:1.6.8")
    // Tests don't reach the Compose wrapper, but the Compose Compiler plugin
    // still verifies the whole compilation unit, so the runtime has to be
    // on the test classpath for compilation to succeed.
    testImplementation("androidx.compose.runtime:runtime:1.6.8")
    testImplementation("androidx.compose.ui:ui:1.6.8")
    testImplementation("androidx.compose.foundation:foundation:1.6.8")

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
            version = "1.7.5"

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

// Exclude kotlin-stdlib from the published POM. The SDK is compiled with
// Kotlin 2.1.20 but emits 1.9-compatible metadata (apiVersion + languageVersion
// pinned to 1.9). If we ship kotlin-stdlib:2.1.20 in the POM, Gradle's "highest
// version wins" conflict resolution upgrades the entire consumer classpath to
// 2.1.20 stdlib — which breaks RN 0.74 apps that compile with Kotlin 1.9 (the
// compiler can't read 2.1 metadata). The stdlib is provided by the host app's
// Kotlin toolchain anyway.
configurations.all {
    if (name.contains("RuntimeClasspath") || name.contains("CompileClasspath")) {
        // Don't exclude from compile/runtime — we need it to build. Only from publishing.
        return@all
    }
}

afterEvaluate {
    publishing.publications.withType<MavenPublication>().configureEach {
        pom.withXml {
            val deps = asNode()["dependencies"] as? groovy.util.NodeList ?: return@withXml
            val depsNode = deps.firstOrNull() as? groovy.util.Node ?: return@withXml
            depsNode.children().toList().filterIsInstance<groovy.util.Node>().forEach { dep ->
                val groupId = (dep["groupId"] as? groovy.util.NodeList)?.text()
                if (groupId == "org.jetbrains.kotlin") {
                    depsNode.remove(dep)
                }
            }
        }
    }
}
