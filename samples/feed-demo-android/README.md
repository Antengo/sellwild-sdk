# SellwildFeed Android demo

Minimal standalone Android app that boots `SellwildSDK.configure()` with the
WeatherBug partner code and renders `SellwildFeedView` against the live CDN
config + cache listings.

## Setup

The app expects a built SDK AAR at `app/libs/sellwild-sdk.aar` (gitignored).
Build it from the repo root:

```sh
cd android
./gradlew assembleRelease
cp build/outputs/aar/android-release.aar ../samples/feed-demo-android/app/libs/sellwild-sdk.aar
```

Then:

```sh
cd samples/feed-demo-android
./gradlew :app:installDebug
adb shell am start -n com.sellwild.feeddemo/.MainActivity
```

## What you should see

Header bar (`Marketplace` + `Powered by Sellwild`), then a vertical feed
following the `col1` token schedule injected by `MainActivity` (default
`BLGLGLGLGLG`):

- `B` → 320×50 banner (Google test ad unit fallback)
- `L` → listing card (full-bleed image, title, price, seller line)
- `G` → 300×250 MREC (adaptive-banner test ad unit fallback)

Schedule, theme, listings URL, and zone IDs are all CDN-driven via
`SellwildSDK.configure()`. The demo only injects token overrides so the schedule
is visible without waiting on a CMS publish.
