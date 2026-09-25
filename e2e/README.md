# Sample app e2e (Maestro)

## What this is

1. Each platform has a sample app named "Sellwild Sample".
2. It has five tabs: Feed, Ads, Listings, Diagnostics, Legacy.
3. Maestro flows open every tab and check each screen's key element by id.
4. The ids live in `contracts/e2e/ids.json`. Add an id there before you use it. Never rename one.
5. `scripts/e2e/run.sh <app>` runs one app from build to shutdown.

## Setup

1. Maestro 2.10.0, once per machine:

   ```sh
   curl -fsSL https://get.maestro.mobile.dev -o /tmp/maestro-install.sh
   PATH="$HOME/.maestro/bin:$PATH" MAESTRO_VERSION=2.10.0 bash /tmp/maestro-install.sh
   ~/.maestro/bin/maestro --version   # 2.10.0
   ```

   The `PATH` prefix stops the installer from editing your shell profiles.
2. A JDK 17. `run.sh` finds it, or set `JAVA_HOME`.
3. iOS: Xcode 26.5. `xcodegen` only to regenerate a sample project.
4. Android: the Android SDK in `~/Library/Android/sdk` (or `ANDROID_HOME`), with the AVD `Pixel_5_API_36` (API 36, arm64, Google APIs).
5. Flutter apps: the `flutter` CLI on `PATH` (or set `FLUTTER`). Flutter 3.47.5 here. `flutter precache --ios --android` once, so the first build does not download the engine.
6. React Native apps: Node and npm (Node 25 here), and CocoaPods for `rn-ios` (1.16.2 here). `run.sh` runs `npm ci` itself when `node_modules` is stale.

## Run

1. One app: `bash scripts/e2e/run.sh ios`, `android`, `flutter-ios`, `flutter-android`, `rn-ios` or `rn-android`.
2. The apps: `bash scripts/e2e/run.sh --list`.
3. Every app, one at a time, with the gate's step table: `bash scripts/gate.sh --e2e` (TESTING.md, "E2E"). Never part of `--fast` or `--full`.
4. `run.sh` builds, boots the device, installs, runs the app's flows, copies the screenshots, then shuts the device down.
5. All of that runs inside one call of the native lock (`SELLWILD_NATIVE_LOCK`). One native build or booted device at a time. When a parent process already runs the lock (the gate run under it), `run.sh` does not take it again.
6. Exit status: 0 all flows passed, 1 a flow failed, 2 setup failed (unknown app, no Maestro, build, boot or install).
7. `SELLWILD_E2E_NO_BUILD=1` reuses the last build.
8. Output goes to `e2e/artifacts/<app>/` (gitignored):
   1. `screenshots/<flow>-<screen>.png`: one per screen, plus a screenshot of any failed step.
   2. `maestro.log`: Maestro's summary and every step with its status.
   3. `report-<flow>.xml`: JUnit.
   4. `build.log`, `device.log`, and `emulator.log` on Android.
   5. `maestro/<flow>/`: Maestro's own output (commands, logs, the view hierarchy of a failed step).
9. Build caches go to `e2e/.cache/` (gitignored).
10. Maestro gets a minute to start its driver on the device (`MAESTRO_DRIVER_STARTUP_TIMEOUT`, 60000 ms). Its own default was too short once, on a busy machine.

## The common subflows (`e2e/maestro/common/`)

1. `launch.yaml`: launch with `clearState`, wait for the tab bar.
2. `no-crash.yaml`: no crash or error dialog, and the tab bar is still on screen. Every screen runs it.
3. `feed.yaml`: the feed list and at least one `sw.listing.card`. Screenshot `feed`.
4. `ads.yaml`: the 320x50 and 300x250 slots and their measured sizes. Fill is not checked. Screenshot `ads`.
5. `listings.yaml`: at least one card and status `<n> listings, load 1`. Refresh, then `load 2`. Screenshot `listings`.
6. `diagnostics.yaml`: SDK version, `sellwild / sellwild-sample`, config source `fallback`, failures. Screenshot `diagnostics`.
7. `legacy.yaml`: the title "Legacy WebView widget (deprecated)" and the WebView container only. Screenshot `legacy`.

Flags each app's flow sets in `env` (the string `"true"` turns one on):

1. `APP_ID`: the bundle id or application id.
2. `FEED_AD_ROWS`: the feed has ad rows that carry `sw.feed.ad` (set by the SDK feed, or on Flutter by the app). The feed flow then scrolls to one.
3. `NATIVE_AD`: the platform has a public native ad view. The ads flow checks `sw.ad.native`.
4. `HOUSE_AD`: the platform has a public house ad view. The ads flow checks `sw.ad.house`.
5. `FAILURE_SINK`: the app can list the failure codes the SDK reported. Diagnostics must then show `config.fetch.http`. Otherwise it must show "not available on this platform".

