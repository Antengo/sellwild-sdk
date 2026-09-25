# Sellwild Sample (Flutter)

The Flutter sample app for the Sellwild SDK. It builds against the SDK in `../../flutter` (a path dependency), so it cannot drift from the API.

## Run it

1. `cd samples/flutter-demo`
2. `flutter pub get`
3. `flutter run` (an iOS Simulator or an Android emulator)

The e2e flows run it with `bash scripts/e2e/run.sh flutter-ios` or `bash scripts/e2e/run.sh flutter-android` (see `e2e/README.md`).

## What it shows

1. It calls `SellwildSDK.configure(partnerCode: 'sellwild', slug: 'sellwild-sample')`.
   1. The CDN has no config for that slug (403). So the SDK keeps its built-in config and reports `config.fetch.http`. That is expected.
   2. The `overrides` set the listings URL, the app id, `debug`, and Google's GPT test ad unit when the CDN config has no GAM tag.
2. Five tabs: Feed, Ads, Listings, Diagnostics, Legacy.
   1. Feed: `fetchListings` drawn with `SellwildListingCard`, two cards a row, and an ad row after every four cards. The Flutter SDK has no feed component, so the app builds it.
   2. Ads: `SellwildBanner` at 320x50 and 300x250, each with its measured size.
   3. Listings: `fetchListings` drawn by the app. Refresh calls `clearCache` and fetches again.
   4. Diagnostics: SDK version, partner and slug, config source, listings URL, and the failure codes the SDK sent this launch.
   5. Legacy: the deprecated `SellwildWidget`, titled "Legacy WebView widget (deprecated)".
3. Every e2e id (`contracts/e2e/ids.json`) is a `Semantics(identifier:)`.

## What the Flutter SDK does not have

1. No native ads. `SellwildBanner` runs Google Publisher Tag in a WebView. There is no Prebid Mobile or GAM SDK, so the app needs no `GADApplicationIdentifier` (iOS) and no `com.google.android.gms.ads.APPLICATION_ID` (Android).
2. No native ad view and no house ad view.
3. No feed component.
4. It does have a public failure sink: `SellwildFailures.setContext(sink: ...)`. The app records each code, then sends the event on through `SellwildAPIClient.instance.sendEvent`, as the SDK does without a sink.

## Checks

1. `flutter analyze --fatal-infos --fatal-warnings`. `analysis_options.yaml` includes the SDK's own rules.
2. `flutter test`: the pure helpers, and the ids on the Diagnostics, Listings and tab bar.

## Ids

1. Bundle id and application id: `com.sellwild.sample.flutter` on both platforms.
2. Display name: "Sellwild Sample".
