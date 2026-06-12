---
name: native-first-mobile
description: |
  Activate for any work on the Sellwild mobile SDKs (iOS, Android, React Native, Flutter)
  involving listings, ad surfaces, the "all-in-one" widget, or partner integrations
  (WeatherBug, Sports Merch, Bargain Hunter, Rtings). Enforces our native-only directive,
  the reproduce-before-fix discipline, and the emulator/sim verification loop we hardened
  through SDK 1.3.0–1.3.4. Use whenever a task touches `SellwildWidgetView`,
  `SellwildWidget`, `SellwildAdView`, `SellwildAdBanner`, `fetchListings`, or
  `useSellwildListings`.
---

# native-first-mobile

The canonical rules for working on Sellwild mobile SDKs. This skill exists because we
spent SDK 1.3.0 → 1.3.4 publishing fixes against a WebView widget that fundamentally
cannot earn the CPMs partner deals are sized against. We are done with that pattern.

## Core directive (do not negotiate)

The WebView widget (`SellwildWidgetView` on iOS/Android, `SellwildWidget` in RN, the
embedded `partner.js`) **WILL NOT PRODUCE THE CPMs NECESSARY FOR THE DEAL. WE NEED
NATIVE.** This is also stated in `AGENTS.md` at the repo root.

Concretely:

- The supported monetization path is **native Prebid Mobile + GAM** via
  `SellwildAdView` / `SellwildAdBanner` (iOS, Android), the RN bindings, and the
  forthcoming Flutter equivalent.
- The supported listings path is **native fetch + native render**:
  - iOS: `SellwildAPIClient.fetchListings(...)`
  - Android: `SellwildAPIClient.fetchListings(...)`
  - React Native: `useSellwildListings(config)`
  - Flutter: (TBD — pattern matches RN hook)
- The best-of-both path is **native listings + native ads interspersed in the same
  feed**, as demonstrated in `samples/demo-app/App.tsx`.
- The WebView widget is **deprecated**. Do not add features, do not write bug-fix
  releases that target it, do not show it as a primary example in docs.

## Reproduce before you fix

We burned SDK 1.3.2, 1.3.3, and 1.3.4 publishing "fixes" that did not reproduce the
reported bug first. The bug in `onListingTapped` was never `window.open()` — the
widget renders `<a target="_blank">` anchors that the WebView follows inline. We only
caught it after building a minimal native test app against the published Maven AAR.

Before any mobile SDK change:

1. **Reproduce the bug** on the same surface the partner uses:
   - iOS partner issues → boot an iOS simulator (`xcrun simctl list devices booted`)
     and run the relevant sample target.
   - Android partner issues → boot the `Pixel_Fold_API_36` AVD (or another configured
     AVD) and install via `adb`.
   - React Native partner issues → run `samples/demo-app` against either simulator.
2. **Confirm the actual code path.** Read the relevant `partner.js` flow, the
   `WebViewClient` / `WKUIDelegate` / RN `WebView` glue, and the JS bridge. Don't
   guess which interception layer is in play.
3. **Add a log line that proves you reproduced.** If you cannot show the bad behavior
   in a console, you have not reproduced it.

Only then propose a fix.

## Emulator / simulator verification loop

The loop that works for this repo:

### Android (native or RN-Android)

```bash
# 1. Boot the emulator if not already running.
~/Library/Android/sdk/emulator/emulator -list-avds
~/Library/Android/sdk/emulator/emulator -avd Pixel_Fold_API_36 &

# 2. Wait for boot and confirm device is online.
~/Library/Android/sdk/platform-tools/adb wait-for-device
~/Library/Android/sdk/platform-tools/adb shell getprop sys.boot_completed   # → 1

# 3. Build + publish locally so test app pulls the change.
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ./gradlew clean test publishReleasePublicationToMavenLocal

# 4. Install and run a minimal native test app that depends on com.sellwild:sdk
#    from `mavenLocal()`. Don't test inside the RN demo — RN ships its own WebView
#    component and will mask native bugs.
cd /tmp/widgettest && ./gradlew installDebug
~/Library/Android/sdk/platform-tools/adb shell am start -n com.test.widgettest/.MainActivity

# 5. Watch logs filtered to the SDK.
~/Library/Android/sdk/platform-tools/adb logcat -c
~/Library/Android/sdk/platform-tools/adb logcat | grep -E "Sellwild|LISTING|widgettest"
```

Notes that bit us:
- Gradle 8.14.2 does **not** run on Java 25. Always set `JAVA_HOME` to Java 17 for SDK
  builds. SDK 1.3.4 reverted to Kotlin 2.1.20 + Gradle 8.14.2 to keep partners on
  Java 17/21 unblocked. Do not silently upgrade Kotlin or Gradle.
- The RN demo (`samples/demo-app`) uses RN's `WebView` component, not the native
  `SellwildWidgetView`. It is **not** a proxy for native widget testing.

### iOS

```bash
# 1. Boot a sim.
xcrun simctl list devices available | grep -E "iPhone (15|16|17)"
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator

# 2. Build the iOS sample or demo against the local pod.
cd samples/ios && pod install
xcodebuild -workspace SellwildSample.xcworkspace -scheme SellwildSample \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build

# 3. Install and launch.
xcrun simctl install booted ./build/.../SellwildSample.app
xcrun simctl launch --console-pty booted com.sellwild.sample
```

### React Native

```bash
cd samples/demo-app
npm install
cd ios && pod install && cd ..
npx react-native run-ios --simulator="iPhone 17 Pro"
# or
npx react-native run-android
```

## Version + publish discipline

Past mistakes to not repeat:

- **Do not** push to `main` and publish to Maven/CocoaPods/npm in the same breath
  without running tests first.
- **Do not** publish a CocoaPods release before pushing the matching git tag — we hit
  this on 1.3.3.
- **Always** create the git tag (`vX.Y.Z`) before any platform publish.
- **Always** bump versions in lock-step across iOS (`SellwildSDK.podspec`), Android
  (`android/build.gradle.kts`), and React Native (`react-native/package.json`).
- **Always** verify the published artifact is reachable before announcing:
  - Maven: `curl -I https://maven.sellwild.com/releases/com/sellwild/sdk/X.Y.Z/sdk-X.Y.Z.aar`
  - CocoaPods: `pod trunk info SellwildSDK`
  - npm: `npm view @sellwild/react-native-sdk@X.Y.Z`

## Goal-mode etiquette

When invoked inside a goal (`/goal sellwild-native-audit`,
`/goal mobile-all-in-one-widget`, or any future native goal):

- Append every meaningful action to the goal's `history.md`. The judge agent reads it.
- Use the feature template at `.mastracode/goals/sellwild-native/templates/feature.md`
  for any newly documented or rewritten feature.
- Do not start fixing things mid-audit. The audit goal produces docs; the build goal
  consumes them.
- Stop and write a `handoff.md` entry whenever you hit something that requires a human
  decision (deal terms, partner-specific config, deletion of public API surface).

## Symbols cheat sheet

| Surface | iOS | Android | React Native | Status |
|---|---|---|---|---|
| Native banner | `SellwildAdView` / `SellwildAdBanner` | `SellwildAdView` | `SellwildBanner` | **supported** |
| Native listings fetch | `SellwildAPIClient.fetchListings` | `SellwildAPIClient.fetchListings` | `useSellwildListings` | **supported** |
| Native listing card | partner-rendered | partner-rendered | `SellwildListingCard` | **supported** |
| WebView widget | `SellwildWidgetView` | `SellwildWidgetView` | `SellwildWidget` | **deprecated** |

If in doubt: native.