## Why "fallback" and config.fetch.http

1. Every sample uses partner code `sellwild` and slug `sellwild-sample`.
2. The CDN has no app config for that slug. It answers 403.
3. So the SDK keeps its built-in config and Google's test ad units, and reports `config.fetch.http` once a launch. That is expected.
4. Listings come from `https://cache.sellwild.com/listings-img-data-sm-avif-fandom`, passed as `listingsUrl`.
5. Events still go to events.sellwild.com under code `sellwild`.

## Apps

### ios

1. App: `samples/feed-demo-ios`. Project `SellwildSample.xcodeproj` (xcodegen), scheme `SellwildSample`, bundle id `com.sellwild.sample`.
2. The SDK comes from the repo's root `Package.swift`, so the app tests the SDK as checked out.
3. Flow: `e2e/maestro/ios/sample.yaml`. Flags: `FEED_AD_ROWS` on, `NATIVE_AD` on, `HOUSE_AD` off, `FAILURE_SINK` off.
4. Device: the iPhone that `scripts/coverage/ios.sh` picks (iPhone 17, iOS 26.5 here). Set `SELLWILD_IOS_SIM_ID` to pick another.
5. Time: about 3 minutes (build 20s warm, boot 12s, flow 75s). The first build also fetches the SwiftPM packages.
6. Not on iOS:
   1. House ad: there is no public house ad view. House backfill runs inside `SellwildAdView` on a no-fill.
   2. Failure codes: there is no public failure sink. The screen shows the public `SellwildFailures.context` instead.
7. WebViews: Maestro can see into a WKWebView on iOS: the GAM test creative's iframe and images show in the hierarchy. The Legacy widget's content was not checked. The flows check only the container.

### android

1. App: `samples/feed-demo-android`. Jetpack Compose, application id `com.sellwild.sample`, name "Sellwild Sample".
2. The build first publishes the SDK in `android/` to mavenLocal (`publishReleasePublicationToMavenLocal`). The sample takes `com.sellwild:sdk` only from there, at the version in `android/build.gradle.kts`. So the app tests the SDK as checked out.
3. Then it runs `./gradlew :app:assembleDebug` in the sample, with 2 Gradle workers, and stops Gradle before the emulator boots.
4. Flow: `e2e/maestro/android/sample.yaml`. Flags: `FEED_AD_ROWS` on, `NATIVE_AD` on, `HOUSE_AD` off, `FAILURE_SINK` off.
5. Device: the AVD `Pixel_5_API_36` on port 5554 (`emulator-5554`), booted with `-memory 2560 -no-snapshot-save -no-audio -no-boot-anim`. 2560 MB is the emulator's floor for API 36; the AVD's own 4 GB is not used, and its config is not changed. Animations are turned off, and `pm trim-caches` clears app caches.
6. Why not `Pixel_5_API_32`: its data partition is 800 MB and full (11 MB free after `pm trim-caches`). The 15 MB sample APK fails with "Requested internal only, but not enough space". Freeing room would mean deleting apps on that AVD or wiping it.
7. `SELLWILD_ANDROID_AVD` picks another AVD, `SELLWILD_ANDROID_MEMORY` another RAM size in MB.
8. Shutdown: `adb emu kill`, then the emulator process if it is still up after 30s, then `gradlew --stop`.
9. Ids: the app's ids are Compose test tags, read as resource-ids (`testTagsAsResourceId`). The SDK feed's rows set their resource-id themselves (`SellwildFeedE2EIdTest`).
   1. A test tag on an `AndroidView` (such as `SellwildFeed`) does not reach UI Automator. The app puts `sw.feed.list` and `sw.legacy.webview` on a `Box` around the view.
10. Not on Android:
   1. House ad: `SellwildHouseAdView` is internal. House backfill runs inside `SellwildAdView` on a no-fill.
   2. Failure codes: there is no public failure sink. The screen shows the public `SellwildFailures.context` instead.
11. WebViews: debug builds turn on `WebView.setWebContentsDebuggingEnabled`. Maestro sees inside the WebViews on Android: the GAM creative's text and the Legacy widget's listings show in the hierarchy. The flows still check only the containers.
12. Time: about 2 minutes warm (124s here: SDK publish 11s, sample build 13s, boot 18s, flow 61s). A cold build also downloads the Gradle dependencies.

