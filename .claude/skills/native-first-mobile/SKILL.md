---
name: native-first-mobile
description: |
  Activate for any work on the Sellwild mobile SDKs (iOS, Android, React Native)
  involving listings, ad surfaces, the "all-in-one" widget, or partner integrations
  (WeatherBug, Sports Merch, Bargain Hunter, Rtings). Enforces our native-only directive,
  the reproduce-before-fix discipline, and the emulator/sim verification loop we hardened
  through SDK 1.3.0–1.3.4. Use whenever a task touches `SellwildAdView`,
  `SellwildAdBanner`, `SellwildFeedView`, `SellwildFeed`, `SellwildNativeAdView`,
  `fetchListings`, or `useSellwildListings` — or anyone asks to bring back the
  removed WebView widget.
---

# native-first-mobile

The canonical rules for working on Sellwild mobile SDKs. This skill exists because we
spent SDK 1.3.0 → 1.3.4 publishing fixes against a WebView widget that fundamentally
cannot earn the CPMs partner deals are sized against. We are done with that pattern.

## Core directive (do not negotiate)

The WebView widget (`SellwildWidgetView` on iOS/Android, `SellwildWidget` in RN, the
embedded `partner.js`) **WILL NOT PRODUCE THE CPMs NECESSARY FOR THE DEAL. WE NEED
NATIVE.** It has been **removed** from iOS, Android, and React Native. This is also
stated in `AGENTS.md` at the repo root.

Concretely:

- The supported monetization path is **native Prebid Mobile + GAM** via
  `SellwildAdView` / `SellwildAdBanner` (iOS, Android) and the RN bindings.
- The supported listings path is **native fetch + native render**:
  - iOS: `SellwildAPIClient.fetchListings(...)`
  - Android: `SellwildAPIClient.fetchListings(...)`
  - React Native: `useSellwildListings(config)`
- The best-of-both path is **native listings + native ads interspersed in the same
  feed**: `SellwildFeedView` (iOS/Android), SwiftUI `SellwildFeed`, RN `SellwildFeed`,
  as the Feed tab of each sample app shows: `samples/feed-demo-ios`,
  `samples/feed-demo-android`, `samples/demo-app` (React Native, `src/FeedScreen.tsx`).
- The WebView widget is **removed**. Do not reintroduce a WebView ad or listings
  surface, and do not document it as an option.

## Reproduce before you fix

We burned SDK 1.3.2, 1.3.3, and 1.3.4 publishing "fixes" that did not reproduce the
reported bug first. The bug in `onListingTapped` was never `window.open()` — the
widget renders `<a target="_blank">` anchors that the WebView follows inline. We only
caught it after building a minimal native test app against the published Maven AAR.

Before any mobile SDK change:

1. **Reproduce the bug** on the same surface the partner uses:
   - iOS partner issues → boot an iOS simulator (`xcrun simctl list devices booted`)
     and run the relevant sample target.
   - Android partner issues → boot the `Pixel_5_API_36` AVD (or another configured
     AVD) and install via `adb`. Not `Pixel_5_API_32`: its data partition is full,
     and the sample APKs do not install there.
   - React Native partner issues → run `samples/demo-app` against either simulator.
2. **Confirm the actual code path.** Read the native view, its delegate / listener,
   and (for RN) the view-manager bridge. Don't guess which layer is in play.
3. **Add a log line that proves you reproduced.** If you cannot show the bad behavior
   in a console, you have not reproduced it.

Only then propose a fix.

## Emulator / simulator verification loop

The loop that works for this repo. Each sample app ("Sellwild Sample", four tabs:
Feed, Ads, Listings, Diagnostics) has one command that builds it, boots the
device, installs, runs its Maestro flows and shuts the device down
(`e2e/README.md`):

```bash
bash scripts/e2e/run.sh ios              # samples/feed-demo-ios
bash scripts/e2e/run.sh android          # samples/feed-demo-android
bash scripts/e2e/run.sh rn-ios           # samples/demo-app on the simulator
bash scripts/e2e/run.sh rn-android       # samples/demo-app on the emulator
```

Screenshots and logs land in `e2e/artifacts/<app>/`. One native build or booted
device at a time: when `SELLWILD_NATIVE_LOCK` names a lock script, `run.sh` runs the
whole session inside one call of it. The steps by hand:

