# Coverage and verification

Branch `feat/testing/2026-09-23-log-failure-coverage`, measured 2026-09-25. Suite times and the fastest checks are in [TESTING.md](TESTING.md).

## Merge of origin/main (2026-09-25)

origin/main (PRs #74-#81) removed the Flutter SDK (df551f7) and the SDK's WebView widget and banner paths (9ff579f). This branch merged it (no rebase). What went with them:

1. Flutter: flutter/** and its tests, the flutter-analyze and flutter-coverage gate steps, scripts/coverage/flutter*, coverage-summary/flutter.json, the Dart failure-code mirror, drift/flutter.json and the Flutter print-gate roots.
2. WebView widget and banner: SellwildWidgetView (iOS, Android), SellwildWidget, htmlBuilder, bannerHtml and widgetBridge (React Native), the pure widget cores (SellwildWidgetPage, WidgetPage), their tests and factories, the bridge-message schema and fixtures, and the react-native-webview test stub and dev dependency.
3. Failure codes: 15 codes nothing emits any more were removed from failure-codes.json; `flutter` is no client, and widget.script_load.network and widget.webview_load.http list only the web widget. Their phase-1 points map to the new `removed` exclusion.
4. Kept, per origin: SellwildWebViewCompat (Android, d6aa615), now on a pure helper with its own tests, and the no-op widget config fields (2bee67c).

The Flutter and widget entries in the appendix below are history.

## Coverage

Gate = all runtime code minus the exclusions listed below. Each exclusion has a reason. Branches on iOS are llvm-cov regions, because Swift has no branch data.

| Platform | Gate lines | Gate branches | Gate functions | Whole lines | Whole branches | Whole functions | Exclusions |
|---|---|---|---|---|---|---|---|
| android | 99.17 | 97.08 | 99.56 | 98.74 | 97.01 | 97.44 | 3 |
| core | 100.00 | 100.00 | 100.00 | 100.00 | 100.00 | 100.00 | 1 |
| ios | 98.91 | 98.11 | 98.30 | 98.03 | 97.24 | 96.46 | 13 |
| react-native | 98.93 | 98.44 | 100.00 | 98.93 | 98.44 | 100.00 | 2 |

Regenerate:

```bash
npm --prefix core run coverage:summary   # core + react-native
bash scripts/coverage/android.sh
bash scripts/coverage/ios.sh
```

## Exclusions

### android

1. `android/build/generated/**`: AGP-generated classes (R, BuildConfig, Manifest, data binding). Kover drops them before writing the XML (androidGeneratedClasses() in android/build.gradle.kts). This library compiles none into its own classes today.
2. `android/src/main/kotlin/com/sellwild/sdk/SellwildPrebidMobile.kt`: A10 third-party SDK calls that need a device or the network: the real SellwildAdNetwork, one call each into MobileAds.initialize, SellwildPrebid.initializeSdk, AdManagerAdView.loadAd, BannerAdUnit.fetchDemand, BannerView.loadAd, NativeAdUnit.fetchDemand and PrebidNativeAd.create. Everything around those calls (bootstrap, runBannerAuction, applyEids, the auction and init results) stays in the gate and runs against a fake network.
3. `android/src/main/kotlin/com/sellwild/sdk/SellwildNativeAdView.kt`: A10 third-party SDK calls that need a device or the network: the real NativeAdContent over the fork's PrebidNativeAd, which only the fork's auction cache can create (no public constructor) and whose registerView starts impression and click trackers that fire over the network. The native view binds and registers against a fake in tests.

### core

1. `src/types.ts`: type-only: interfaces and type aliases, compiles to an empty module

### ios

1. `ios/Sources/SellwildSDK/Failures/SellwildFailureCode.swift`: type-only and generated: a String enum of registry raw values, written by contracts/scripts/gen-codes.mjs from contracts/failure-codes.json. No executable regions; SellwildFailureCodeTests checks it against the registry.
2. `ios/Sources/SellwildSDK/SellwildFeedView.swift:135-135`: crash-guard: init(coder:) traps by design (storyboards are not supported).
3. `ios/Sources/SellwildSDK/SellwildFeedView.swift:530-530`: crash-guard: init(coder:) traps by design; the feed registers this cell by class.
4. `ios/Sources/SellwildSDK/SellwildFeedView.swift:623-623`: crash-guard: init(coder:) traps by design; the feed builds the card in code.
5. `ios/Sources/SellwildSDK/SellwildFeedView.swift:733-733`: crash-guard: init(coder:) traps by design; the feed registers this cell by class.
6. `ios/Sources/SellwildSDK/SellwildFeedView.swift:787-787`: crash-guard: init(coder:) traps by design; the feed registers this cell by class.
7. `ios/Sources/SellwildSDK/SellwildHouseAdView.swift:93-93`: crash-guard: init(coder:) traps by design (storyboards are not supported).
8. `ios/Sources/SellwildSDK/SellwildSwiftUI.swift:134-145`: preview: Xcode previews run this; the app and the tests never do.
9. `ios/Sources/SellwildSDK/SellwildPrebidMobile.swift:66-81`: third-party-init: MobileAds.start and SellwildPrebid.initializeSDK need the app's GMA application id and the network; the outcome handlers below are tested.
10. `ios/Sources/SellwildSDK/SellwildPrebidMobile.swift:85-88`: fetch-demand: BannerAdUnit.fetchDemand sends the Prebid Server request.
11. `ios/Sources/SellwildSDK/SellwildNativeAdView.swift:61-61`: crash-guard: init(coder:) traps by design (storyboards are not supported).
12. `ios/Sources/SellwildSDK/SellwildNativeAdView.swift:271-273`: fetch-demand: NativeRequest.fetchDemand sends the Prebid Server request.
13. `ios/Sources/SellwildSDK/SellwildAdView.swift:204-207`: crash-guard: init(coder:) traps by design (storyboards are not supported); the report it sends first is tested through reportUnsupportedInit().

### react-native

1. `ios/**`: RN native bridge glue: needs an RN host app build
2. `android/**`: RN native bridge glue: needs an RN host app build

## How the work was checked

1. Every platform suite passes (last full run 2026-09-25, after the origin/main merge). Type checks pass (tsgo); the widget has 10 pre-existing type errors, all in dead files.
2. The print gate (`contracts/scripts/print-gate.mjs`) is at zero empty catches and one print in shipped runtime code: origin's dev-only console.warn in react-native/src/SellwildFeed.tsx (2f790ce), allowlisted with its ESLint no-console suppression.
3. Every unit was checked by a separate verifier agent: full suites, failure-handling rules, validated factories, honest exclusions, and mutation checks (break the code on purpose, confirm a test fails).
4. logFailure on every client reproduces the same golden vectors (`contracts/golden`) exactly.

## Open items (not done in this branch)

1. Nothing ran on a device yet. Before release, run the iOS and Android sample apps and the RN demo on a simulator/emulator (the `native-first-mobile` loop).
2. The React Native native bridge edits (react-native/ios, react-native/android) are not compiled here; they need an RN host app. The RN package also needs a native SDK release that includes SellwildFailures.
3. An independent code review of the SDK diff was not run.
4. iOS views, verifier: Survivor R1: the per-stack once-a-launch latch for ad.zone.missing is untested. If it collapses to one latch, a later .prebidOnly or native zone-missing report (severity error) is silenced for the whole launch.
5. iOS views, verifier: Survivor R3: 'once per token per launch' for feed.layout.invalid is untested. If the latch collapses to once per launch, a second different unknown COL1 token is never reported.
6. iOS logic: its last fix round was not re-verified by a separate agent (all iOS tests pass).
7. Android views: the Android 6.0 crash (Locale.getDefault(Locale.Category) is API 24+) was fixed by hand after the last verifier ran; not re-verified by an agent (tests pass).
8. rn, test gap (accepted): Three failure sites in the native glue have no test that catches a regression. All three mutants survived (the rule says two or more uncaught mutants is major). There is also no test anywhere, in the repo or in scratch, that shows these codes fire exactly once: Android setExternalUserIds/toEids (bridge.eids.invalid and its catch), Android emit (bridge.event_emit.exception, both view managers), the Android onAfterUpdateTransaction fatal catch (bridge.config.invalid), the Android prewarm catch, the log-and-dedupe of bridge.props.invalid on both platforms, and the iOS view-manager bridge.config.exception log. The only harnesses that exist (r4/swift-rules/main.swift, r4/kt/jvmtest/GlueChecks.kt) live in /private/tmp scratch, not in the repo, so nothing will guard these sites after this session.
9. Semantic drift between platforms is recorded, not changed: contracts/expectations/drift/*.json. origin/main fixed three of the recorded drifts (text IAB_CATS, JS-literal S2S_CONFIG, Android bidder passthrough); their entries are gone.

## Appendix: behavior changes and bugs fixed, per unit

From each unit's report. Every change was made with a test written first.

<details><summary>sdk-flutter-harness: 6 behavior changes, 5 bugs fixed</summary>

1. `flutter/test/sellwild_sdk_configure_test.dart`: Test passes AD_REFRESH_INTERVAL: 30000 and expects Duration(seconds: 30)
1. `flutter/test/support/contract_schemas.dart`: format is enforced at every depth via a custom vocabulary behind an if:{type:string} guard; an unported format or a non-2020-12 $schema throws at compile time
1. `flutter/test/support/contract_schemas.dart`: contractErrors/explainErrors/ajvKeyword/ContractError list errors in ajv's shape, including the errors inside each branch
1. `flutter/test/support/support_self_test.dart`: Round-trip writes <out>/flutter-harness; invalid fixtures need an exact path and keyword; new format, null, compile-error, explainErrors and real-contract anyOf tests; banner message tied to the page script
1. `scripts/coverage/flutter.sh`: Deletes only top-level *.json; deletes the summary at start; always runs validate --out flutter-harness; runs --out flutter once a non-support test calls emitContract (or files exist), else records 'skipped'
1. `scripts/coverage/flutter-summary.mjs`: Adds `contractsHarness` (--contracts-harness)
1. Fixed: Stale test expected AD_REFRESH_INTERVAL in seconds; code and docs use milliseconds
1. Fixed: json_schema 5.2.2 child validators (anyOf/oneOf/allOf/if-then-else/not/contains) never check `format`, so the matcher accepted bad URIs that ajv rejects
1. Fixed: json_schema 5.2.2 throws TypeError (Null is not a subtype of Object) when any custom keyword meets a JSON null; avoided with the if:{type:string} guard
1. Fixed: rm -rf on a caller-controlled path; stale summary left behind when lcov.info was missing
1. Fixed: Header wrongly said every SDK HTTP path takes an injected http.Client

</details>

<details><summary>sdk-ts-harness: 11 behavior changes, 3 bugs fixed</summary>

1. `core/package.json`: "typecheck": "tsgo --noEmit -p . && tsgo --noEmit -p tsconfig.test.json"
1. `react-native/tsconfig.json`: module esnext, moduleResolution bundler, lib [ES2018, DOM]
1. `core/package.json`: "typecheck": "tsgo --noEmit -p . && tsgo --noEmit -p tsconfig.test.json"; test, coverage and coverage:summary scripts; devDependencies vitest ~3.2.7, @vitest/coverage-v8 ~3.2.7, ajv ^8, ajv-formats ^3, @typescript/native-preview. The build (tsc) and test:smoke scripts are unchanged
1. `core/package-lock.json`: root "version": "1.7.7" (twice), plus the new devDependency tree
1. `react-native/package-lock.json`: root "version": "1.7.7", plus the new devDependency tree
1. `react-native/package.json`: typecheck, test and coverage scripts; adds devDependencies vitest, @vitest/coverage-v8, react 18.3.1, react-test-renderer 18.3.1, @types/react-test-renderer, ajv, ajv-formats, @typescript/native-preview, react-native-webview ~13.6.4 (types only; aliased to a stub in tests). react-native is not installed. peerDependencies, files and version are unchanged
1. `react-native/tsconfig.json`: module esnext, moduleResolution bundler, lib [ES2018] (no DOM), files [test/stubs/rn-globals.d.ts]
1. `react-native/test/setup.ts`: the fetch blocker records the call and returns Promise.reject(new Error('network blocked in tests: <url>')). XHR, WebSocket and sendBeacon still throw. afterEach still fails a test that made a blocked call
1. `core/package.json`: "typecheck": "tsgo --noEmit -p . && tsgo --noEmit -p tsconfig.test.json"; adds test, coverage, coverage:summary; build (tsc emit) and test:smoke unchanged
1. `react-native/tsconfig.json`: module esnext, moduleResolution bundler, lib ES2018, files test/stubs/rn-globals.d.ts (declares crypto.randomUUID only)
1. `core/test/setup.ts`: the fetch blocker returns a rejected promise (XHR, WebSocket and sendBeacon throw), the same way a real fetch fails, so source .catch handlers run
1. Fixed: (lane's own, round 0) Stub state leaked across tests when a test imported a fresh copy after vi.resetModules(). Now shared on globalThis and reset for every copy.
1. Fixed: (lane's own, round 0) The swallowed-error test depended on test order through the remote-config cache. A beforeEach now clears the cache.
1. Fixed: (lane's own, round 0) It ignored the gate run's exit code and could summarize stale coverage output. It now deletes coverage/ first, checks file freshness, and records exit codes and thresholdsMet.

</details>

<details><summary>sdk-ios-harness: 3 behavior changes, 7 bugs fixed</summary>

1. `scripts/coverage/ios.sh`: It exports TEST_RUNNER_SELLWILD_NETWORK_LEFTOVERS=.coverage-tmp/ios-network-leftovers.txt and deletes that file first. If the file exists after the tests, it prints it, records networkLeftovers in ios.json, and exits 1. out/ios now always holds at least 1 SDK-produced payload, so validation passes.
1. `scripts/coverage/ios-summary.mjs`: A missing file is reported as a problem and a note, and it fails --enforce. The note lists what the blocker does and does not see. A new --network flag becomes networkLeftovers in the summary.
1. `ios/Tests/SellwildSDKTests/Support/NetworkBlocker.swift`: In testBundleDidFinish, leftover requests are appended to leftoversFile(). If that write fails, the run ends with fatalError, since XCTest can no longer fail a test and printing is not allowed. Failure messages mark requests that started outside the running test as 'reported late'.
1. Fixed: ios.sh exited 1 once contracts/scripts/validate.mjs existed, because no iOS test wrote to contracts/out/ios. Fixed: ContractOutputTests emits the real SellwildAPIClient events POST body as events-batch.sdk-ad-error.json.
1. Fixed: A file missing from the llvm-cov export silently counted 0/0 regions and functions. Fixed: it is now reported as a problem and a note.
1. Fixed: The note overclaimed network safety. Fixed: it now lists what the blocker covers and what it does not.
1. Fixed: testResetClearsHandlerAndRequests could not detect a reset that failed to clear captured requests. Fixed: it captures 1 request before reset().
1. Fixed: Requests after a test's teardown-block check were blamed on the next test with no hint, and requests after the last test were never reported. Fixed: the timing is documented, late requests are marked, and a bundle-end leftovers file is checked by ios.sh.
1. Fixed: `defer { try? ... }` silently ignored a cleanup error. Fixed: it is now a throwing addTeardownBlock.
1. Fixed: A self-test depended on the name field in contracts/package.json. Fixed: it now reads schemas/events-batch.schema.json and asserts type == array.

</details>

<details><summary>sdk-android-harness: 6 behavior changes, 7 bugs fixed</summary>

1. `android/settings.gradle.kts`: also declares maven { url = uri("https://maven.sellwild.com/releases") }
1. `android/build.gradle.kts`: Unit tests run on the JUnit Platform (vintage engine; JUnit 4 tests unchanged) with a 2g test heap. NetworkBlockSessionListener blocks all http/https JVM-wide before the first test. Robolectric runs offline from build/robolectric-deps.
1. `android/build.gradle.kts`: Every Test task passes sellwild.test.networkBlock.report. Its doLast step throws a GradleException listing each unexpected attempt, and each HttpStub left installed, that support/NetworkBlockAuditListener.kt recorded. This covers tests with or without the rule, and attempts made between tests (for example a fire-and-forget flush).
1. `android/build.gradle.kts`: The out dir is $SELLWILD_CONTRACT_OUT/android when that is set and not blank, else ../contracts/out/android. The test JVM gets it through sellwild.contracts.outDir.
1. `scripts/coverage/android.sh`: It makes SELLWILD_CONTRACT_OUT absolute, exports it, and cleans and validates <root>/android. ContractOutputTest now emits the real SDK events-batch body, so validation passes and the script exits 0. On a contract failure it prints a message and exits 1.
1. `android/src/test/kotlin/com/sellwild/sdk/support/NetworkBlock.kt`: The handler first asks the installed HttpStub (shared JVM-wide as a java.util.function.Function in the system properties, so Robolectric's sandbox reaches it). It blocks and records the attempt only when no stub answers. NetworkBlockRule.expectAttempts() also sets a JVM-wide expected flag, which the audit listener reads.
1. Fixed: The maven.sellwild.com/releases repo was missing, so a clean machine could not resolve com.sellwild:omsdk-android:1.4.1 (a transitive dep of the Prebid fork)
1. Fixed: The acceptance script exited 1 once contracts/scripts/validate.mjs existed, because no Android test emitted into contracts/out/android and validate.mjs --out fails on an empty dir.
1. Fixed: SELLWILD_CONTRACT_OUT was ignored, so validate.mjs and the Gradle emitter could use different dirs.
1. Fixed: The SDK test passed without robolectric.properties, because the manifest targetSdk is also 35. It now asserts the file is on the classpath with sdk=35.
1. Fixed: Kotlin warning: 'inferred type is ClassLoader? but ClassLoader was expected'.
1. Fixed: Attempts from tests without NetworkBlockRule were blocked but never reported. NetworkBlockAuditListener plus the Gradle doLast check now report them.
1. Fixed: The summary did not say that the phase-1 gate candidates RnGeo.kt and RnPrebidServer.kt are dropped from the gate.

</details>

<details><summary>sdk-android-logfailure: 21 behavior changes, 6 bugs fixed</summary>

1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (SellwildAPIClient.parseListing, L256-264)`: optTextOrNull(): isNull(key) -> null, else optString().ifEmpty { null }. tapUrl falls back to https://sellwild.com/product/{id}?p=...
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt (configure)`: Same fallback config, plus one logFailure: config.fetch.http (non-2xx, httpStatus and msg 'HTTP <n>'), config.fetch.timeout (SocketTimeoutException), config.fetch.parse (JSONException) or config.fetch.network (anything else, e.g. IOException or SecurityException). Component remoteConfig, url host only. setContext(partnerCode) runs before the fetch. After overrides it sets partnerCode, debug and the raw EVENTS_ENABLED/FAILURES_ENABLED/FAILURES_SAMPLE_RATE (JSON null reads as unset).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt (prewarm)`: SellwildFailures.attach(context) first: creates the shared events queue and sends any failures held since configure()
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (SellwildEventQueue)`: Internal primary constructor(uidProvider, sender, clock, dispatcher); public constructor(Context) unchanged. push/track take attributes: Map<String, Any?>? = null. An internal track(SellwildEvent) keeps a prebuilt uid and createdTime. buildBatchJson() is extracted as a pure function with byte-identical stamping. flush(): Unit counts failed POSTs (thrown or non-2xx) in internal failedPosts, still with no retry and no logging. shared() attaches logFailure when it creates the queue. Still one POST per track().
1. `android/src/main/kotlin/com/sellwild/sdk/failures/* (new public API)`: SellwildFailures (log / setContext / setWrapper / attach / resetForTests / context), SellwildFailureContext, SellwildFailureCode (57 codes + ALL), SellwildFailureComponent, SellwildFailureSeverity, SellwildLog (debug logger, Logcat tag 'Sellwild', no-op unless debug)
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: optTextOrNull checks isNull first, so JSON null gives remoteUrl=null and tapUrl falls back to the product page.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: Injected sender, uid provider, clock and dispatcher. buildBatchJson() is pure and builds the same body. push/track take an optional attributes map. A failed or non-2xx POST is counted in failedPosts and dropped (no retry, never logged). flush returns Unit. Still one POST per track() call.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: Creating the queue also attaches logFailure (outside the lock), which sends failures held since before any Context existed.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: Same fallback. A non-2xx response is also reported once as config.fetch.http (with httpStatus and host), and a thrown error as config.fetch.timeout/parse/network. Before the fetch it sets partnerCode and clears eventsEnabled/failuresEnabled/failuresSampleRate. After it, it sets the partner, debug and the raw EVENTS_ENABLED/FAILURES_ENABLED/FAILURES_SAMPLE_RATE.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: prewarm() first calls SellwildFailures.attach(context), then bootstrap. The return value is unchanged.
1. `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailures.kt`: bind() reads the uid once, before any change and outside the lock. If it fails, nothing is bound and the held calls stay held. record() reuses the cached uid.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: optTextOrNull (an isNull check) gives remoteUrl = null, so tapUrl falls back to https://sellwild.com/product/{id}?p=...
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: push/track(event, action, label, attributes: Map<String, Any?>? = null) with @JvmOverloads. Java gets the 1-, 2-, 3- and 4-argument overloads, so the old 3-argument Java signature still exists. Kotlin callers compiled against the old AAR that used defaults call the push$default/track$default synthetic, whose signature changed, so they must recompile.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: flush() returns Unit. The POST goes through the injected SellwildEventSender (production: HttpEventSender, same headers, timeouts and drain). The body comes from the pure buildBatchJson(). A failed POST is counted in the internal failedPosts and dropped (no retry, no log), the same drop as before. The primary constructor is internal and injects uid provider, sender, clock and dispatcher; the public constructor(context) is unchanged.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: Creating the shared queue also attaches logFailure (SellwildFailures.attachQueue), which sends failures held since configure().
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: Each fetch first calls SellwildFailures.attach(context) on Dispatchers.IO. It is idempotent and never throws. The first fetch creates the shared events queue, which reads or writes _sw_uid in SharedPreferences, and sends held failures.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: Still events on, and it now logs config.remote_values.parse (component remoteConfig, severity warn, with the JSONException).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: It returns the same fallback config, and logs once through logFailure: config.fetch.http (with httpStatus, host widget.sellwild.com), config.fetch.network, config.fetch.timeout or config.fetch.parse. It sets the failure context: the partner before the fetch (remote flags reset to unset), then the partner, debug, and the raw EVENTS_ENABLED, FAILURES_ENABLED and FAILURES_SAMPLE_RATE values after it.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: prewarm calls SellwildFailures.attach(context) first, then bootstraps.
1. `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailures.kt`: At attach, held calls are dropped when the current EVENTS_ENABLED value coerces to off. Call-time EVENTS_ENABLED off still drops through the gate, so the stricter of the two wins. FAILURES_ENABLED and the sample rate still come from the call-time context.
1. `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailures.kt`: That printer failure also increments internalErrorCount. It is not echoed again.
1. Fixed: JSON null remote_url parsed to the text "null" on a device (Android org.json optString), so tapUrl opened "null" for dataSourceId 31 listings. Confirmed by a Robolectric test on the real weatherbug listings sample (7 affected ids).
1. Fixed: A JSON null remote_url became the text "null" on a device (org.json optString), and tapUrl opened "null" for dataSourceId 31 listings.
1. Fixed: A feed-only or listings-only app never attached logFailure, so the config.fetch.* failures held since configure() were never sent.
1. Fixed: Held failures replayed when shared() created the queue went out before SellwildAdView set queue.enabled, so they bypassed an EVENTS_ENABLED=false loaded after the failure.
1. Fixed: internalError ignored a printer that threw while echoing an internal error.
1. Fixed: SellwildEvents.isEnabled silently swallowed a remote JSON parse error (runCatching.getOrNull). It now logs config.remote_values.parse.

</details>

<details><summary>sdk-core-logfailure: 10 behavior changes, 0 bugs fixed</summary>

1. `core/src/config.ts`: Both call eventQueue.setEnabled(coerceFlag(config.eventsEnabled, true)) after the fetch; EVENTS_ENABLED=false stops TS event POSTs (an undefined override keeps events on)
1. `core/src/config.ts + core/src/event-queue.ts`: configure()/buildConfigWithRemote set eventQueue.setPartnerCode(partnerCode) before the fetch; push() fills attributes.code when the event has none (a caller's own code wins)
1. `core/src/config.ts`: Sets failure context partnerCode before the fetch, then debug (setDebugLogging), eventsEnabled, failuresEnabled, failuresSampleRate after it; debug=true now prints one '[Sellwild] failure ...' line per logFailure call
1. `core/src/remote-config.ts`: Uses contract coerceFlag (ASCII trim/lower only); e.g. ' false' was false, now true
1. `core/src/remote-config.ts + core/src/types.ts + core/src/config.ts`: Mapped to failuresEnabled (coerceFlag, default true) and failuresSampleRate (coerceRate, default 1) on SellwildConfig
1. `core/src/remote-config.ts`: Same return values ({} and no cache on failure; null JSON {} ; non-object JSON still mapped and cached); each failure now reported once: config.fetch.timeout/network/http/parse, config.parse.invalid; caller abort not reported
1. `core/src/api.ts`: Same resolves/rejections and cache behavior; now reports listings.fetch.network, listings.fetch.http (once, even when the non-2xx body then fails to parse), listings.fetch.parse, listings.parse.invalid; caller abort not reported. Implemented as an async helper instead of a .then chain
1. `core/src/api.ts -> core/src/event-queue.ts`: Class in event-queue.ts with injectable deps; createEventQueue, EventQueue/EventQueueDeps types and setPartnerCode added; api.ts and index re-export them; eventQueue singleton unchanged; timer check uses !== null
1. `core/src/index.ts`: Exports logFailure, setFailureContext, resetFailuresForTests, getFailureInternalErrors, FAILURE_CODES, FailureCode and types, debugLog, setDebugLogging, isDebugLogging
1. `core/src/failures/index.ts`: Shell cuts message/errMessage to 1000 and stack to 2000 UTF-16 units before the pure core

</details>

<details><summary>sdk-ios-logfailure: 10 behavior changes, 2 bugs fixed</summary>

1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: guard: no fetch, defaults kept, SellwildFailures.log(.configUrlInvalid, component: .configure, severity: .fatal, url: host only).
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: Same fallback, plus exactly one clientFailure per failure: config.fetch.http (status, or 'not an HTTP response'), config.fetch.parse, config.parse.invalid, config.fetch.timeout (URLError.timedOut), config.fetch.network (other errors). A cancelled fetch (URLError.cancelled) is not a failure: SellwildLog.debug only.
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: configure sets partnerCode on SellwildFailures and SellwildAPIClient.shared before the fetch. After overrides it sets the shared client's eventsEnabled (SellwildEvents.isEnabled), the failure context (partnerCode, debug, raw EVENTS_ENABLED/FAILURES_ENABLED/FAILURES_SAMPLE_RATE) and SellwildLog.isEnabled from the final config. A failed fetch leaves the failure flags unset (on, rate 1).
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: It logs config.url.invalid (fatal, component configure) and keeps the defaults.
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: Each one calls SellwildFailures.log once (config.fetch.network / .timeout / .http / .parse, config.parse.invalid). A cancelled fetch is not logged; it goes to the SellwildLog debug trace. The fallback is unchanged.
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: configure sets partnerCode on the events client and the failure context before the fetch. After overrides it applies partnerCode, eventsEnabled, the FAILURES_* raw values and the debug flag (SellwildFailures and SellwildLog).
1. `ios/Sources/SellwildSDK/SellwildAPI.swift`: Both are computed properties backed by an NSLock. The public name, type and get/set are the same.
1. `ios/Sources/SellwildSDK/SellwildAPI.swift`: A clientFailure event that already carries code keeps it. Every other event is stamped as before.
1. `ios/Sources/SellwildSDK/SellwildAPI.swift`: It goes through an injected SellwildEventTransport and SellwildEventClock. The defaults are .session(session) and .system (the same URLSession and a DispatchSource timer), so behavior is unchanged. The public init(session:) is kept.
1. `ios/Sources/SellwildSDK/Failures/SellwildFailures.swift`: resetForTests() is public. The live dependencies are live(client: = .shared), so a test can bind them to a capturing client.
1. Fixed: Force-unwrapped remote config URL (crash before iOS 17). Line number is from the original file.
1. Fixed: Empty catch that silently swallowed every remote config fetch failure (network, timeout, non-2xx, bad JSON). Line number is from the original file.

</details>

<details><summary>sdk-flutter-logfailure: 12 behavior changes, 4 bugs fixed</summary>

1. `flutter/lib/src/sellwild_models.dart`: Numbers and bools are read as text ('38', 'true'). has_photo accepts true, 1, '1' and 'true'. distance accepts numeric text. Any other wrong type reads as absent (default '' or null). fromJson never throws on a Map.
1. `flutter/lib/src/sellwild_api.dart`: sendEvent never throws: a thrown or non-2xx POST is counted in failedEventSends and never logged. uid is optional (default: the process v4 UUID). createdTime and the clock are injectable. It sends nothing when eventsEnabled is false (set by configure). It stamps attributes.code = partnerCode when the event has none; a caller's code wins. type and sdkVersion still win.
1. `flutter/lib/src/sellwild_api.dart`: Every failure is reported once through logFailure (listings.fetch.network/timeout/http/parse, listings.parse.invalid, listings.client.missing after dispose), then thrown as before. The same error types still reach callers. A missing rs is reported as listings.parse.invalid and dropped entries as listings.item.invalid (warn); the results are unchanged. There is a public constructor SellwildAPIClient({client, clock, uid}). instance is now a getter with a @visibleForTesting setter.
1. `flutter/lib/src/sellwild_sdk_configure.dart`: The partner is set in the failure context and on SellwildAPIClient.instance before the fetch. Each failed step is reported once (config.fetch.network/timeout/http/parse, config.parse.invalid, config.apply.exception) and defaults are kept as before. An overrides throw is reported as config.overrides.exception and rethrown, so callers still get it. apply coerces the 3 switches into SellwildConfig; absent or null keeps base. After overrides, configure sets the failure context (partner, debug, switches) and the events client's partnerCode and eventsEnabled. apply(raw, base, {bool? isAndroid}) reads Platform.isAndroid only when isAndroid is omitted.
1. `flutter/lib/src/sellwild_config.dart`: New const-constructor fields: eventsEnabled = true, failuresEnabled = true, failuresSampleRate = 1.0. toJson is unchanged.
1. `flutter/lib/sellwild_sdk.dart`: Also exports SellwildFailures, SellwildFailureContext, SellwildFailureSink, ClientFailureEvent, SellwildFailureCode, SellwildFailureComponent and SellwildFailureSeverity. The pure-core helpers are not exported.
1. `flutter/lib/src/sellwild_models.dart`: String, num and bool values read as text (bool true -> 'true', 19.5 -> '19.5', 20.0 -> '20.0'). An object or array where a scalar belongs, a non-object user, non-array photos, an object has_photo and a bool or object distance still throw TypeError, as before.
1. `flutter/lib/src/sellwild_models.dart`: has_photo: a bool; any non-zero number (2 and NaN included) is true; text 'true' or '1' (trimmed, any case) is true; other text and absent are false. distance: a number, or text parsed with double.tryParse (non-numeric text gives null, like displayPrice).
1. `flutter/lib/src/sellwild_api.dart`: Each unreadable item is dropped. A response with any such items reports listings.item.parse once, with the count and the first error, and the other items are returned. Non-object entries report listings.item.invalid (warn). A missing rs reports listings.parse.invalid and returns an empty feed. Network, timeout, disposed, HTTP, JSON and shape failures are each reported once, then thrown as before.
1. `flutter/lib/src/sellwild_api.dart`: The constructor takes client, clock and uid (defaults: real client, wall clock, a process-lifetime Random.secure UUID v4). `instance` has a @visibleForTesting setter. sendEvent never throws, counts failed sends in failedEventSends and never reports itself. uid is optional. attributes.code is stamped from partnerCode (a caller's code wins). The client-level eventsEnabled switch is honored.
1. `flutter/lib/src/sellwild_sdk_configure.dart`: Each failure is reported once (config.fetch.network/timeout/http/parse and config.parse.invalid with component remoteConfig; config.apply.exception with component configure), and the defaults are still returned. The partner is set in the failure context and on the API client before the fetch. The resolved debug and kill switches are passed on after overrides. A throwing overrides callback is reported as config.overrides.exception and rethrown. configure passes isAndroid from SellwildSDK.isAndroidHost into apply.
1. `flutter/lib/src/sellwild_config.dart`: New eventsEnabled (default true), failuresEnabled (default true) and failuresSampleRate (default 1.0). apply fills them from EVENTS_ENABLED, FAILURES_ENABLED and FAILURES_SAMPLE_RATE with contract coercion (coerceFlag/coerceRate). Absent or JSON null keeps the base values.
1. Fixed: SellwildListing.fromJson threw TypeError on bool shippable and numeric price/strikePrice/id in 4 of 5 real listing caches, so fetchListings failed for every real feed.
1. Fixed: Round-1 verifier: an invalid body with no rs and a bad config was reported twice (listings.parse.invalid twice). All casts now run before any report.
1. Fixed: Round-1 verifier: the first crash fix turned any wrong type into an absent value without a report. The throws are restored, and fetchListings now reports listings.item.parse and drops the item.
1. Fixed: sendEvent's failed POST was an unhandled Future error when the caller did not await it.

</details>

<details><summary>sdk-rn-logfailure: 4 behavior changes, 1 bugs fixed</summary>

1. `react-native/src/SellwildWidget.tsx`: It first calls logFailure({ code: 'bridge.script.exception', component: 'webview', message }) (core sanitizes the message; URLs are cut to their host), then calls onError with the raw message as before.
1. `react-native/src/SellwildWidget.tsx`: It first calls logFailure({ code: 'widget.webview_load.network', component: 'webview', error: description, message: '<domain> <code>' such as 'NSURLErrorDomain -1009', url }) (only the host is sent), then calls onError as before. A throwing host onError still throws, but the report is already recorded.
1. `react-native/src/failures.ts, react-native/src/index.ts`: Loading src/failures.ts (index.ts and SellwildWidget.tsx import it) calls setFailureContext({ client: 'react-native' }). Every clientFailure event from an RN app now has client 'react-native'.
1. `react-native/ios/SellwildRNModule.swift, SellwildBannerViewManager.swift, SellwildFeedViewManager.swift; react-native/android/.../SellwildSdkPackage.kt`: iOS: SellwildFailures.setWrapper("react-native") runs once, through a static-let token, the first time any of the 3 bridge classes is created. Android: it runs in the SellwildSdkPackage init block. Native failure events now carry wrapper 'react-native'.
1. Fixed: NativeBannerProps.style was typed ViewStyle, but the component passes [containerStyle, style], an array. npm run typecheck failed with TS2559 at line 168 before any change in this lane. Changed to StyleProp<ViewStyle>, as SellwildFeed already uses. Type only, no runtime change.

</details>

<details><summary>sdk-contracts-prep: 29 behavior changes, 24 bugs fixed</summary>

1. `core/src/failures/index.ts`: When the stack is over 2000 units and starts with '<name>: <message>' (or '<name>' alone when the message is empty) followed by a newline or the end of the text, the header is removed before the cut, so the frames are sent. The cut still applies when the name is not text.
1. `ios/Sources/SellwildSDK/Failures/SellwildFailures.swift`: SellwildFailures.capInput keeps the first 1000 UTF-16 units. A surrogate pair split by the cut ends as U+FFFD, the same text TS, Kotlin and Dart produce.
1. `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailures.kt`: capInput cuts message and errMessage to 1000 UTF-16 units and the stack to 2000.
1. `flutter/lib/src/failures/sellwild_failure_code.dart`: Removed, because the registry no longer lists flutter for config.url.invalid. No lib or test code used it. It was added in phase 2 and never released.
1. `contracts/failure-codes.json`: 220 codes. widget.webview_load.http added (webview, error; react-native, ios, android, widget). config.url.invalid clients are ios only. The core, iOS and Android mirrors gained the new constant: FAILURE_CODES entry, .widgetWebviewLoadHttp, WIDGET_WEBVIEW_LOAD_HTTP.
1. `contracts/expectations/app-config.expected.json`: Cases hold only file and expected. Drift lives in expectations/drift/<platform>.json. RN bridge drift is in drift/react-native.json under other.bridge.android and other.bridge.ios.
1. `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailures.kt`: capInput cuts message and errMessage to 1000 UTF-16 units and the stack to 2000. The tests now pin 2000 from both sides.
1. `contracts/failure-codes.json`: 220 codes. widget.webview_load.http added (webview, error; react-native, ios, android, widget). config.url.invalid clients are ios only. The core, iOS and Android mirrors gained the new constant.
1. `contracts/scripts/lib/registry.mjs`: validateRegistry reports '[i] ?: the entry must be a JSON object' and skips that entry in the order check. breakIfStale returns 'stranded' and leaves the moved lock; withLock's release removes the .lock.stale-* dir only when it holds its own token.
1. `contracts/scripts/gen-codes.mjs`: It exits 1 with 'gen-codes: --contracts-dir needs a value'.
1. `contracts/scripts/lib/registry.mjs`: tryLock writes owner.json into a mkdtemp directory (.lock.new-*) and renames it to .lock. ENOTEMPTY or EEXIST means held, and any other error is thrown after the temp directory is removed. releaseLock renames .lock to .lock.free-* and checks the token before it deletes. An empty .lock directory is not treated as a lock, so it is taken.
1. `contracts/scripts/add-code.mjs`: addCode takes an optional `now` clock, and today() is exported. The CLI output is unchanged.
1. `core/src/failures/index.ts`: When the stack is over 2000 units and starts with the header '<name>: <message>' ('<name>' alone when the message is empty), and a newline or the end of the text follows it, the header is removed before the cut.
1. `ios/Sources/SellwildSDK/Failures/SellwildFailures.swift`: capInput keeps the first 1000 UTF-16 units. A split surrogate pair becomes U+FFFD.
1. `flutter/lib/src/failures/sellwild_failure_code.dart`: It is removed: the registry no longer lists flutter for config.url.invalid. It was never used and never released.
1. `contracts/failure-codes.json`: 220 codes. widget.webview_load.http was added (webview, error; react-native, ios, android, widget). config.url.invalid clients are ios only.
1. `contracts/expectations/app-config.expected.json`: Cases hold only file and expected. Drift is in expectations/drift/<platform>.json.
1. `contracts/scripts/lib/registry.mjs`: '/*' is refused (Kotlin block comments nest). NEVER_LOGGED_RE is /no_?fill|no_?bids?|^events?\./. writeFileAtomic takes tmpDir, and gen-codes passes contracts/ (where *.tmp-* is git-ignored). withLock uses an injectable ops.now and ops.sleep.
1. `contracts/print-gate.allowlist.json`: 19 prints and 1 empty catch, in 5 iOS files.
1. `contracts/scripts/lib/registry.mjs`: The owner file is written into a mkdtemp dir that is then renamed to .lock. Release moves the lock aside and checks the token before deleting it.
1. `core/src/failures/index.ts`: The '<name>: <message>' header is removed before the cut when the stack is over 2000 units.
1. `ios/Sources/SellwildSDK/Failures/SellwildFailures.swift`: capInput keeps the first 1000 UTF-16 units, and a split surrogate becomes U+FFFD.
1. `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailures.kt`: Capped at 1000, 1000 and 2000 UTF-16 units.
1. `contracts/failure-codes.json`: 220 codes: widget.webview_load.http was added. config.url.invalid lists ios only. The Dart mirror dropped configUrlInvalid.
1. Fixed: The input cap sent no stack frames when an Error message was about 2000 units or longer: the V8 header filled the 2000-unit cut, and the pure core then dropped the header.
1. Fixed: No input cap: a long message or localizedDescription went into the regex sanitizer uncut, which can block the calling thread.
1. Fixed: No input cap on message, errMessage or stack before FailuresCore.
1. Fixed: config.url.invalid listed flutter, but it cannot fire on Flutter. Its phase-1 point is now excluded as 'unreachable', and a new registry test checks that every mapped point's platform emits its code.
1. Fixed: Drift that phase 2 fixed was still listed: flutter items throws (7 cases), android nullRemoteUrlIds 'null' text (5 cases), and flutter eventsEnabled 'no mapping' (4 app-config cases). Passing platform tests prove all three fixed.
1. Fixed: The input cap sent no stack frames when an Error message was about 2000 units or longer: the V8 header filled the 2000-unit cut, and the pure core then dropped the header.
1. Fixed: No input cap: a long message or localizedDescription went into the regex sanitizer uncut, which can block the calling thread.
1. Fixed: No input cap on message, errMessage or stack before FailuresCore.
1. Fixed: The stack-cap test put the newline at index 2000, so a 2001 cap only added a newline, which the core drops. The test now also logs a 1999-unit first frame, and 2001 and 1999 both fail it.
1. Fixed: validateRegistry threw TypeError on a null entry (e.g. a hand edit), instead of reporting it.
1. Fixed: A bare --contracts-dir resolved to the cwd without an error.
1. Fixed: config.url.invalid listed flutter, but it cannot fire on Flutter. Its phase-1 point is now excluded as 'unreachable', and a registry test checks that every mapped point's platform emits its code.
1. Fixed: Drift that phase 2 fixed was still listed: flutter items throws (7 cases), android nullRemoteUrlIds 'null' text (5 cases), and flutter eventsEnabled 'no mapping' (4 app-config cases). Passing platform tests prove all three are fixed.
1. Fixed: Ownerless-lock race. In the gap between mkdir and the owner write, a stale-lock breaker that saw a null owner could delete a live lock (null === null). A failed owner write also left an ownerless lock that blocked runs for 120 s. Fixed with the temp-dir-plus-rename acquire and the move-aside release.
1. Fixed: Test gaps: mutations C1, C2, C7, C8, C9, C11 and C13 survived. All 7 are now caught.
1. Fixed: Round 1: the input cap sent no stack frames when an Error message was about 2000 units or longer.
1. Fixed: Round 1: there was no input cap before the regex sanitizer.
1. Fixed: Round 1: there was no input cap on message, errMessage or stack.
1. Fixed: Round 1: config.url.invalid listed flutter, but it cannot fire on Flutter.
1. Fixed: Round 1: drift that phase 2 had already fixed was still listed (flutter items, android nullRemoteUrlIds, flutter eventsEnabled).
1. Fixed: The lock timeout was untested, so mutants C2, C12, C21, C22 and C24 survived. Fake-clock withLock tests, a stale-boundary test and a release-error test now kill all 5. A 10,000-try guard in heldLock and a 15 s runAdd kill make wait-forever mutants fail fast instead of hanging.
1. Fixed: A description holding '/*' opened a nested Kotlin comment in SellwildFailureCode.kt. It is now refused.
1. Fixed: NEVER_LOGGED_RE missed the no_bid and nobid codes. It now refuses both.
1. Fixed: Mirror temp files were written into SDK source folders, where no .gitignore covers them. They now go in contracts/.

</details>

<details><summary>sdk-core: 35 behavior changes, 11 bugs fixed</summary>

1. `core/src/api.ts`: A non-array pick gives listings []. Which key wins is the same (rs, then listings), and a null body still throws the old TypeError. It is still reported as listings.parse.invalid.
1. `core/src/api.ts`: It returns the same values ([] on any failure, and still returns an array body even from a non-2xx answer). Each failure is now reported once: tag_cache.network, .http, .parse and .invalid. A caller abort is not reported.
1. `core/src/remote-config.ts`: They are coerced exactly the same way. fetchRemoteConfig now reports config.adstack.invalid or config.field.invalid once per bad key per fetch (the config is cached). mapRemoteConfig stays pure.
1. `core/src/growthcode.ts`: They return the same values and now report growthcode.eid.parse, eid.invalid, sync.invalid and config.missing through logFailure. Pure *WithIssues forms were added.
1. `core/src/localized-listings.ts`: It returns the same values. It now reports localized.config.parse and localized.config.invalid. '' (the CMS unset value), null or absent, and enabled:false are not reported. A pure resolveLocalizedListingsWithIssues was added.
1. `core/src/ads.ts`: Same values and the same TypeError, but ad.size.invalid is reported first. Pure parseAdSize, isGdprRegionFor, isCcpaRegionFor and isGeoBlockedFor(config, loc) were added; the global-reading functions now wrap them.
1. `core/src/api.ts, remote-config.ts, event-queue.ts, failures/core.ts`: New additive exports: parseListingsResponse, hasListingsArray, buildTagCacheUrl, parseTagCacheResponse, mapRemoteConfigWithIssues, RemoteConfigMapping, buildRemoteConfigUrl, remoteConfigHeaders, stampEventAttributes, EventStamp, UserLocation, parseRate. Public API stays back-compatible.
1. `core/src/config.ts`: configure() and buildConfigWithRemote() take the issues from fetchRemoteConfigWithIssues and log them after applyRuntimeFlags (overrides included), so a config that turns events/failures off or samples to 0 sends no report about itself; a local failuresEnabled override still wins
1. `core/src/remote-config.ts`: fetchRemoteConfig (standalone) puts the EVENTS_ENABLED/FAILURES_ENABLED/FAILURES_SAMPLE_RATE the config sets into the failure context before reporting its value issues (only when there are issues; unset keys are left alone). New fetchRemoteConfigWithIssues returns {config, issues} with the URL on each issue; a cached config returns issues []
1. `core/src/growthcode.ts`: Only the error name goes (errName SyntaxError, msg 'eid blob is not JSON', no stack) via parseErrorName
1. `core/src/api.ts`: errName only, with msg 'listings body is not JSON' / 'tag cache body is not JSON'; the caller still gets the original error
1. `core/src/remote-config.ts`: errName only, msg 'config body is not JSON'
1. `core/src/localized-listings.ts`: errName only for the parse error; a present non-number frequency (not null/absent/'') is reported once as localized.config.invalid '<name> frequency is <kind>, not a number, read as 0' while the integration still resolves with frequency 0
1. `core/src/api.ts`: Gives [] and reports listings.parse.invalid; failing test first (a9-red.log)
1. `core/src/api.ts`: Same [] results, and each failure is reported once: listings.tag_cache.network/http/parse/invalid; caller abort not reported; keywords never sent
1. `core/src/growthcode.ts, core/src/localized-listings.ts`: They report their issues once via logFailure; pure *WithIssues forms return them; results unchanged
1. `core/src/ads.ts`: Reports ad.size.invalid then reads it as before; pure isGdprRegionFor/isCcpaRegionFor/isGeoBlockedFor/parseAdSize added, old exports are thin wrappers
1. `core/src/config.ts, core/src/event-queue.ts, core/src/remote-config.ts, core/src/api.ts`: Added as pure exports (additive public API); the shells use them with the same observable behavior
1. `core/src/remote-config.ts`: It reports config.adstack.invalid and config.field.invalid once per fetch through logFailuresWithFlags. Each report goes out only when both the fetched config's flags and the context allow it, at the lower sample rate. The global context is never changed.
1. `core/src/failures/index.ts`: Adds logFailuresWithFlags(flags, inputs) and the pure strictestFailureFlags(a, b); both are additive exports. A stack over 2000 units that starts with the V8 header has the header removed before the cut (FAILURES.md 3.3 item 4).
1. `core/src/api.ts`: It returns [] and reports listings.parse.invalid once.
1. `core/src/api.ts`: Same return values ([] on failure; a non-2xx array body is still returned). It now reports listings.tag_cache.network, .http, .parse and .invalid once each. A caller abort is not reported, and keywords are never sent.
1. `core/src/config.ts`: They call fetchRemoteConfigWithIssues (same fetch and cache) and report the issues after the merged config's flags and overrides are applied to the context.
1. `core/src/growthcode.ts`: Same return values. It now reports growthcode.eid.parse (error name only), growthcode.eid.invalid, growthcode.sync.invalid and growthcode.config.missing once, through the pure *WithIssues functions.
1. `core/src/localized-listings.ts`: Same return values. It now reports localized.config.parse (error name only) and localized.config.invalid once, through resolveLocalizedListingsWithIssues.
1. `core/src/ads.ts`: Read the same way, but reported once as ad.size.invalid. The geo, GDPR and CCPA checks now have pure *For(config, loc) versions; the old exports are thin wrappers.
1. `core/src/api.ts`: It resolves [] and reports listings.tag_cache_url.invalid once (error name only, base host only, never the keywords). No request is made.
1. `core/src/remote-config.ts`: It reports config.adstack.invalid and config.field.invalid once per fetch through logFailuresWithFlags. Each report goes out only when both the fetched config's flags and the context allow it, at the lower sample rate. The global failure context is never changed.
1. `core/src/failures/index.ts`: Adds logFailuresWithFlags(flags, inputs) and the pure strictestFailureFlags(a, b), both additive. A stack over 2000 units that starts with the V8 header has the header removed before the cut (FAILURES.md 3.3 item 4).
1. `core/src/api.ts`: Same return values. It now reports listings.tag_cache.network, .http, .parse and .invalid once each. A caller abort is not reported; keywords are never sent.
1. `core/src/config.ts`: They call fetchRemoteConfigWithIssues and report the issues after the merged config's flags and overrides are applied to the context.
1. `core/src/localized-listings.ts`: Same return values. It now reports localized.config.parse (error name only) and localized.config.invalid once.
1. `core/src/ads.ts`: It is read the same way, but reported once as ad.size.invalid. Geo, GDPR and CCPA checks have pure *For(config, loc) versions; the old exports are thin wrappers.
1. Fixed: parseListingsResponse returned a non-array result.rs or result.listings as `listings` (for example {} or 'none'). React Native's useSellwildListings then crashed calling .map on it.
1. Fixed: Config value reports were logged before configure applied the same config's kill switches, so EVENTS_ENABLED:false with a bad AD_STACK still POSTed a clientFailure. The fix moves reporting to after applyRuntimeFlags (config.ts:161); 4 tests went red on the old ordering.
1. Fixed: growthcode.eid.parse sent the SyntaxError message, which quotes part of the EID blob (PII).
1. Fixed: listings.tag_cache.parse and listings.fetch.parse (line 93) sent res.json() messages quoting the response body.
1. Fixed: config.fetch.parse sent the res.json() message quoting the body; localized.config.parse (localized-listings.ts:79) quoted the config text.
1. Fixed: A9: fetchListings returned a non-array result.rs as listings, which crashed RN useSellwildListings (.map). Failing test written first (prior round, a9-red.log).
1. Fixed: parseListingsResponse returned a non-array result.rs or result.listings as `listings`, which crashed RN useSellwildListings (.map on a non-array).
1. Fixed: Round-1 regression: fetchRemoteConfig wrote the fetched config's failure flags into the global context whenever it had value issues. That dropped a host failuresEnabled override and could turn failures back on after the active kill switch.
1. Fixed: fetchTagCacheListings rejected with URIError, with no report, for keywords holding a lone UTF-16 surrogate; its doc says it never rejects.
1. Fixed: parseListingsResponse returned a non-array result.rs or result.listings as `listings`, which crashed RN useSellwildListings (.map on a non-array).
1. Fixed: Round-1 regression: fetchRemoteConfig wrote the fetched config's failure flags into the global context, which dropped a host failuresEnabled override.

</details>

<details><summary>sdk-flutter-rest: 49 behavior changes, 26 bugs fixed</summary>

1. `flutter/lib/src/remote_config.dart`: A value that is not finite, or over 2^53-1 ms, keeps the base interval and is reported as config.field.invalid. Every other remote value still applies.
1. `flutter/lib/src/remote_config.dart`: '' means absent, like core and like the schema ('' for the default), so the base listingsUrl is kept.
1. `flutter/lib/src/widget_html.dart`: Typed values escape '"' as &quot;, the same as passthrough values and iOS. The browser decodes it, so the widget reads the original text.
1. `flutter/lib/src/widget_html.dart`: A JSON null passthrough value is left out, as on iOS.
1. `flutter/lib/src/widget_html.dart`: send() returns true after posting and false in its catch. No caller reads the result, so page behavior is the same.
1. `flutter/lib/src/sellwild_widget.dart`: Each failure is reported once: bridge.message.parse/invalid/unsupported, bridge.script.exception on ERROR (onError still called), widget.host_callback.exception (not rethrown, as before), widget.webview_load.network for main-frame load errors and for setup failures, and ad.banner_config.missing. WIDGET_LOADED after dispose is ignored, as before. Host callbacks run as before.
1. `flutter/lib/src/sellwild_sdk_configure.dart`: apply delegates to the pure applyRemoteConfig and reports one logFailure per code: config.field.invalid, config.color.invalid, config.adstack.invalid, config.refresh_interval.invalid. configure adds the config host. Values applied are the same except for the A9 fixes. The config.apply.exception catch stays, and it is tested through a throwing isAndroidHost.
1. `flutter/lib/src/sellwild_api.dart`: Still skipped, and reported as listings.item.invalid (warn) once per response, with the count.
1. `flutter/lib/src/sellwild_listing_card.dart`: Same rendering. Each is reported once per card (per listing/config, not per build): config.color.invalid, listings.item.invalid, feed.image.network. The widget tree gains two transparent StatefulWidget wrappers.
1. `flutter/lib/src/remote_config.dart`: Base interval kept, every other key applied, and config.field.invalid 'AD_REFRESH_INTERVAL is out of range'
1. `flutter/lib/src/remote_config.dart`: Base kept plus config.field.invalid (checks |ms| > 9007199254740991)
1. `flutter/lib/src/remote_config.dart`: '' is absent: base listingsUrl, else the default cache (as core)
1. `flutter/lib/src/remote_config.dart`: Base partnerCode kept plus config.field.invalid 'CODE is empty' (core also keeps the base for '')
1. `flutter/lib/src/remote_config.dart`: '' keeps the base gamTag (null by default), as core does
1. `flutter/lib/src/widget_html.dart`: hasGamTag treats '' as no tag (as iOS, Android and core do). With a zone id the zone script runs; without one the slot is blank and ad.banner_config.missing 'no GAM tag and no zone id' fires
1. `flutter/lib/src/listing_card_view.dart`: Only #rrggbb or rrggbb is used. Anything else gets the grey fallback plus config.color.invalid (Android parseColor also rejects #fff)
1. `flutter/lib/src/sellwild_widget.dart`: Wrapped in _callHost: reported as widget.host_callback.exception and not rethrown, like every other host callback
1. `flutter/lib/src/widget_html.dart`: Typed values are escaped with &quot;, like passthrough values
1. `flutter/lib/src/widget_html.dart`: Null keys are left out, as on iOS
1. `flutter/lib/src/sellwild_widget.dart`: The first failure is reported once as widget.webview_load.network, and nothing is rethrown
1. `flutter/lib/src/widget_html.dart`: send() returns true or false. The catch is not empty; nothing reads the result
1. `flutter/lib/src/sellwild_models.dart + listing_card_view.dart`: displayPrice is null for a non-finite value, so there is no badge. The card reports listings.item.invalid (warn) 'price is not a number; no badge' once.
1. `flutter/lib/src/sellwild_listing_card.dart`: didUpdateWidget reports again when the error is a new object, with the new URL. A URL change alone (Image keeps its old error while loading) is not reported.
1. `flutter/lib/src/sellwild_widget.dart`: Reported once as widget.webview_load.exception (a new registry code, added with add-code.mjs).
1. `flutter/lib/src/remote_config.dart (SellwildSDK.apply)`: The base interval is kept. config.field.invalid 'AD_REFRESH_INTERVAL is out of range' is reported once.
1. `flutter/lib/src/remote_config.dart`: The base partnerCode is kept. config.field.invalid 'CODE is empty' is reported.
1. `flutter/lib/src/remote_config.dart`: '' means absent: the base URL, or the default, is kept, as in core.
1. `flutter/lib/src/remote_config.dart + widget_html.dart`: '' is no tag: the base is kept, and the banner uses the zone script or a blank slot, which is reported as ad.banner_config.missing.
1. `flutter/lib/src/listing_card_view.dart`: Only #rrggbb or rrggbb is used. Anything else is grey and reported as config.color.invalid.
1. `flutter/lib/src/widget_html.dart`: Typed values are escaped like passthrough values. Null passthrough keys are left out, as on iOS.
1. `flutter/lib/src/sellwild_widget.dart`: A throwing callback is reported as widget.host_callback.exception and not rethrown. Bad bridge messages are reported as bridge.message.parse, .invalid or .unsupported (warn). Existing onError calls stay (A6).
1. `flutter/lib/src/sellwild_listing_card.dart`: Each config reports each bad color once, tracked by an Expando keyed on the config object. Listing issues (currency, price) and photo failures are still reported once per card. The severity stays error, matching Android FeedTheme and the registry.
1. `flutter/lib/src/widget_html.dart`: The comment says the catch is a deliberate in-page swallow: no caller reads the false it returns, and the point is excluded as 'in-page'. The page HTML is unchanged.
1. `flutter/lib/src/sellwild_models.dart + listing_card_view.dart (round 2)`: No badge, and listings.item.invalid 'price is not a number; no badge' is reported once.
1. `flutter/lib/src/remote_config.dart (rounds 1-2)`: The base interval is kept and config.field.invalid is reported once. '' means absent for LISTINGS and GAM. CODE '' keeps the base and is reported.
1. `flutter/lib/src/sellwild_widget.dart (rounds 1-2)`: The bridge reports bridge.message.parse, .invalid or .unsupported. A throwing callback is reported as widget.host_callback.exception. A setup failure is reported as widget.webview_load.exception. The onError calls stay (A6).
1. `flutter/lib/src/sellwild_api.dart (this round)`: The URL is parsed before the fetch. The failure is reported once as listings.url.invalid (error) with 'listings URL is not a valid URL' and the FormatException. The same FormatException is rethrown, and no request is made, as before.
1. `flutter/lib/src/widget_html.dart gptScript/zoneScript (this round, A9)`: Each one goes through escapeJsString, which escapes \ ' \n \r U+2028 U+2029 and writes < as \x3C. Plain tags, zone ids and URLs come out byte for byte the same. A bad tag now reaches defineSlot, so ad.gpt_slot.invalid can report it.
1. `flutter/lib/src/listing_card_view.dart parseHexColor (round 1, A9)`: Only #rrggbb or rrggbb is used. Anything else, including 3-digit #rgb and 8-digit hex, shows fallbackCardColor (grey) and is reported once per config as config.color.invalid (error). Grey for #rgb is on purpose: Android FeedTheme.resolve and iOS SellwildFeedView.parseColor also reject #rgb, so expanding it would be Flutter-only drift. This is now stated in a code comment and in drift other.card.cssColor.
1. `flutter/lib/src/widget_html.dart buildWidgetAttributes, typed values (round 1, A9)`: Typed values are escaped with escapeAttribute ('"' -> '&quot;'), like the passthrough values. The browser decodes it, so the widget reads the same text.
1. `flutter/lib/src/widget_html.dart buildWidgetAttributes, passthrough JSON null (round 1, A9)`: A null value is absent: no attribute, as on iOS.
1. `flutter/lib/src/widget_html.dart hasGamTag/selectBannerAdScript (round 1, A9)`: '' means no tag, as on iOS, Android and core. The banner uses the zone script, or it is a blank slot reported as ad.banner_config.missing.
1. `flutter/lib/src/sellwild_listing_card.dart (round 4)`: Each config reports each bad color once (an Expando keyed on the config). Listing issues and photo failures are still reported once per card.
1. `flutter/lib/src/sellwild_models.dart + listing_card_view.dart (round 2, A9)`: No badge. listings.item.invalid 'price is not a number; no badge' is reported once.
1. `flutter/lib/src/remote_config.dart (rounds 1-2, A9)`: The base interval is kept, and config.field.invalid is reported once. '' means absent for LISTINGS and GAM, like core. CODE '' keeps the base value and is reported.
1. `flutter/lib/src/sellwild_widget.dart (rounds 1-2)`: The bridge reports bridge.message.parse, .invalid or .unsupported. A throwing callback is reported as widget.host_callback.exception, and a setup failure as widget.webview_load.exception. The onError calls stay (A6).
1. `flutter/lib/src/widget_html.dart buildWidgetHtml comment (round 4)`: The comment says the catch in send() is a deliberate in-page swallow. The page HTML did not change.
1. `flutter/test/support/failure_capture.dart (this round, tests only)`: At tearDown, captureFailures fails when any gate key folded a repeat. Opt out with allowFolds: true. Loops use endFailureCase(), which checks for a fold before it resets.
1. `scripts/coverage/flutter.sh (this round)`: It runs with --concurrency=${FLUTTER_TEST_JOBS:-2}. The recorded command shows the value.
1. Fixed: Infinite AD_REFRESH_INTERVAL: Infinity.round() threw, so apply lost the whole remote config.
1. Fixed: AD_REFRESH_INTERVAL 1e300 wrapped silently to a -1 ms Duration (int overflow in Duration).
1. Fixed: LISTINGS '' was copied into listingsUrl and replaced the host's base listingsUrl.
1. Fixed: Typed attribute values were not HTML-escaped. A '"' (real LINK_TEXT fixture) broke the <sellwild-widget> markup.
1. Fixed: A JSON null passthrough value was sent as the attribute text "null".
1. Fixed: Test seam restore read a lazy top-level (hostIsAndroid) only after the swap, so it restored the replaced function, not the original.
1. Fixed: An infinite AD_REFRESH_INTERVAL threw in apply, and 1e300 or -1e300 wrapped to a negative Duration
1. Fixed: LISTINGS '' was copied into listingsUrl
1. Fixed: CODE '' wiped partnerCode, and with it the partner on every failure and event
1. Fixed: GAM '' built googletag.defineSlot(''): a blank banner with no report
1. Fixed: parseHexColor read 'fff' as 0x000fff (dark blue) and also took a sign, '##' or 8 digits
1. Fixed: A host onError that threw from the navigation delegate escaped, not reported
1. Fixed: Typed attribute values were not escaped (a '"' spilled into the markup)
1. Fixed: A JSON null passthrough value was written as the text "null"
1. Fixed: A dead assertion on a stale, immutable gate snapshot. It now reads gateState fresh: 2, then 4
1. Fixed: displayPrice gave 'NaN' or 'Infinity' for contract-valid price text, so the badge showed '$NaN'.
1. Fixed: A second photo failure on a reused card was not reported (initState only).
1. Fixed: A WebView setup exception was reported with a network code.
1. Fixed: displayPrice gave 'NaN' or 'Infinity' for price text the contract allows (round 2).
1. Fixed: A second photo failure on a reused card was not reported (round 2).
1. Fixed: One bad config color was reported by every card in a feed, not once (this round).
1. Fixed: The GAM tag, gpt.js URL and zone id went into single-quoted JS strings unescaped. A quote made the whole banner script fail to parse, with no report (this round).
1. Fixed: A malformed LISTINGS URL was reported as listings.fetch.network, not listings.url.invalid (this round).
1. Fixed: displayPrice gave 'NaN' or 'Infinity' for price text the contract allows (round 2).
1. Fixed: A second photo failure on a reused card was not reported (round 2).
1. Fixed: One bad config color was reported by every card in a feed, not once (round 4).

</details>

<details><summary>sdk-ios-logic: 50 behavior changes, 28 bugs fixed</summary>

1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: LISTINGS '' is treated as absent; listingsUrl keeps the partner value or nil (effectiveListingsUrl = default cache), like core.
1. `ios/Sources/SellwildSDK/SellwildAPI.swift (SellwildEvents.isEnabled)`: Uses SellwildFailuresCore.coerceFlag (ASCII trim + ASCII lower case, FAILURES.md 5.3), so those values are off and U+00A0 is not trimmed. SellwildAdView's eventsEnabled assignment uses it too.
1. `ios/Sources/SellwildSDK/SellwildHouseAd.swift`: coerceFlag: those values disable house ads.
1. `ios/Sources/SellwildSDK/SellwildAdAudioGuard.swift`: coerceFlag, which matches the schema's flag type (text trimmed).
1. `ios/Sources/SellwildSDK/SellwildAPI.swift (fetchListings)`: Non-2xx resolves .failure(SellwildError.invalidResponse), is not cached, and reports listings.fetch.http. CloudFront geo seeding still runs first.
1. `ios/Sources/SellwildSDK/SellwildHouseAd.swift (loadImage)`: Downloads go through the injectable ImageLoader (live = URLSession.shared dataTask; a non-2xx is a failure). Each failure is reported once: house.image.invalid, house.image.network, storage.write.exception, storage.cache_dir.exception. A directory that cannot be created means memory-only caching. The completion is still nil on failure, on main.
1. `ios/Sources/SellwildSDK/SellwildAdAudioGuard.swift (muteScript)`: Each JS catch counts the error in window.__swAudioGuardErrors. The shim returns and resets the count. The completion reports ad.audio_guard.exception for an evaluation error or a count > 0. apply(to:remoteValues:delays:) gains a defaulted delays parameter.
1. `ios/Sources/SellwildSDK/SellwildAPI.swift, SellwildConfig.swift, SellwildAdSizes.swift, SellwildGpid.swift, SellwildGrowthCode.swift, SellwildLocalizedListings.swift`: The same fallbacks, now reported once each with registry codes. Outputs are unchanged except as listed above.
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift (internal)`: bootstrap is (SellwildConfig) -> Bool, set to SellwildPrebidMobile.bootstrap(with:) directly. The public configure uses the internal static SellwildSDK.environment (default .live).
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: '' is treated as absent: the partner URL or the default cache is kept (line 225).
1. `ios/Sources/SellwildSDK/SellwildAPI.swift`: Uses SellwildFailuresCore.coerceFlag, the contract rule (ASCII trim and ASCII lower case, line 676). 'off\n', '\tfalse\r\n', ' NO\v' and '0\f' now read OFF. ' off' now reads ON, matching the golden coerceFlag table.
1. `ios/Sources/SellwildSDK/SellwildHouseAd.swift`: Uses coerceFlag (line 43). ' off ', 'False\n' and ' 0' now disable house ads.
1. `ios/Sources/SellwildSDK/SellwildAdAudioGuard.swift`: Uses coerceFlag (line 47). The schema's flag type trims text.
1. `ios/Sources/SellwildSDK/SellwildAPI.swift`: A non-2xx status is reported once as listings.fetch.http and fails with SellwildError.invalidResponse. It is not cached, so the next fetch asks again (line 303).
1. `ios/Sources/SellwildSDK/SellwildHouseAd.swift`: Images download through the ImageLoader seam (a URLSession dataTask by default). A non-2xx answer is refused and reported as house.image.network with httpStatus (downloadResult, line 218). The completion is still delivered on main, and the memory and disk caches are unchanged.
1. `ios/Sources/SellwildSDK/SellwildAdAudioGuard.swift`: apply(to:remoteValues:delays:evaluate:) takes an Evaluator; the default is evaluateInPage, which is WebKit's evaluateJavaScript. Callers without the argument (SellwildAdView) behave exactly as before.
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: '' reads as unset: the partner's URL or the default cache is kept
1. `ios/Sources/SellwildSDK/SellwildAPI.swift (SellwildEvents.isEnabled), SellwildHouseAd.swift (isEnabled), SellwildAdAudioGuard.swift (isEnabled)`: All three use SellwildFailuresCore.coerceFlag (ASCII trim, ASCII lower case, false/0/no/off)
1. `ios/Sources/SellwildSDK/SellwildAPI.swift (fetchListings)`: A non-2xx is reported (listings.fetch.http) and fails with SellwildError.invalidResponse. It is not cached.
1. `ios/Sources/SellwildSDK/SellwildAPI.swift (fetchListings, fetchCacheListings)`: Parsing is pure (Core/SellwildListingsCore). Each failure is reported once, with a registry code. A 403/404 on the localized cache is a normal skip (debug trace only). A cancelled load is not a failure. A client released mid-request still delivers an empty success and reports listings.client.missing.
1. `ios/Sources/SellwildSDK/SellwildHouseAd.swift (loadImage)`: The download runs through an injected ImageLoader (live: URLSession dataTask) and checks the HTTP status. Failures are reported (house.image.invalid, house.image.network, storage.cache_dir.exception, storage.write.exception). A cancelled download is not a failure. When the cache directory cannot be created, images are cached in memory only.
1. `ios/Sources/SellwildSDK/SellwildHouseAd.swift (resolve)`: candidates() is pure, and the random source is injectable (resolve(using:)). The selection rules are unchanged.
1. `ios/Sources/SellwildSDK/SellwildGrowthCode.swift`: An Environment seam (send, nowMs, defaults, advertisingId). Pure syncRequest and syncOutcome. Reports: growthcode.sync.timeout/network/http/parse, growthcode.url.invalid, growthcode.eid.invalid, growthcode.config.missing.
1. `ios/Sources/SellwildSDK/SellwildGpid.swift, SellwildAdAudioGuard.swift`: They are reported as ad.gpid.exception and ad.audio_guard.exception. The shim counts the errors it catches in the page and returns the count.
1. `ios/Sources/SellwildSDK/SellwildConfig.swift (remoteValues)`: It is reported as config.remote_values.parse (warn), once per launch for each way the payload can be bad
1. `ios/Sources/SellwildSDK/SellwildAdSizes.swift`: Entries that do not parse, are not positive, or do not fit an Int are dropped. The drop is reported once per launch per zone and message.
1. `ios/Sources/SellwildSDK/SellwildLocalizedListings.swift`: localized.config.invalid is reported once per launch per reason, and localized.url.invalid once per URL. A frequency too large for an Int reads as Int.max, which fills every slot, as any frequency of 100 or more does. 'inf' and 'nan' read as 0, as in core.
1. `ios/Sources/SellwildSDK/SellwildGrowthCode.swift (eidBlob)`: An atype too large for an Int reads as Int.max. Text that is not a finite number reads as 0.
1. `ios/Sources/SellwildSDK/SellwildGrowthCode.swift (resolveIfNeeded)`: It is logged once per launch through a separate latch. The once-per-launch sync is not used up by it, so a config that gains its settings later still syncs.
1. `ios/Sources/SellwildSDK/SellwildHouseAd.swift (loadImage)`: It is reported once per launch per URL
1. `ios/Sources/SellwildSDK/SellwildAPI.swift (flushEvents)`: do/catch with a SellwildLog.debug trace. There is no clientFailure, because transport never reports itself (A7).
1. `ios/Sources/SellwildSDK/SellwildRemoteConfig.swift`: bootstrap is `(SellwildConfig) -> Bool`, with the live value `SellwildPrebidMobile.bootstrap(with:)` (a method reference). The static `SellwildSDK.environment` is a test seam. configURLString and configRequest are pure.
1. `ios/Sources/SellwildSDK/SellwildNative.swift, SellwildAdSizes.swift, SellwildLocalizedListings.swift, SellwildGrowthCode.swift, SellwildConfig.swift (AdSize.cgSize)`: Restored to the original code. The arms are reachable: an integer above 2^53 hits the Int arm, and UInt64.max hits the NSNumber arm. New tests cover them. The cgSize guard is dead and carries a 'dead: pending delete decision' comment. SellwildNative.swift now matches HEAD.
1. `ios/Sources/SellwildSDK/SellwildHouseAd.swift (loadImage, reportInvalid)`: Every house.image.invalid problem is reported once per launch per image and problem. A data: URI is keyed by its UTF-8 length and hash, not its text. Download failures (house.image.network) are still reported on every try.
1. `ios/Sources/SellwildSDK/SellwildNative.swift, SellwildAdSizes.swift, SellwildLocalizedListings.swift, SellwildGrowthCode.swift, SellwildConfig.swift (AdSize.cgSize)`: Restored to the original code. The arms can be reached: an integer above 2^53 hits the Int arm, and UInt64.max hits the NSNumber arm. The cgSize guard is dead and carries a 'dead: pending delete decision' comment. SellwildNative.swift matches HEAD.
1. Fixed: LISTINGS '' became listingsUrl '' (an unusable URL) and overrode a partner-supplied listings URL.
1. Fixed: EVENTS_ENABLED kill switch: 'off\n' and other values with a trailing line break or VT/FF read as ON (.whitespaces trim).
1. Fixed: MOBILE_HOUSE_AD_ENABLED ' off ' read as enabled (no trim).
1. Fixed: MOBILE_AD_MUTE_AUTOPLAY ' off ' read as enabled (no trim).
1. Fixed: fetchListings ignored the HTTP status; a JSON error body was cached as an empty feed for the session.
1. Fixed: Flaky test. It drove a real WKWebView, and the simulator's process freezer can suspend WebContent for the test process in the middle of an evaluation. A late completion then reported into the next test's capture. It is replaced by a scripted evaluator, an in-process answering WKWebView subclass, and JavaScriptCore tests of the shim. No WebContent process is used now.
1. Fixed: only()/none() counted only the events left after the dedupe gate, so a site that logged twice still passed. They now also assert FailureCapture.calls (1 or 0).
1. Fixed: An unrecorded behavior change from the first round: trimming the whole BANNER_SIZES text with .whitespacesAndNewlines made '300x250\n' parse. It is reverted to the old per-part space trim, pinned by a test, and recorded as drift.
1. Fixed: LISTINGS '' became listingsUrl '', a URL nobody can load.
1. Fixed: EVENTS_ENABLED 'off\n' read as ON because the trim used .whitespaces only.
1. Fixed: MOBILE_HOUSE_AD_ENABLED ' off ' read as enabled because the text was not trimmed.
1. Fixed: MOBILE_AD_MUTE_AUTOPLAY ' off ' left the guard on because the text was not trimmed.
1. Fixed: A listings 4xx/5xx body parsed as an empty feed, was reported as success, and was cached for the session.
1. Fixed: LISTINGS '' was copied into listingsUrl (unusable URL)
1. Fixed: EVENTS_ENABLED 'off\n' read ON (the trim used .whitespaces only)
1. Fixed: MOBILE_HOUSE_AD_ENABLED ' off ' read enabled (no trim)
1. Fixed: fetchListings parsed a 4xx/5xx body, delivered it as an empty feed and cached it as a success
1. Fixed: Crash: Int(_:) trapped on a schema-valid BANNER_SIZES part of 2^63 or more ('99999999999999999999x50', [1e20, 50]) or 'inf'
1. Fixed: Crash: Int(_:) trapped on a schema-valid LOCALIZED_LISTINGS frequency of 1e19, a 20-digit text, or UInt64.max
1. Fixed: Crash: Int(_:) trapped on a schema-valid eid atype of 20 digits, or 1e300, from the GrowthCode sync answer (network data)
1. Fixed: house.image.invalid for a data: URI, an image over the cap, or bytes that are not an image was reported on every no-fill load, not once per image
1. Fixed: LISTINGS '' was copied into listingsUrl (unusable URL)
1. Fixed: EVENTS_ENABLED 'off\n' read ON (the trim used .whitespaces only)
1. Fixed: MOBILE_HOUSE_AD_ENABLED ' off ' read enabled (no trim)
1. Fixed: fetchListings parsed a 4xx/5xx body, delivered it as an empty feed and cached it as a success
1. Fixed: Crash: Int(_:) trapped on a schema-valid BANNER_SIZES part of 2^63 or more or 'inf'. It is now dropped, and 2^63 exactly is pinned by a test.
1. Fixed: Crash: Int(_:) trapped on a schema-valid LOCALIZED_LISTINGS frequency of 1e19, a 20-digit text, or UInt64.max
1. Fixed: Crash: Int(_:) trapped on a schema-valid eid atype of 20 digits, or 1e300, from the GrowthCode sync answer

</details>

<details><summary>sdk-android-logic: 57 behavior changes, 34 bugs fixed</summary>

1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: It returns FailuresCore.coerceFlag(EVENTS_ENABLED): a number is on unless it is 0, and text is trimmed and lower-cased as ASCII only. No config, unparseable config, JSON null or an object all read as on (as before). The eventsEnabled drift entries are removed from drift/android.json.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: A clientFailure keeps the code logFailure set. The queue still stamps the partner on a clientFailure that has no code, and on every other event as before.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: LISTINGS '' is treated as absent and the base listingsUrl is kept, as core does.
1. `android/src/main/kotlin/com/sellwild/sdk/core/GrowthCodeSync.kt`: gc_id and eb are read as absent when JSON null, missing or empty (isNull check). The throttle time is still saved.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: Each failure is logged once: listings.url.invalid and listings.fetch.http/network/timeout/parse (error severity), and localized.url.invalid and localized.fetch.http/network/timeout/parse (warn). A 403/404 state cache is still a silent skip. A bad or non-http(s) URL returns Result.failure(MalformedURLException) without opening a connection. The failure messages the caller sees are unchanged ('HTTP <status> from <url>').
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: The body is read (and the stream closed) before the geo is seeded, so a body that breaks mid-read no longer seeds geo first. Geo seeding is now the pure Fetch.seededGeo, with the same rules.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildConfig.kt`: fetchListings and GrowthCode.resolveIfNeeded call config.claimFailurePartner(), which sets the failure-context partner from a hand-built config when none is set. configure()'s partner always wins.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: configure() logs one config.field.invalid (warn) naming every mapped key whose value is off-schema and was dropped or coerced. Schema-valid configs log nothing (checked over every fixture and sample). IAB_CATS text is known drift and is not reported. apply itself stays pure.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildConfig.kt`: All of them use remoteObject() (RemoteValues.parse), which logs config.remote_values.parse (warn) and falls back the same way. Blank remoteJson means no config and is not reported. The gate folds repeats of the same parse error.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdStack.kt`: The same fallback, plus config.adstack.invalid (warn), with zoneId for a zone entry. '' (the CMS's unset value) is not reported. Resolution is now the pure resolveFrom/global/byZone.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdSizes.kt`: The same sizes result. When anything was dropped, one config.banner_sizes.invalid (warn) says how many, with zoneId for a zone entry. '' is unset. JSON-list text is only tried when it starts with '[' (same outcome, no exception used as control flow).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildLocalizedListings.kt`: The same result, plus localized.config.invalid (warn). '' and enabled:false are not reported. merge takes an injected kotlin.random.Random (default Random.Default, @JvmOverloads).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGrowthCode.kt`: Logged once each (warn): growthcode.sync.network or .timeout (thread catch), growthcode.sync.http, growthcode.sync.parse, growthcode.url.invalid, growthcode.eid.parse, growthcode.eid.invalid and growthcode.config.missing. The runner, clock and advertising-id source are injectable. A missing GAID is still silent (privacy exclusion, commented).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildHouseAd.kt`: The same null callback, with house.image.invalid (scheme, too large, not base64, not decodable, unreadable cache), house.image.network (download) or storage.write.exception (disk cache write, image still dropped as before). A cached image is read and decoded through the same decoder. resolve takes an injected Random. The runner, download and decode seams are injectable; resetForTests restores them.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdAudioGuard.kt`: A throwing evaluateJavascript is logged as ad.audio_guard.exception (warn). Each JS catch now counts into window.__swAudioGuardErrors, the script returns the count since its last run, and a non-zero count is logged as ad.audio_guard.exception. Muting behavior is unchanged; the script was checked with node.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: One synchronized block, which attaches logFailure only when it created the queue. Same results.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSafeUrl.kt`: external() drops the runCatching (Uri.parse never throws for non-null text). imageUrl() uses Fetch.httpUrl; null means refused, which the caller reports. Same results.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: configure() sets debug and the 3 remote flags, then reports config.field.invalid (still with the partner configure() was called with), then sets partnerCode = config.partnerCode.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: The seed is wrapped in runCatching and logged once as geo.seed.exception (warn, component geo). The listings still parse and return success.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGrowthCode.kt`: Read with RemoteValues.optText: JSON null is unset. The partner id and sync url are null, which gives growthcode.config.missing and no request. The endpoint falls back to the default.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildLocalizedListings.kt`: JSON null is unset. A null baseUrl or urlTemplate is a missing URL part: the integration is off and localized.config.invalid is reported. A null forceState or source is null.
1. `android/src/main/kotlin/com/sellwild/sdk/core/GrowthCodeSync.kt`: JSON null is absent. The entry or uid is dropped and counted in growthcode.eid.invalid, and a null stype is left out of ext.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGrowthCode.kt`: It is logged once per launch, behind its own latch (didReportMissing). resetForTesting clears it. A later complete config still syncs.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildConfig.kt`: remoteObject() remembers the last bad text it reported and reports each bad text once. A different bad text is reported again.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: A new internal constructor takes (context, dispatcher, setGeo). The public SellwildAPIClient(context) delegates with Dispatchers.IO and SellwildPrebidMobile::setGeo. No public API change.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGrowthCode.kt (round 0)`: JSON null is not stored (GrowthCodeSync.parseResponse with optTextOrNull).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt (round 0)`: '' is treated as absent, as core does, so the base URL is kept.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (round 0)`: A clientFailure keeps the code logFailure set.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (round 0)`: It uses FailuresCore.coerceFlag, so 0.5 is on, as in the contract.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGeo.kt`: A lat or lon that is not finite is left out of device.geo; the other fields still go out. setGeo stores the geo and does not throw.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdStack.kt, SellwildAdSizes.kt, SellwildLocalizedListings.kt, SellwildConfig.kt`: Each issue (code plus message, as in the gate dedupe key) is logged once per config text (remoteJson, or the local localizedListings override). A new config text is new, and its issues are logged again. The memory holds the last 8 texts (LRU).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGrowthCode.kt`: A new eb equal to the cached text is not parsed again. It was already parsed, fed and reported in step 1. A different new eb is still parsed and reported.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: The catch around setGeo stays, as a defense for the Prebid fork's setGlobalOrtbConfig. Its test now injects a setGeo that throws. A NaN partner geo takes the seed and reports nothing.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGrowthCode.kt, core/GrowthCodeSync.kt`: Each is read as absent. Bad eid entries are dropped with one growthcode.eid.invalid.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildLocalizedListings.kt`: They are read as absent.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: '' is treated as absent, and the base URL is kept, as in core.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (buildBatchJson)`: The code that logFailure set is kept on a clientFailure (FAILURES.md 17.12 / 6.1 item 4).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (SellwildEvents kill switch)`: It uses FailuresCore.coerceFlag, so 0.5 is on, as the contract says. The other flags' fraction drift is recorded in drift/android.json other.flags.fraction.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (fetchListings)`: It is caught and reported once as geo.seed.exception (a new code), and the listings still load.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: configure resets eventsEnabled, failuresEnabled and the sample rate before the fetch. A single config.field.invalid is reported after the fetched config's own kill switches apply.
1. `android owned shells (SellwildAPI, SellwildHouseAd, SellwildGrowthCode, SellwildAdAudioGuard, SellwildConfig, SellwildGpid, SellwildNative, SellwildVideo, SellwildSafeUrl)`: Each failure path reports once, with a registry code: listings.* / localized.* url/fetch, house.image.*, storage.write.exception, growthcode.*, ad.audio_guard.exception, config.remote_values.parse (once per text), growthcode.config.missing (once per launch). Return values and public APIs are unchanged.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdAudioGuard.kt`: Each apply() keeps a weak per-apply Run. A WebView that threw is reported once and is not retried in that apply. A shim error is reported once per WebView per apply. Live WebViews still get all 4 runs. A later apply (a new ad load) reports again.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdSizes.kt`: The message names the zone ('BANNER_SIZES_BY_ZONE[43]: dropped 1 of 1 entries'), so each zone's bad entry is reported once, with its zoneId. The global BANNER_SIZES message is unchanged.
1. `android/src/main/kotlin/com/sellwild/sdk/core/Fetch.kt, SellwildSDK.kt (configFailureCode), SellwildAPI.kt, SellwildGrowthCode.kt`: Only an IOException or a SecurityException (no INTERNET permission) is *.network. Anything else is *.exception: listings.fetch.exception, localized.fetch.exception, growthcode.sync.exception (new codes), and config.apply.exception for the config fetch (android merged as a client). Timeout and parse are unchanged.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (SellwildEvents.isEnabled)`: It uses FailuresCore.coerceFlag, which trims ASCII only, as the contract's coerceFlag does. A blank remoteJson means no config: events stay on and nothing is reported (RemoteValues.parse).
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGeo.kt`: A lat or lon that is not finite is left out of device.geo. The other fields still go out, and setGeo does not throw.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdStack.kt, SellwildAdSizes.kt, SellwildLocalizedListings.kt, SellwildConfig.kt`: Each issue (code plus message) is logged once per config text: remoteJson, or the local localizedListings override. The memory holds the last 8 texts (LRU). A new text is reported again.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildGrowthCode.kt`: A new eb equal to the cached text is not parsed again. A different new eb is still parsed and reported.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt`: The catch around setGeo stays, as a defense for the Prebid fork's setGlobalOrtbConfig. Its test injects a setGeo that throws.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: '' is treated as absent and the base URL is kept, as in core.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt (fetchListings)`: It is caught and reported once as geo.seed.exception, and the listings still load.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildSDK.kt`: configure resets eventsEnabled, failuresEnabled and the sample rate before the fetch. One config.field.invalid is reported after the fetched config's own kill switches apply.
1. `android owned shells (SellwildAPI, SellwildHouseAd, SellwildGrowthCode, SellwildAdAudioGuard, SellwildConfig, SellwildGpid, SellwildNative, SellwildVideo, SellwildSafeUrl)`: Each failure path reports once with a registry code. Return values and public APIs are unchanged.
1. Fixed: SellwildEvents.isEnabled read EVENTS_ENABLED 0.5 as off (toInt), against the contract's coerceFlag.
1. Fixed: buildBatchJson overwrote a clientFailure's attributes.code with the queue's raw partnerCode.
1. Fixed: LISTINGS '' replaced a partner-set listingsUrl with '' (the feed then used the general cache).
1. Fixed: A JSON-null gc_id or eb in the GrowthCode response was stored as the text "null" on a device (was SellwildGrowthCode.kt:177).
1. Fixed: config.field.invalid was logged before the fetched config's kill switches applied, so a failures-off, events-off or rate-0 config reported its own bad field.
1. Fixed: No test could catch a failure logged twice: every captured sink sits after the gate's 60 s dedupe. FailuresRule now fails any test whose gate state shows a suppressed or twice-emitted key, and CapturedEvents.single checks gateCalls == 1.
1. Fixed: No test pinned the 8 MiB image cap boundary (V5 survived). Tests for exactly MAX_IMAGE_BYTES, remote and inline, were added.
1. Fixed: A geo seed exception (for example a partner geo with a NaN lat) escaped fetchListings instead of being caught.
1. Fixed: GROWTHCODE_PARTNER_ID, GROWTHCODE_ENDPOINT and GROWTHCODE_SYNC_URL JSON null became the text "null" on a device.
1. Fixed: LOCALIZED_LISTINGS source, baseUrl, urlTemplate and forceState JSON null became "null" on a device (a null forceState became the state LL).
1. Fixed: A JSON null eid source, uid id or stype became "null" on a device and was sent to auctions.
1. Fixed: growthcode.config.missing was logged on every ad view load, before the once-per-launch latch.
1. Fixed: config.remote_values.parse was logged on every read of a bad remoteJson, up to 3 times in one SellwildNative call.
1. Fixed: toOrtbGeo threw JSONException for a NaN or infinite lat/lon, which failed setGeo and bootstrap.
1. Fixed: config.adstack.invalid was logged on every resolve (log-once violation). The same fix covers SellwildAdSizes.kt:49 and SellwildLocalizedListings.kt:62.
1. Fixed: growthcode.eid.* was logged twice when the sync returned the same bad eb as the cache.
1. Fixed: gc_id JSON null was stored as the text "null" on the device (round 1).
1. Fixed: Empty LISTINGS '' was copied into listingsUrl (round 1).
1. Fixed: buildBatchJson overwrote attributes.code on clientFailure events (round 1).
1. Fixed: EVENTS_ENABLED 0.5 read as off, against the contract's coerceFlag (round 1).
1. Fixed: An exception from setGeo escaped fetchListings (round 1).
1. Fixed: A JSON null baseUrl, forceState or source became "null" or "LL" on a device (round 1).
1. Fixed: One apply() reported the same dead WebView, or the same throwing shim, up to 4 times (now plus 3 retries).
1. Fixed: A bad BANNER_SIZES_BY_ZONE entry in a second zone with the same counts was never reported: the message held only counts.
1. Fixed: Fetch.codeFor reported any throwable that was not a timeout or JSONException as *.network, including a SharedPreferences ClassCastException in the GrowthCode sync.
1. Fixed: toOrtbGeo threw JSONException for a NaN or infinite lat or lon, which failed setGeo and bootstrap (round 2).
1. Fixed: config.adstack.invalid, config.banner_sizes.invalid and localized.config.invalid were logged on every resolve (round 2).
1. Fixed: growthcode.eid.* was logged twice when the sync returned the same bad eb as the cache (round 2).
1. Fixed: gc_id JSON null was stored as the text "null" on the device (round 1).
1. Fixed: Empty LISTINGS '' was copied into listingsUrl (round 1).
1. Fixed: buildBatchJson overwrote attributes.code on clientFailure events (round 1).
1. Fixed: EVENTS_ENABLED 0.5 read as off, against the contract's coerceFlag (round 1).
1. Fixed: An exception from setGeo escaped fetchListings (round 1).
1. Fixed: A JSON null baseUrl, forceState or source became "null" or "LL" on a device (round 1).

</details>

<details><summary>gap-core: 1 behavior changes, 1 bugs fixed</summary>

1. `core/src/api.ts`: It catches the URIError, logs listings.tag_cache_url.invalid once (severity error, errName URIError only, host of the tag-cache base URL, no keywords), makes no request and resolves []. buildTagCacheUrl still throws URIError; this is now documented and pinned by a test.
1. Fixed: fetchTagCacheListings rejected with URIError on keywords holding a lone surrogate, although it is documented never to reject (the old line 171 ran buildTagCacheUrl outside any try).

</details>

<details><summary>gap-flutter: 7 behavior changes, 3 bugs fixed</summary>

1. `scripts/coverage/flutter-summary.mjs`: Gate include = whole include = lib/**, with gate.exclude and an explicit EXCLUDED list, where each entry has an A10 category and a reason. Functions are derived from the source plus DA hits (lcov FN/FNDA are used when present). perFile now has branch/function counts and missedFunctions, and excluded files are listed. New checks: A10 category, stale exclusion, unlisted ignore-file, gate functions under 95%. There is a --functions CLI to inspect the scanner.
1. `scripts/coverage/flutter.sh`: Comment-only change: the header says the gate is lib/ minus A10 exclusions, that functions are derived, and that COVERAGE_ENFORCE covers lines, branches and functions.
1. `flutter/lib/src/widget_html.dart`: Both scripts set s.onerror, which posts {type:'scriptError', src: s.src}. defineSlot null posts {type:'slotError'}; a throw posts {type:'slotError', message}. Rendering is unchanged.
1. `flutter/lib/src/widget_bridge.dart`: Decodes scriptError (src must be text) to BannerScriptError, and slotError (message null or text) to BannerSlotError; wrong types give bridge.message.invalid. Adds widgetLoadedDeadline (15 s) and isWidgetScriptLoadError (partner.js as a non-main-frame error).
1. `flutter/lib/src/sellwild_widget.dart`: SellwildBanner logs ad.banner_script.network (url = script URL, host only) and ad.gpt_slot.invalid once; the host is not called. SellwildWidget logs widget.load.timeout once if no WIDGET_LOADED within 15 s; WIDGET_LOADED, a main-frame load error, a setup failure and dispose cancel it (new dispose override). A partner.js sub-resource error (Android) logs widget.script_load.network (fatal) and is still passed to onError. The spinner and host callbacks are unchanged.
1. `scripts/coverage/flutter-summary.mjs`: ignore-line and ignore-start must name an A10 category in their reason, or they are flagged (and --enforce fails). Exports A10, parseLcov, functionTotalsFrom, functionTotals, scanIgnores, namesA10 and ignoreProblems. Totals unchanged.
1. `scripts/coverage/flutter.sh`: Also runs node --test scripts/coverage/flutter-summary.test.mjs before the summary; a failure fails the run (exit 1). Recorded in the summary's commands.
1. Fixed: gpt.js and zone script load failures were silent (no onerror). Phase-1 lines 402 and 420, code ad.banner_script.network.
1. Fixed: defineSlot returning null (or throwing inside GPT's command queue) was silent. Phase-1 line 407, code ad.gpt_slot.invalid.
1. Fixed: No watchdog: when WIDGET_LOADED never arrived, the spinner ran forever with no report. Phase-1 line 94, code widget.load.timeout.

</details>

<details><summary>sdk-rn: 49 behavior changes, 24 bugs fixed</summary>

1. `react-native/src/htmlBuilder.ts`: escapeAttribute runs on every value: & becomes &amp; and the quote character becomes &quot; or &#39;. The script src is escaped the same way. What the HTML parser gives back is the exact value. Output bytes are the same for values with no '&' or quote character.
1. `react-native/src/SellwildBanner.tsx (+ src/bannerSizing.ts)`: It renders. The slot holds the BANNER_SIZES(_BY_ZONE) fallbacks, or 0x0. Native gets the label as before. ad.size.invalid (banner, warn) is reported once per placement.
1. `react-native/src/SellwildListingCard.tsx (+ src/listingCard.ts)`: Only numbers and numeric text are shown. Any other kind is hidden, as a non-numeric price already was. A first photo url that is not non-empty text gives the placeholder. Each issue is reported once as listings.item.invalid (listings, warn), with the field and its JSON kind only. Every valid listing renders the same as before.
1. `react-native/src/SellwildWidget.tsx (+ src/widgetBridge.ts)`: Each of these is reported once. Parse errors: bridge.message.parse. Invalid messages: bridge.message.invalid. Unknown types: bridge.message.unsupported. All use component bridge, severity warn. Host callback throws are reported as widget.host_callback.exception (webview, warn) and are still not rethrown. A wrong-typed field is reported as bridge.message.invalid and routed to the host as before. An ERROR whose message is not text reports bridge.message.invalid instead of bridge.script.exception, and onError still gets new Error(message).
1. `react-native/src/SellwildWidget.tsx`: onHttpError reports widget.webview_load.http with httpStatus, description and the url's host. It does not call onError.
1. `react-native/src/nativeViews.ts, SellwildBanner.tsx, SellwildFeed.tsx`: Same rendering. bridge.native_view.missing (banner or feed, error) is reported once per view name per process, after the first render that needs the view. The probe still runs once at module load.
1. `react-native/src/commands.ts`: Still no-ops. bridge.native_module.missing (bridge, warn) is reported once per method per process. Present methods are called as before, as methods of the module.
1. `react-native/src/htmlBuilder.ts, react-native/src/bannerHtml.ts (in-page scripts)`: They count the failure in window.__sellwildBridgeFailures. The page cannot report it, because the bridge is its only way out (contract exclusion 'in-page').
1. `react-native/src/bannerHtml.ts`: They moved as-is to bannerHtml.ts, apart from the catch above. htmlBuilder.ts re-exports buildBannerHtml. The file is excluded from the gate as 'dead: pending delete decision'.
1. `contracts/failure-codes.json, core/src/failures/codes.ts`: Both also list react-native (add-code --merge-clients; core mirror regenerated).
1. `react-native/src/widgetBridge.ts (used by SellwildWidget.tsx:77-78)`: JSON null counts as wrong-typed: bridge.message.invalid ('AD_IMPRESSION zoneId is null', 'ERROR message is null', 'LISTING_CLICK listing is null'), reported once and not also as bridge.script.exception. LISTING_CLICK checks listing then url, whichever one routes. Routing is unchanged: onAdImpression(null), onError(new Error(null)) = 'null', and the url stub still routes next to a null listing.
1. `react-native/src/SellwildWidget.tsx`: decodeWidgetMessage reports bridge.message.parse / invalid / unsupported once (component bridge, warn) and still routes wrong-typed fields as before. A throwing host callback is reported as widget.host_callback.exception (warn) and not rethrown, as before. onHttpError reports widget.webview_load.http (status, host, description) and does not call onError. onError reports widget.webview_load.network before the host hears.
1. `react-native/src/SellwildBanner.tsx`: The slot holds the BANNER_SIZES fallbacks, or 0x0. Native gets the label as before. ad.size.invalid (warn, zoneId) is reported once per placement, even when the view manager is also missing.
1. `react-native/src/nativeViews.ts (SellwildBanner, SellwildFeed)`: bridge.native_view.missing (error, component banner/feed) is reported once per process on first render. Rendering is unchanged.
1. `react-native/src/commands.ts`: They are still no-ops, and bridge.native_module.missing (warn) is reported once per method per process.
1. `react-native/src/SellwildListingCard.tsx + listingCard.ts`: A price that is not a number or text is hidden and reported as listings.item.invalid (warn, field + JSON kind only), once per value. 'photos is ...' and 'photos[0] url is ...' are reported the same way.
1. `react-native/src/htmlBuilder.ts configToAttributes + script src`: escapeAttribute escapes & first, then the quote in use, for every typed, passthrough and script-src value. The widget gets each value exactly.
1. `react-native/src/htmlBuilder.ts injected send()`: It counts window.__sellwildBridgeFailures. It cannot be reported: the bridge is the page's only way out.
1. `react-native/src/htmlBuilder.ts / bannerHtml.ts / nativeConfig.ts`: buildBannerHtml moved to bannerHtml.ts and is re-exported from htmlBuilder (same output). buildPrebidPreConfigScript, configToAttributes and escapeAttribute are exported. toNativeFeedConfig is extracted with the same key set.
1. `react-native/src/nativeConfig.ts (toNativeFeedConfig, nativeZoneId, nativeZoneIds)`: Text zone ids are sent as they are. A finite number other than 0 is sent as its text. 0 and non-finite values are left out (undefined, so the bridge drops them), which matches how iOS read them before. The key set is unchanged.
1. `react-native/src/htmlBuilder.ts (scriptJson, buildPrebidPreConfigScript)`: Every '<' in that JSON is written as <. JS reads back the same value, and the script ends where the SDK closes it.
1. `react-native/ios/SellwildRNModule.swift:58`: It calls SellwildBannerHostView.configFromMap (the same mapping the banner uses).
1. `react-native/android/.../SellwildBannerViewManager.kt, SellwildFeedViewManager.kt, SellwildModule.kt (prewarm)`: It is caught. The view logs bridge.config.invalid (fatal) and sets up no ad or feed. prewarm logs it (warn) and does nothing.
1. `react-native/android/.../SellwildFeedViewManager.kt (readText, readTextList)`: A zone id that is not text is dropped, as iOS does, and all such problems go into one bridge.config.invalid (error). Text and null behave as before.
1. `react-native/android/.../SellwildBannerViewManager.kt, SellwildFeedViewManager.kt (emit)`: It is caught and logged as bridge.event_emit.exception (warn). The event is dropped.
1. `react-native/android/.../SellwildModule.kt (setExternalUserIds)`: The skip rules are the same, and one bridge.eids.invalid (warn) says how many were skipped. A throw is caught, logged as bridge.eids.invalid, and no eids are set.
1. `react-native/ios/SellwildBannerViewManager.swift, SellwildFeedViewManager.swift (remoteJSON)`: SellwildRNBridgeRules.remoteJSON checks isValidJSONObject first and catches the error. A failure is logged as bridge.config.exception (warn), and remoteJSON stays nil, as before.
1. `react-native/ios/* and react-native/android/* (reporting only)`: The behavior is the same, and each is now reported once: bridge.props.invalid (per view, per problem), bridge.config.invalid, bridge.geo.invalid (iOS) and bridge.eids.invalid. A size that is not a JS AdSize is still reported only by JS (ad.size.invalid).
1. `react-native/src/widgetBridge.ts (used by SellwildWidget.tsx:77-78) [earlier round]`: JSON null counts as wrong-typed and is reported as bridge.message.invalid, once. Routing is unchanged.
1. `react-native/src/SellwildWidget.tsx [earlier round]`: decodeWidgetMessage reports bridge.message.parse, invalid or unsupported. A host callback that throws is reported as widget.host_callback.exception and not rethrown. onHttpError reports widget.webview_load.http. onError reports widget.webview_load.network.
1. `react-native/src/SellwildBanner.tsx [earlier round]`: The slot holds the BANNER_SIZES fallbacks, or 0x0, and ad.size.invalid is reported once per placement.
1. `react-native/src/nativeViews.ts, commands.ts [earlier round]`: bridge.native_view.missing is reported once per process. bridge.native_module.missing is reported once per method. Rendering and no-op behavior are unchanged.
1. `react-native/src/SellwildListingCard.tsx + listingCard.ts [earlier round]`: A price that is neither a number nor text is hidden and reported as listings.item.invalid, as are bad photos values.
1. `react-native/src/htmlBuilder.ts attributes + script src [earlier round]`: escapeAttribute escapes & first, then the quote in use.
1. `react-native/android/src/main/java/com/sellwild/rnsdk/SellwildModule.kt + RnGeo.kt + RnBridgeRules.kt (this round)`: RnGeo.parse checks each field's ReadableType. A wrong-typed field is dropped and the other fields are set, as on iOS. bridge.geo.invalid (warn) names each dropped field and its type, never the value ('geo.lat is text, not a number, so it was dropped'). A map that cannot be read at all is caught, reported ('geo could not be read, so geo was cleared' + error), and geo is cleared. {} and null still clear with no report.
1. `react-native/android/src/main/java/com/sellwild/rnsdk/RnGeo.kt readableMapToGeo (config paths, this round)`: It still throws, and the caller still reports the config. The exception is now IllegalArgumentException, and its message names the fields ('geo.lat is text, not a number, so it was dropped').
1. `react-native/android/src/main/java/com/sellwild/rnsdk/RnPrebidServer.kt, SellwildFeedViewManager.kt, SellwildBannerViewManager.kt (this round)`: RnPrebidServer.fromConfig returns (config, problem) and does not log. The feed puts the problem in its problems list: one bridge.config.invalid for the config, as on iOS. The banner logs it once. A prebidServer that is not an object, or an accountId/endpoint that is not text, now gets the default Prebid Server and a report with the iOS text, and the rest of the config is used.
1. `react-native/ios/SellwildRNBridgeRules.swift geoMap/geoFieldProblem (this round)`: The same fields are dropped, as before, but they are now reported as bridge.geo.invalid with the same text as Android. A payload that is not an object still clears geo and is reported.
1. `react-native/src/listingCard.ts (this round, vs rounds 1-3)`: It is hidden, as at HEAD, and not reported. listing.schema.json allows any text there (numOrNumericString is number | string). A NaN number, a boolean, a list and an object are still reported.
1. `react-native/src/nativeConfig.ts toNativeFeedConfig + nativeZoneId (round 3; record corrected this round)`: JS sends zone ids as text and leaves out 0 (undefined). The bridge drops an undefined value, so for core's default config the iOS feed gets up to 3 fewer keys (bannerZid, bottomBannerZid, mobileBannerZid) than at HEAD. The iOS feed re-applies config by NSDictionary.hash, which is the key count, so a zone that goes from 0 to set now changes the count and re-applies. The earlier record said 'the key set is unchanged'. That was wrong and is corrected here and in the code comment.
1. `react-native/src/nativeConfig.ts nativeZoneId: iOS numeric zone ids (round 3; named separately this round)`: JS sends it as its decimal text, and the iOS feed now uses it.
1. `react-native/test/SellwildWidget.test.tsx (this round)`: Each onError test also asserts how many times logFailure ran through countLogFailureCalls: {'widget.webview_load.network': 1}, or 3 for three different errors.
1. `react-native/android glue: SellwildBannerViewManager / SellwildFeedViewManager / SellwildModule (rounds 2-3)`: The config prop is read in a try/catch (bridge.config.invalid, fatal, no ad or feed). Emit is in a try/catch (bridge.event_emit.exception). eids that cannot be read, and skipped entries, are reported as bridge.eids.invalid. prewarm with an unreadable config is reported as bridge.config.invalid (warn). Banner props are reported as bridge.props.invalid once per distinct problem. A size label JS already reported is not reported again.
1. `react-native/ios glue: SellwildBannerViewManager / SellwildFeedViewManager / SellwildRNModule (rounds 2-3)`: remoteJSON checks isValidJSONObject first and reports bridge.config.exception. Also reported: bridge.props.invalid, bridge.config.invalid (the feed sends one report for all its problems), bridge.geo.invalid and bridge.eids.invalid. The native SDK's own failures carry wrapper react-native (SellwildRNWrapper).
1. `react-native/src/SellwildWidget.tsx + widgetBridge.ts (rounds 0-1)`: Reported once each: bridge.message.parse / invalid / unsupported (null counts as wrong-typed), widget.host_callback.exception (not rethrown), widget.webview_load.http (onError not called) and widget.webview_load.network (before onError runs). Routing is unchanged.
1. `react-native/src/SellwildBanner.tsx + bannerSizing.ts (round 0)`: The slot uses the BANNER_SIZES fallback, or 0x0. ad.size.invalid is reported once per placement.
1. `react-native/src/nativeViews.ts, commands.ts (round 0)`: bridge.native_view.missing is reported once per process. bridge.native_module.missing is reported once per method per process. Rendering and the no-op calls are unchanged.
1. `react-native/src/listingCard.ts (round 0)`: Such a price is hidden and reported as listings.item.invalid (field and JSON kind only). So are bad photos values.
1. `react-native/src/htmlBuilder.ts (rounds 0-3)`: escapeAttribute escapes & first, then the quote in use. scriptJson escapes '<'. send() counts window.__sellwildBridgeFailures. buildBannerHtml moved to bannerHtml.ts and is re-exported with the same output.
1. Fixed: Attribute values were not HTML-escaped. A '"' in a CMS value (web-passthrough-keys LINK_TEXT) ended the attribute and closed the <sellwild-widget> tag early, so every later attribute was dropped.
1. Fixed: AD_DIMENSIONS[size] was undefined for a size label that is not an AdSize, and the baseline useMemo threw a TypeError, which crashed the render for JS callers.
1. Fixed: A boolean true price showed as '$1', and a one-element array as its element, because Number(true) is 1.
1. Fixed: The empty catch in handleMessage silently swallowed non-JSON messages and any exception thrown by host callbacks.
1. Fixed: A size label that is not an AdSize threw a TypeError in render (AD_DIMENSIONS[size].width). Fixed via adDimensions() plus an ad.size.invalid report.
1. Fixed: A boolean price showed as '$1' (Number(true)) and a one-element array as its element. It is now hidden and reported as listings.item.invalid.
1. Fixed: Attribute values were not HTML-escaped. A CMS LINK_TEXT with double quotes cut off the <sellwild-widget> tag and dropped every later attribute.
1. Fixed: The partner.js script src was not escaped. A host widgetJsUrl with a double quote was cut, and a character reference was decoded (red run this round).
1. Fixed: The RN iOS glue did not compile at HEAD. prewarm called SellwildBannerViewManager.configFromMap, which does not exist (it is on SellwildBannerHostView). Every RN iOS host build since 72dec3b would fail.
1. Fixed: getString on bannerZid/bottomBannerZid/mobileBannerZid (and on mobileZids entries) threw UnexpectedNativeTypeException for the number JS sent: core's default bannerZid 0, which the real weatherbug config also has. This crashed the Android feed. Fixed in JS (nativeZoneId) and in the glue (typed read, dropped and reported).
1. Fixed: buildPrebidPreConfigScript put JSON.stringify output into an inline <script>. A value holding '</script>' (appStoreUrl, tcString, prebidServer fields) ended the script and broke the page.
1. Fixed: configFromMap uses getBoolean/getInt/getString without type checks, so a wrong type or a null (new architecture) throws. It is now caught and reported as bridge.config.invalid in banner, feed and prewarm instead of crashing the host.
1. Fixed: [earlier round] A size label that is not an AdSize threw a TypeError in render.
1. Fixed: [earlier round] A boolean price showed as '$1'.
1. Fixed: [earlier round] Attribute values were not HTML-escaped, so a CMS LINK_TEXT with quotes cut off the tag.
1. Fixed: [earlier round] The partner.js src was not escaped.
1. Fixed: setGeo with a wrong-typed field (lat as text) threw UnexpectedNativeTypeException from RnGeo's getters inside a @ReactMethod, which crashed the host app. Red run: r4/kt/head-geo-repro.log. Fixed: type-checked parse, field dropped and reported, and a try/catch that clears geo.
1. Fixed: A prebidServer that was not an object, or an accountId/endpoint that was not text, threw and failed the whole banner or feed config. iOS used the default server and reported it. The feed also sent 2 reports for one bad config. Fixed: the problem goes to the caller, and one report is sent.
1. Fixed: (round 3) The Android RN feed threw on a numeric zone id (getString), and core's default bannerZid 0 is a number. Fixed in JS (nativeZoneId) and in native (readText drops it and reports it).
1. Fixed: (round 0) A size label that is not an AdSize threw a TypeError in render. Fixed via adDimensions() and an ad.size.invalid report.
1. Fixed: (round 0) A boolean price showed as '$1', and a one-element array showed as its element. It is now hidden and reported.
1. Fixed: (round 0) Attribute values were not escaped: a CMS LINK_TEXT with a double quote cut off the <sellwild-widget> tag.
1. Fixed: (round 1) The partner.js src was not escaped: a widgetJsUrl with a double quote was cut, and &quot; was decoded.
1. Fixed: (round 3) A config value holding </script> ended the Prebid pre-config script. scriptJson now escapes '<'.

</details>

<details><summary>sdk-android-views: 12 behavior changes, 13 bugs fixed</summary>

1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdView.kt`: Reports ad.setup.missing once, calls listener.onAdFailed, loads nothing
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildWidgetView.kt`: Reports widget.setup.missing, calls listener.onError, loads nothing
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildWidgetView.kt`: Reports widget.webview_process.exception, drops the dead WebView, tells listener.onError, returns true. The next load() builds a new WebView.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildFeedView.kt`: Reports feed.view_type.invalid and binds an empty row
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildFeedView.kt`: An Error from FeedImages.fetch (download plus decode) or FeedImages.decode (data: URI) keeps the placeholder and reports feed.image.invalid once ('image could not be decoded: <error text>'). An Exception from fetch is still feed.image.network.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildAdView.kt`: Both sites catch Throwable again, as at HEAD, and report ad.bid_inspect.exception or house.open_url.exception. The bid is treated as not video, and the tap does nothing.
1. `android/src/main/kotlin/com/sellwild/sdk/core/AdDecisions.kt`: A JSON null GAM counts as no unit (RemoteValues.optText). The SDK uses the GAM test unit and reports ad.gam_unit.missing (fatal), once per config.
1. `android/src/main/kotlin/com/sellwild/sdk/SellwildWidgetView.kt`: A certificate error on the widget bundle (partner.js) reports widget.webview_load.network ('SSL error <primaryError>'). Other subresources are not reported. The load is still cancelled through super, so the widget never proceeds past a bad certificate.
1. Fixed: load()/resume() before setup() crashed the host (lateinit config)
1. Fixed: load() before setup() threw IllegalStateException via check()
1. Fixed: When the WebView render process died, the unhandled event let the system kill the app
1. Fixed: An unknown view type threw IllegalArgumentException
1. Fixed: The window-root self-heal tests (ad view and feed view) dispatched before the window attached the view, so the no-parent branch never ran and the assertion passed for the wrong reason
1. Fixed: load()/resume() before setup() crashed the host (lateinit config)
1. Fixed: load() before setup() threw IllegalStateException via check()
1. Fixed: When the WebView render process died, the unhandled event let the system kill the app
1. Fixed: An unknown view type threw IllegalArgumentException
1. Fixed: Regression from an earlier phase-3 round: FeedImages caught only Exception around fetch and nothing around decode. An OutOfMemoryError on a huge listing photo reached the main thread's uncaught handler and would kill the host app (HEAD's runCatching had kept the placeholder).
1. Fixed: Regression from an earlier phase-3 round: isVideo() caught only Exception and launchUrl (line 594) only RuntimeException, so an Error escaped to the host. HEAD used runCatching.
1. Fixed: A certificate error on partner.js blanked the widget with no report (no onReceivedSslError override)
1. Fixed: The window-root self-heal tests (ad view and feed view) dispatched before the window attached the view, so the no-parent branch never ran and the assertion passed for the wrong reason

</details>

<details><summary>sdk-ios-views: 21 behavior changes, 14 bugs fixed</summary>

1. `ios/Sources/SellwildSDK/Core/SellwildFormat.swift (was a copy in SellwildFeedView and one in SellwildHouseAdView)`: The price is written in decimal form: "$100000000000000000000.00".
1. `ios/Sources/SellwildSDK/SellwildFeedView.swift`: It logs feed.cell.invalid (fatal) and returns a blank cell.
1. `ios/Sources/SellwildSDK/Core/SellwildWidgetPage.swift (the bridge script SellwildWidgetView loads)`: It counts each failed post in window.__sellwildBridgeFailures, as the Android and React Native pages do.
1. `ios/Sources/SellwildSDK/SellwildFeedView.swift, SellwildAdView.swift, SellwildNativeAdView.swift, SellwildPrebidMobile.swift`: Failures go to SellwildFailures.log. Traces that are not failures go to SellwildLog.debug, which prints only with the SDK debug flag on.
1. `ios/Sources/SellwildSDK/SellwildAdView.swift`: It also sets SellwildFailures.context.partnerCode.
1. `ios/Sources/SellwildSDK/SellwildWidgetView.swift`: All three report widget.webview_load.network or widget.webview_process.exception. Cancelled navigations are skipped. Delegate calls are unchanged.
1. `ios/Sources/SellwildSDK/Core/SellwildWidgetPage.swift`: Same delegate calls, and bridge.message.invalid, parse or unsupported is reported. An ERROR message also reports bridge.script.exception with the page's text. The delegate still gets SellwildError.invalidResponse.
1. `scripts/coverage/ios-summary.mjs, scripts/coverage/ios.sh`: ios.sh runs a full export. Regions and functions are counted from the function records; this matches llvm-cov's summary exactly when nothing is excluded, and a self-check guards it. Lines are per source line from the xccov archive. A10 line ranges are read from source comments and listed with their reason.
1. `ios/Sources/SellwildSDK/SellwildNativeAdView.swift`: A result that SellwildAdPolicy.isAuctionFailure flags logs ad.prebid_auction.invalid once (component native, severity warn, message 'the native auction failed: <name>', zoneId), then onFailed(nativeNoFill) as before. No-bids (7) and no cached bids (11) keep the debug line only. The host callbacks and the adError event do not change.
1. `ios/Sources/SellwildSDK/Core/SellwildImageLoad.swift`: An HTTP status outside 2xx is a failed download: nothing is shown or cached, and it is reported (feed.image.network or ad.native_image.network with httpStatus). The 8 MB cap is unchanged.
1. `ios/Sources/SellwildSDK/SellwildWidgetView.swift`: webView(_:decidePolicyFor navigationResponse:) logs widget.webview_load.http (message 'HTTP <status>', httpStatus, url host) for a 4xx or 5xx main-frame response. It then decides exactly as WebKit's default: canShowMIMEType ? .allow : .cancel. Sub-frames (ad iframes) are not reported.
1. `ios/Sources/SellwildSDK/Core/SellwildFormat.swift`: Int(exactly:) is used; a whole price too large for Int takes the decimal form ('$100000000000000000000.00').
1. `ios/Sources/SellwildSDK/SellwildFeedView.swift`: A cell of the wrong type logs feed.cell.invalid (severity fatal) and the row is blank.
1. `ios/Sources/SellwildSDK/SellwildAdView.swift`: SellwildFailures.setContext sets partnerCode next to environment.events.partnerCode, so failure events carry the partner.
1. `ios/Sources/SellwildSDK/Core/SellwildWidgetPage.swift`: The catch runs `window.__sellwildBridgeFailures = (window.__sellwildBridgeFailures || 0) + 1;` (SellwildWidgetPage.swift:243-248). The page partners load changes by that one statement. Nothing else in the script changed. SellwildWidgetPageTests.testPageLoadsTheWidgetBundleAndTheBridgeScript pins it.
1. `ios/Sources/SellwildSDK/Core/SellwildImageLoad.swift`: A status outside 2xx is a failed download: nothing is shown or cached, and it is reported as feed.image.network (feed) or ad.native_image.network (native) with httpStatus. The 8 MB cap is unchanged. A cancelled download is still not reported.
1. `ios/Sources/SellwildSDK/SellwildFeedView.swift`: A cell of the wrong type leaves the row blank and logs feed.cell.invalid (fatal) once per occurrence. SellwildFeedViewTests.testACellOfTheWrongTypeIsReportedAndLeftBlank pins it.
1. `ios/Sources/SellwildSDK/Core/SellwildFormat.swift`: One shared SellwildFormat.price uses Int(exactly:). A whole price too large for an Int takes the decimal form ("$100000000000000000000.00"). Every other price formats as before. SellwildFeedLayoutTests.testAWholePriceTooLargeForAnIntIsNotACrash pins it. Repro: scratchpad/phase3/sdk-ios-views/repro-price.swift and repro-price.log.
1. `ios/Sources/SellwildSDK/SellwildWidgetView.swift`: decidePolicyFor navigationResponse reports a main-frame HTTP error (widget.webview_load.http) and then makes WebKit's own default decision (canShowMIMEType ? .allow : .cancel). didFailProvisionalNavigation reports widget.webview_load.network (the delegate is not told, as before). webViewWebContentProcessDidTerminate reports widget.webview_process.exception. A bridge ERROR is reported as bridge.script.exception, and the delegate still gets invalidResponse. A malformed bridge message is reported (bridge.message.parse / invalid / unsupported), and a LISTING_CLICK with a broken listing still opens its URL. The host sees no change.
1. `ios/Sources/SellwildSDK/SellwildAdView.swift`: init also runs SellwildFailures.setContext { $0.partnerCode = config.partnerCode }. Failure reports carry the partner code even when an app builds its config by hand and never calls SellwildSDK.configure.
1. `scripts/coverage/ios-summary.mjs`: whole counts every target file under ios/Sources/SellwildSDK, including range lines and EXCLUDED files. gate = whole minus exclusions. perFile numbers are the gated part, plus a `whole` object when a file has excluded lines. An EXCLUDED file appears with inGate false and excluded true.
1. Fixed: Int(value) trapped for a whole price above Int.max. The listing schema allows any numeric text.
1. Fixed: The dequeued cells were force-cast (as!), so a wrong cell type crashed the app.
1. Fixed: The bridge script had an empty JS catch in send().
1. Fixed: The line totals from the xccov report and the llvm-cov summary count a line once per function that spans it, so closure lines count twice. That inflates both totals and made line-range exclusion impossible.
1. Fixed: A native auction error (5, 6, 8, 3, 10...) was treated as no-fill with only a debug print: a silent swallow under A1.
1. Fixed: The registry lists ios as a client of widget.webview_load.http, but iOS had no emitter.
1. Fixed: The auctionBidderParams drift note pointed at SellwildAdView L388, which no longer exists. It now names SellwildLiveAdNetwork.runBannerAuction; the meaning is unchanged.
1. Fixed: A whole price above Int.max trapped in Int(_:) and crashed the feed card and house backdrop (fixed in an earlier round; reproduced first).
1. Fixed: A force cast (as!) on dequeued feed cells crashed on a wrong type. It is now feed.cell.invalid plus a blank row (earlier round).
1. Fixed: Force casts on dequeued cells crashed the app when a cell had the wrong type. Now the row is left blank and feed.cell.invalid is logged.
1. Fixed: Int(value) trapped on a whole price of 2^63 or more (feed card and house ad backdrop). Fixed with Int(exactly:).
1. Fixed: Feed photos and native asset images showed a non-2xx body that decoded as an image (the feed cached it too).
1. Fixed: Test gap (V8): no shell test sent a LISTING_CLICK with both a problem and a message through handleMessage, so the report could be suppressed. Added testABrokenListingStillOpensItsURLAndIsReportedOnce. V8 is now caught.
1. Fixed: whole also dropped the A10 exclusions, so whole always equaled gate.

</details>

