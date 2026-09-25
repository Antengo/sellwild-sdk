# iOS sample

The iOS sample app moved to `samples/feed-demo-ios` (project `SellwildSample.xcodeproj`).

1. It has what the old `SampleApp.swift` showed, on current API: `SellwildSDK.configure`, `SellwildFeed`, `SellwildAdBanner`, `SellwildAPIClient.fetchListings` and `clearCache`, and the deprecated `SellwildWidgetView` on its Legacy screen only.
2. It builds against the SDK in this repo, so it cannot drift from the API.
3. `bash scripts/e2e/run.sh ios` builds it and runs its Maestro flows.
