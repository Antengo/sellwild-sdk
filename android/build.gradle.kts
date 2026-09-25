import java.util.concurrent.Callable

plugins {
    // Plugin versions for standalone builds are pinned in settings.gradle.kts.
    // When this module is included as a subproject (e.g. samples/demo-app),
    // the host build's plugin classpath supplies the versions.
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("maven-publish")
    // Coverage: Kover line/branch report for the unit tests
    // (scripts/coverage/android.sh). Test tooling only; the AAR is unchanged.
    id("org.jetbrains.kotlinx.kover") version "0.9.1"
    // Kotlin lint: detekt plus its ktlint wrapper (detekt-formatting), one tool.
    // Version inline, like kover: a host build that includes this module does
    // not have detekt on its plugin classpath, so a settings.gradle.kts pin
    // (which a host never reads) would leave the id unresolvable there.
    // Lint tooling only; the AAR is unchanged.
    id("io.gitlab.arturbosch.detekt") version "1.23.8"
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
        // Gate: ./gradlew lintDebug. Existing issues are in the baseline; any
        // new warning or error fails (warningsAsErrors + abortOnError).
        // Refresh the baseline only when issues go away: updateLintBaselineDebug.
        lintConfig = file("config/lint/lint.xml")
        baseline = file("config/lint/lint-baseline.xml")
        abortOnError = true
        warningsAsErrors = true
        // Lint runs in the gate (lintDebug), not inside release/publish builds:
        // publishing the AAR must not depend on lint.
        checkReleaseBuilds = false
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

    sourceSets {
        // Cross-platform contracts (schemas, fixtures, golden vectors) ride the
        // unit-test classpath, so tests load them as resources
        // (support/FixtureLoader.kt). A missing dir is fine.
        getByName("test").resources.srcDir("../contracts")
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
    // Resolved from https://maven.sellwild.com/releases (see settings.gradle.kts),
    // the repo partners already add for com.sellwild:sdk, so the published POM's
    // transitive fork deps resolve with no extra setup. Don't use the JitPack
    // coordinate here: partners don't have jitpack.io, so the release POM would
    // fail to resolve for them.
    // 3.3.2-sw4: cumulative Sellwild fork patches on the rendering BannerView —
    // sw1 exposes multiformat (banner+video) for prebidOnly outstream; sw2 makes
    // BasicParameterBuilder honor the VideoParameters on the rendering path; sw3
    // adds getCreativeWidth()/getCreativeHeight() so prebidOnly multi-size slots
    // (e.g. 300x250 + 320x50) can shrink to the won creative instead of holding
    // the reserved bounding box; sw4 substitutes the ${AUCTION_PRICE} macro in
    // bid.burl (billing URL) and emits device.geo.country in ISO alpha-3
    // (see Antengo/prebid-mobile-android).
    implementation("com.sellwild:PrebidMobile-core:3.3.2-sw4")
    implementation("com.sellwild:PrebidMobile-gamEventHandlers:3.3.2-sw4")
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
    // Robolectric for Uri / SharedPreferences / Looper / View shells. Plain
    // JUnit tests keep the android.jar stubs (isReturnDefaultValues above).
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("io.mockk:mockk:1.13.17")
    // Validates mock factories against ../contracts/schemas (JSON Schema 2020-12).
    testImplementation("com.networknt:json-schema-validator:1.5.6")
    // The existing JUnit 4 tests run unchanged on the vintage engine; the
    // launcher API is for support/NetworkBlockSessionListener.kt.
    testImplementation("org.junit.platform:junit-platform-launcher:1.11.4")
    testRuntimeOnly("org.junit.vintage:junit-vintage-engine:5.11.4")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
}

// ── Unit-test harness ────────────────────────────────────────────────────────
// Robolectric runs offline. Gradle resolves the android-all jar for the default
// SDK (src/test/resources/robolectric.properties) and the test JVM never
// downloads it, because unit tests block the network
// (src/test/kotlin/com/sellwild/sdk/support/NetworkBlock.kt).
val robolectricAndroidAll: Configuration by configurations.creating {
    isCanBeConsumed = false
    isTransitive = false
}
dependencies {
    // The pre-instrumented SDK 35 jar Robolectric 4.14.1 asks for
    // (DefaultSdkProvider). Bump it together with the Robolectric version.
    robolectricAndroidAll("org.robolectric:android-all-instrumented:15-robolectric-12650502-i7")
}
val robolectricDepsDir = layout.buildDirectory.dir("robolectric-deps")
val syncRobolectricDeps = tasks.register<Sync>("syncRobolectricDeps") {
    from(robolectricAndroidAll)
    into(robolectricDepsDir)
}
// support/ContractEmitter.kt writes factory output here, and
// contracts/scripts/validate.mjs --out android checks it. SELLWILD_CONTRACT_OUT
// moves the root, as it does for validate.mjs (a relative path resolves from
// this module dir; scripts/coverage/android.sh passes an absolute one).
val contractsOutDir: File = providers.environmentVariable("SELLWILD_CONTRACT_OUT")
    .filter { it.isNotBlank() }
    .map { file(it).resolve("android") }
    .getOrElse(file("../contracts/out/android"))
// support/NetworkBlockAuditListener.kt appends every http/https attempt a test
// did not expect (NetworkBlockRule.expectAttempts) to <task name>.txt here.
val networkAuditDir = layout.buildDirectory.dir("network-block").get().asFile

tasks.withType<Test>().configureEach {
    dependsOn(syncRobolectricDeps)
    // JUnit 4 tests run on the JUnit Platform (vintage engine), so
    // support/NetworkBlockSessionListener.kt blocks the network before the
    // first test class loads, including tests that never opt in.
    useJUnitPlatform()
    // Each Robolectric SDK sandbox holds a full android-all in memory.
    maxHeapSize = "2g"
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", robolectricDepsDir.get().asFile.absolutePath)
    systemProperty("sellwild.contracts.outDir", contractsOutDir.absolutePath)
    outputs.dir(contractsOutDir)

    // A test that tried the network fails the task even when it passed: SDK code
    // swallows the blocked IOException, and a JUnit listener cannot fail a test.
    val networkAudit = File(networkAuditDir, "$name.txt")
    systemProperty("sellwild.test.networkBlock.report", networkAudit.absolutePath)
    outputs.file(networkAudit)
    doFirst { networkAudit.delete() }
    doLast {
        if (networkAudit.isFile && networkAudit.length() > 0) {
            throw GradleException(
                "Unit tests opened network connections they did not expect, or left an HttpStub " +
                    "installed (contract A8). " +
                    "Stub them with support/HttpStub.kt or inject a fake; a test that means to " +
                    "hit the block calls NetworkBlockRule.expectAttempts().\n" + networkAudit.readText(),
            )
        }
    }
}

// ../contracts is a test resource dir. Keep the tests' own output and any node
// tooling off the classpath (out/ would otherwise re-trigger every test run).
tasks.withType<Sync>().matching { it.name.endsWith("UnitTestJavaRes") }.configureEach {
    exclude("out/**", "**/node_modules/**")
}

kover {
    reports {
        filters {
            excludes {
                // R, BuildConfig and the other classes AGP generates.
                androidGeneratedClasses()
            }
        }
        // No verify rule here: scripts/coverage/android-summary.mjs computes the
        // gate (include list + 95% target) from the XML report.
    }
}

// ── Kotlin lint (detekt) ─────────────────────────────────────────────────────
// Gate tasks: detektDebug (main sources, with type resolution, which
// ForbiddenMethodCall needs), detektDebugUnitTest (unit tests, same), and
// detektRnBridge + detektRnBridgePrints (react-native/android/src, see below).
// `./gradlew detektAll` (or `detekt`, or `check`) runs them all. Existing
// findings live in config/detekt/baseline-*.xml; a new one fails the task.
// Refresh the baselines only when findings go away: ./gradlew detektBaseline
val detektVersion = "1.23.8"
detekt {
    toolVersion = detektVersion
    config.setFrom(file("config/detekt/detekt.yml"))
    buildUponDefaultConfig = true
    // Variant tasks read baseline-<variant>.xml next to this file
    // (baseline-debug.xml, baseline-debugUnitTest.xml).
    baseline = file("config/detekt/baseline.xml")
}
dependencies {
    detektPlugins("io.gitlab.arturbosch.detekt:detekt-formatting:$detektVersion")
}
// detekt 1.23.8 embeds the Kotlin 2.0.21 compiler and refuses to run on any
// other. Pin its classpath so no Kotlin alignment from outside (this build's
// Kotlin 2.1.20, or a host build forcing kotlin-stdlib, as samples/demo-app
// does for every configuration) can move it.
configurations.matching { it.name == "detekt" || it.name == "detektPlugins" }.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlin") {
            useVersion(io.gitlab.arturbosch.detekt.getSupportedKotlinVersion())
            because("detekt $detektVersion runs only on the Kotlin compiler it was built with")
        }
    }
}
tasks.withType<io.gitlab.arturbosch.detekt.Detekt>().configureEach {
    jvmTarget = "17"
    reports {
        html.required.set(true)
        xml.required.set(true)
        txt.required.set(false)
        sarif.required.set(false)
        md.required.set(false)
    }
}
tasks.withType<io.gitlab.arturbosch.detekt.DetektCreateBaselineTask>().configureEach {
    jvmTarget = "17"
}