### flutter-ios and flutter-android

1. App: `samples/flutter-demo` (`flutter create`, org `com.sellwild`). Id `com.sellwild.sample.flutter` on both platforms, name "Sellwild Sample".
2. The SDK comes from `../../flutter` (a path dependency), so the app tests the SDK as checked out.
3. One flow for both: `e2e/maestro/flutter/sample.yaml`. Flags: `FEED_AD_ROWS` on, `NATIVE_AD` off, `HOUSE_AD` off, `FAILURE_SINK` on.
4. What Flutter has, so what the app shows:
   1. Feed: the Flutter SDK has no feed component. The app draws `fetchListings` with `SellwildListingCard`, two a row, and puts a `SellwildBanner` ad row after every four cards. The app sets `sw.listing.card` and `sw.feed.ad` itself.
   2. Ads: `SellwildBanner` at 320x50 and 300x250. It is a WebView that runs Google Publisher Tag. The screen says so.
   3. No native ad view and no house ad view. The Ads screen says "Not in the Flutter SDK".
   4. Failure codes: Flutter has a public failure sink (`SellwildFailures.setContext(sink:)`). The app records each code and sends the event on, as the SDK does without a sink. So Diagnostics must show `config.fetch.http`.
   5. GAM tag: the built-in Flutter config has none. The app sets Google's GPT test unit `/6499/example/banner` when the CDN config has none.
5. Ids: `Semantics(identifier:)`. It is the accessibilityIdentifier on iOS and the resource-id on Android. `main.dart` turns the semantics tree on at launch (`SemanticsBinding.instance.ensureSemantics()`).
6. `flutter-ios`:
   1. Build: `flutter pub get`, then `flutter build ios --simulator --debug`. Plugins come in through Swift Package Manager (no CocoaPods).
   2. Device: the same iPhone as `ios` (`scripts/e2e/lib/ios-sim.sh`).
   3. Time: about 2.5 minutes warm (149s here: Xcode build 23s, flow 52s). The first run took 187s (Xcode build 42s, boot 11s, flow 53s).
7. `flutter-android`:
   1. Build: `flutter pub get`, then `flutter build apk --debug --target-platform android-arm64`, with 2 Gradle workers. Then `gradlew --stop` in the sample.
   2. The app's Gradle heap is 2 GB (the template asks for 8 GB).
   3. Flutter runs Gradle with the JDK it finds first: Android Studio's (JDK 21 here), not `JAVA_HOME`.
   4. The first build downloads Gradle 9.3.1 and installs the NDK the template names (28.2, 2.8 GB) into the Android SDK.
   5. Device: `Pixel_5_API_36`, as for `android` (`scripts/e2e/lib/android-emu.sh`). The debug APK is 79 MB.
   6. Time: about 2 minutes warm (106s here: Gradle 14s, boot 18s, flow 51s). The first run took 348s (Gradle 256s with the downloads).
8. WebViews:
   1. Android: Maestro sees inside the Flutter WebViews. The banner page's `#ad` div and GPT's iframe container show in the hierarchy.
   2. iOS: not checked.
   3. The flows check only the containers.
9. Fill: GPT loads in the banner WebViews, but the test unit did not fill in these runs. After 25s on Android, GPT's slot container still had a height of 0.
10. `FLUTTER` picks another `flutter` CLI.

### rn-ios and rn-android

1. App: `samples/demo-app` (React Native 0.74.6, npm). Id `com.sellwild.sample.rn` on both platforms, name "Sellwild Sample". Its README has the details.
2. The SDK as checked out:
   1. JS: `metro.config.js` maps `@sellwild/react-native-sdk` to `react-native/` and `@sellwild/sdk-core` to `core/`. Core is read from its gitignored `dist/`, so every build first runs `npm --prefix core run build` (tsgo, under a second).
   2. iOS: the local pods `SellwildSDK` (root podspec) and `SellwildSDK-RN` (`react-native/`), in `ios/Podfile`.
   3. Android: the bridge is the Gradle project `:sellwild-react-native-sdk` (`react-native/android`). The SDK comes from mavenLocal as `com.sellwild:sdk:1.7.7`, published first from `android/`, as for `android`.
