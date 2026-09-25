# Flutter sample

The Flutter sample app moved to `samples/flutter-demo` (app "Sellwild Sample", id `com.sellwild.sample.flutter`).

1. It has what the old `main.dart` showed, on current API: `SellwildSDK.configure`, `SellwildBanner`, `SellwildAPIClient.fetchListings` and `clearCache`, `SellwildListingCard`, and the deprecated `SellwildWidget` on its Legacy screen only.
2. The old file said `SellwildBanner` ran a native Prebid Mobile auction into a native GAM view. It does not: every Flutter ad is a WebView. The new app says so on its screens.
3. It builds against the SDK in this repo (a path dependency), so it cannot drift from the API.
4. `bash scripts/e2e/run.sh flutter-ios` and `bash scripts/e2e/run.sh flutter-android` build it and run its Maestro flows.
