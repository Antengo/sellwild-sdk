# Android sample

The Android sample app moved to `samples/feed-demo-android` (app "Sellwild Sample", application id `com.sellwild.sample`).

1. It has what the old `SampleActivity.kt` showed, on current API: `SellwildSDK.configure` and `prewarm`, `SellwildFeed`, `SellwildAdView` with its listener and `SellwildAPIClient.fetchListings` and `clearCache`. The WebView widget it once showed is removed (origin/main 9ff579f).
2. It builds against the SDK in this repo (published to mavenLocal), so it cannot drift from the API.
3. `bash scripts/e2e/run.sh android` builds it and runs its Maestro flows.