3. Release builds: the JS bundle (Hermes bytecode) is inside the app. Metro runs once, as a bundler step of the build, and exits. No Metro server runs while the flows do, and no dev menu or LogBox shows.
4. One flow for both: `e2e/maestro/react-native/sample.yaml`. Flags: `FEED_AD_ROWS` on, `NATIVE_AD` off, `HOUSE_AD` off, `FAILURE_SINK` on.
5. What React Native has, so what the app shows:
   1. Feed: `SellwildFeed`, the native SDK feed (iOS `SellwildFeedView`, Android `SellwildFeedView`). The SDK sets `sw.listing.card` and `sw.feed.ad` on its rows.
   2. Ads: `SellwildBanner` at 320x50 and 300x250, native Prebid Mobile + GAM. No native ad or house ad component: the Ads screen says so.
   3. Listings: `useSellwildListings` with `SellwildListingCard`. Refresh is the hook's `refresh`, which clears the listings cache.
   4. Failure codes: `setFailureContext({ sink })` from `@sellwild/sdk-core` is public. The app records each code and sends the event on to the events queue. So Diagnostics must show `config.fetch.http`. The sink sees what React Native JS and core report, not the native SDKs under the bridge.
6. Ids: `testID`. It is the accessibilityIdentifier on iOS and the resource-id on Android. A `View` around a native view (the feed, the ad slots, the widget) also sets `collapsable={false}`.
7. `rn-ios`:
   1. Build: `npm ci` when stale, core's dist, `pod install` when `Pods/Manifest.lock` differs from `Podfile.lock`, then `xcodebuild -workspace SellwildDemo.xcworkspace -scheme SellwildDemo -configuration Release` for the simulator, `ONLY_ACTIVE_ARCH=YES`. Derived data in `e2e/.cache/rn-ios/`.
   2. Device: the same iPhone as `ios` (`scripts/e2e/lib/ios-sim.sh`).
   3. Time: about 5 minutes warm (299s here: Xcode build 134s, which bundles the JS again every time; flow 70s). The first run took 549s, with `pod install` (hermes-engine, boost and the other pods download).
8. `rn-android`:
   1. Build: `npm ci` when stale, core's dist, the SDK to mavenLocal, then `./gradlew :app:assembleRelease -PreactNativeArchitectures=arm64-v8a` in `samples/demo-app/android`, with 2 Gradle workers. Then `gradlew --stop` for both Gradle versions (8.14.2 for the SDK, 8.6 for the app). The release APK is signed with the template's debug keystore.
   2. The first build downloads Gradle 8.6 and installs Android SDK Platform 34 (the app's `compileSdk`) into the Android SDK. The NDK it names (26.1) is not needed: without it, Gradle packs the native libraries unstripped and says so.
   3. Device: `Pixel_5_API_36`, as for `android` (`scripts/e2e/lib/android-emu.sh`). The APK is 59 MB.
   4. Time: about 3 minutes warm (174s here: SDK publish 15s, app build 13s, boot 63s, flow 55s). The first run took 681s (app build 9m 15s with the downloads).
9. WebViews: Maestro sees inside the Legacy widget's WebView (react-native-webview) on both platforms. A separate probe flow found "View all" and "Buy now" there on iOS and on Android. The flows still check only the container.
10. `scripts/rn/compile-bridge-ios.sh` and `scripts/rn/compile-bridge-android.sh` compile only the native bridge (no app, no device). They take no lock: run them through the lock. The gate's `--full` runs them as `rn-bridge-android` and `rn-bridge-ios`.
11. Seen in the runs, not checked by the flows:
    1. Android: `SellwildListingCard` on the Listings screen shows no photos. The feed's 10 photos are `data:image/avif` URLs, and React Native's Android image pipeline did not draw them. iOS draws them, and the native SDK feed draws them on both.
    2. The 320x50 banner did not fill on either platform. The MREC filled with a Google test ad on both.

## Add an app

1. Write `scripts/e2e/apps/<app>.sh`. Copy `apps/ios.sh`. Set `E2E_APP_ID` and `E2E_FLOWS`. Define `e2e_build`, `e2e_boot`, `e2e_install` and `e2e_shutdown`.
2. For an iOS simulator, use `scripts/e2e/lib/ios-sim.sh`. Put helpers for another device kind in a new `scripts/e2e/lib/<kind>.sh`. `run.sh` sources every `lib/*.sh`.
3. `e2e_shutdown` must shut the device down (`xcrun simctl shutdown all`, `adb emu kill`). Stop Gradle there too (`./gradlew --stop`).
4. Write `e2e/maestro/<app>/<flow>.yaml`. Set `appId`, `env` (`APP_ID` and the flags), then run the common subflows.
5. Add new ids to `contracts/e2e/ids.json` first. `contracts/test/e2e-ids.test.mjs` fails on an unlisted id.
6. Add a section for the app above.
7. The gate's `--e2e` picks the new app up from `run.sh --list` as step `e2e-<app>`. Nothing to edit there.