### Android (native or RN-Android)

```bash
# 1. Boot the emulator if not already running. API 36 needs at least 2560 MB of RAM.
~/Library/Android/sdk/emulator/emulator -list-avds
~/Library/Android/sdk/emulator/emulator -avd Pixel_5_API_36 -memory 2560 \
  -no-snapshot-save -no-audio -no-boot-anim &

# 2. Wait for boot and confirm device is online.
~/Library/Android/sdk/platform-tools/adb wait-for-device
~/Library/Android/sdk/platform-tools/adb shell getprop sys.boot_completed   # → 1

# 3. Build + publish locally so test app pulls the change.
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home
(cd android && ./gradlew clean test publishReleasePublicationToMavenLocal)

# 4. Install and run the native sample app, which depends on com.sellwild:sdk
#    from `mavenLocal()` only (samples/feed-demo-android). Don't test inside the
#    RN demo — the RN bridge layer will mask native bugs.
(cd samples/feed-demo-android && ./gradlew :app:assembleDebug)
~/Library/Android/sdk/platform-tools/adb install -r -t \
  samples/feed-demo-android/app/build/outputs/apk/debug/app-debug.apk
~/Library/Android/sdk/platform-tools/adb shell am start -n com.sellwild.sample/.MainActivity

# 5. Watch logs filtered to the SDK.
~/Library/Android/sdk/platform-tools/adb logcat -c
~/Library/Android/sdk/platform-tools/adb logcat | grep -E "Sellwild|LISTING"
```

Notes that bit us:
- Gradle 8.14.2 does **not** run on Java 25. Always set `JAVA_HOME` to Java 17 for SDK
  builds. SDK 1.3.4 reverted to Kotlin 2.1.20 + Gradle 8.14.2 to keep partners on
  Java 17/21 unblocked. Do not silently upgrade Kotlin or Gradle.
- The RN demo (`samples/demo-app`) runs through the RN bridge. It is **not** a proxy
  for native SDK testing.

### iOS

```bash
# 1. Boot a sim (several runtimes may have an "iPhone 17": boot one by UDID).
xcrun simctl list devices available | grep -E "iPhone (15|16|17)"
xcrun simctl boot <UDID>
open -a Simulator

# 2. Build the iOS sample against the SDK as checked out. It is an xcodegen
#    project that takes the SDK from the root Package.swift (SwiftPM, no pods).
xcodebuild -project samples/feed-demo-ios/SellwildSample.xcodeproj -scheme SellwildSample \
  -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath e2e/.cache/ios/DerivedData build

# 3. Install and launch.
xcrun simctl install booted e2e/.cache/ios/DerivedData/Build/Products/Debug-iphonesimulator/SellwildSample.app
xcrun simctl launch --console-pty booted com.sellwild.sample
```

### React Native

The app is `samples/demo-app` (RN 0.74, npm, bundle/application id
`com.sellwild.sample.rn`). Metro takes the JS SDK from `react-native/` and `core/`;
core is read from its gitignored `dist/`, so build it first.

```bash
npm --prefix samples/demo-app ci
npm --prefix core run build                     # core/dist, with tsgo
(cd samples/demo-app/ios && pod install)        # local pods SellwildSDK + SellwildSDK-RN
(cd android && ./gradlew publishReleasePublicationToMavenLocal)   # com.sellwild:sdk for the bridge

# Compile only the native bridge (react-native/ios, react-native/android):
bash scripts/rn/compile-bridge-ios.sh
bash scripts/rn/compile-bridge-android.sh

# A Release build with the JS bundle inside, on a device, with the Maestro flows:
bash scripts/e2e/run.sh rn-ios
bash scripts/e2e/run.sh rn-android
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
| All-in-one native feed | `SellwildFeedView` / `SellwildFeed` | `SellwildFeedView` | `SellwildFeed` | **supported** |
| Native ad view | `SellwildNativeAdView` | `SellwildNativeAdView` | — | **supported** |
| WebView widget | `SellwildWidgetView` | `SellwildWidgetView` | `SellwildWidget` | **removed** |

If in doubt: native.