// The React Native bridge (react-native/android) is its own Gradle module that
// builds only inside an RN app, against React Native's classes. detekt reads
// its sources without compiling them, in two passes:
// 1. detektRnBridge: every rule, no classpath (no type resolution). With a
//    partial classpath, unresolved React Native types made UnreachableCode
//    report live code (`config ?: return null` on a ReadableMap?), so the
//    type-resolution rules stay off here. Baseline: baseline-rnBridge.xml.
// 2. detektRnBridgePrints: only detekt.yml (the house rules, not detekt's
//    defaults), with this module's debug classpath (android.jar + Kotlin
//    stdlib). That resolves println/Log.*/PrintStream for ForbiddenMethodCall;
//    no other type-resolution rule runs, so nothing misreads the unresolved
//    React Native types. No baseline: the bridge has no findings; fix new ones.
val rnBridgeSources = file("../react-native/android/src/main")
// Lazy: AGP registers detektDebug only once the variants exist.
val detektDebugClasspath = Callable {
    tasks.named<io.gitlab.arturbosch.detekt.Detekt>("detektDebug").get().classpath
}
val detektRnBridgeBaseline = file("config/detekt/baseline-rnBridge.xml")
val detektRnBridge = tasks.register<io.gitlab.arturbosch.detekt.Detekt>("detektRnBridge") {
    description = "Runs detekt (all rules, no type resolution) on the React Native bridge Kotlin."
    group = "verification"
    setSource(rnBridgeSources)
    include("**/*.kt")
    config.setFrom(detekt.config)
    buildUponDefaultConfig = true
    baseline.set(detektRnBridgeBaseline)
}
tasks.register<io.gitlab.arturbosch.detekt.DetektCreateBaselineTask>("detektBaselineRnBridge") {
    description = "Writes the detekt baseline for the React Native bridge Kotlin."
    group = "verification"
    setSource(rnBridgeSources)
    include("**/*.kt")
    config.setFrom(detekt.config)
    buildUponDefaultConfig.set(true)
    baseline.set(detektRnBridgeBaseline)
}
val detektRnBridgePrints = tasks.register<io.gitlab.arturbosch.detekt.Detekt>("detektRnBridgePrints") {
    description = "Runs the house rules (detekt.yml only) with type resolution on the React Native bridge Kotlin."
    group = "verification"
    setSource(rnBridgeSources)
    include("**/*.kt")
    config.setFrom(detekt.config)
    buildUponDefaultConfig = false
    classpath.setFrom(detektDebugClasspath)
}
val detektAll = tasks.register("detektAll") {
    description = "Runs every detekt gate task: SDK main + unit tests (type resolution) and the RN bridge."
    group = "verification"
    dependsOn("detektDebug", "detektDebugUnitTest", detektRnBridge, detektRnBridgePrints)
}
// The plugin's own `detekt` task (src/main + src/test, no type resolution) is
// wired into `check`. It would report the same findings again against a
// fourth baseline, so it lints nothing itself and runs the gate tasks
// instead: `./gradlew detekt` and `./gradlew check` both mean detektAll, and
// `./gradlew detektBaseline` refreshes all three baselines.
tasks.named<io.gitlab.arturbosch.detekt.Detekt>("detekt") {
    setSource(files())
    dependsOn(detektAll)
}
tasks.named<io.gitlab.arturbosch.detekt.DetektCreateBaselineTask>("detektBaseline") {
    setSource(files())
    dependsOn("detektBaselineDebug", "detektBaselineDebugUnitTest", "detektBaselineRnBridge")
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "com.sellwild"
            artifactId = "sdk"
            version = "1.7.7"

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
