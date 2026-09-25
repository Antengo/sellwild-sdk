# Sellwild Sample (React Native)

The React Native sample app. It has the same four tabs as the iOS and Android samples, so one set of Maestro flows (`e2e/maestro/`) covers them all.

## Tabs

1. Feed: `SellwildFeed`, the native feed. Native listing cards with native ads between them. It opens first.
2. Ads: `SellwildBanner` at 320x50 and 300x250 (native Prebid Mobile + GAM). The label under each slot shows its measured size. The React Native SDK has no native ad or house ad component, and the screen says so.
3. Listings: `useSellwildListings`, drawn with `SellwildListingCard`. Refresh clears the listings cache and fetches again.
4. Diagnostics: the SDK version (`SDK_VERSION`), partner and slug, config source (remote or fallback), the listings URL, and the failure codes the SDK sent this launch.

## What it passes to the SDK

1. Partner code `sellwild`, slug `sellwild-sample`. The CDN has no config for that slug (403), so the source is "fallback" and `config.fetch.http` is reported once a launch. That is expected.
2. Listings from `https://cache.sellwild.com/listings-img-data-sm-avif-fandom` (`listingsUrl`).
3. Zones `sellwild-sample-banner` and `sellwild-sample-mrec` when the config has none.
4. The failure codes come from a failure sink: `setFailureContext({ sink })` from `@sellwild/sdk-core`. It records each code, then sends the event on to the SDK's events queue. It sees what React Native JS and core report, not what the native SDKs report.

## How it gets the SDK

1. JS: `metro.config.js` maps `@sellwild/react-native-sdk` to `../../react-native` and `@sellwild/sdk-core` to `../../core`. Core is read from its `dist/` (gitignored): build it first with `npm --prefix ../../core run build` (tsgo).
2. iOS: `ios/Podfile` takes the pods `SellwildSDK` and `SellwildSDK-RN` from this repo.
3. Android: `android/settings.gradle` includes the bridge (`react-native/android`) as `:sellwild-react-native-sdk`. The SDK comes from mavenLocal as `com.sellwild:sdk:1.7.7`: publish it first with `android/gradlew -p ../../android publishReleasePublicationToMavenLocal`.
4. `MainApplication.kt` adds `SellwildSdkPackage` by hand, since the bridge is not autolinked here.

## Commands

Use npm (`package-lock.json`). On the agents' machine, run every native build and device through the native lock.

1. `npm ci`: the packages.
2. `npm run typecheck`: tsgo, with the SDK sources (`tsconfig.json` maps the packages to the repo folders).
3. `npm run lint`: ESLint (`@react-native` config, Prettier).
4. `npm test`: jest. It checks the tab ids and the Diagnostics screen.
5. `bash ../../scripts/e2e/run.sh rn-ios` or `rn-android`: a Release build with the JS bundle inside, on a simulator or emulator, with the Maestro flows. `e2e/README.md` has the details.
6. `bash ../../scripts/rn/compile-bridge-ios.sh` and `compile-bridge-android.sh`: compile only the native bridge.
7. `npm start`, then `npm run ios` or `npm run android`: the usual Metro dev loop (Debug builds that load the JS from Metro). Not run when this sample was last checked; the e2e uses Release builds.

## Ids

1. Each tab and each checked element has a `testID` from `src/sampleIds.ts`. The one list is `contracts/e2e/ids.json`.
2. A `View` around a native view (the feed, the ad slots, the widget) also sets `collapsable={false}`.
3. The SDK feed sets `sw.listing.card` and `sw.feed.ad` on its rows itself.
