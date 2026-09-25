# iOS sample

The iOS sample app moved to `samples/feed-demo-ios` (project `SellwildSample.xcodeproj`).

1. It has what the old `SampleApp.swift` showed, on current API: `SellwildSDK.configure`, `SellwildFeed`, `SellwildAdBanner` and `SellwildAPIClient.fetchListings` and `clearCache`. The WebView widget it once showed is removed (origin/main 9ff579f).
2. It builds against the SDK in this repo, so it cannot drift from the API.
3. `bash scripts/e2e/run.sh ios` builds it and runs its Maestro flows.
