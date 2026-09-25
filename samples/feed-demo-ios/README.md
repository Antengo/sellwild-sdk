# Sellwild Sample (iOS)

The native iOS sample app. It is also what the iOS e2e flows drive (`e2e/README.md`).

## Screens

1. Feed: `SellwildFeed`. Native listing cards with native ads between them. It opens first.
2. Ads: `SellwildAdBanner` at 320x50 and 300x250, and `SellwildNativeAdView`. Each slot shows its measured size. Test ads may not fill.
3. Listings: `SellwildAPIClient.shared.fetchListings`, drawn by the app. Refresh calls `clearCache()` and fetches again.
4. Diagnostics: SDK version, partner code and slug, config source (remote or fallback), listings URL, and `SellwildFailures.context`. Failure codes show "not available on this platform": iOS has no public failure sink.

## Config

1. `SellwildSDK.configure(partnerCode: "sellwild", slug: "sellwild-sample")` runs at launch.
2. There is no CDN config for that slug (it answers 403). So the SDK keeps its built-in config and Google's test ad units. That is expected.
3. The app sets `listingsUrl` to `https://cache.sellwild.com/listings-img-data-sm-avif-fandom`, plus COL1 and zone ids when the CDN has none.
4. Everything is in `SellwildSample/SampleModel.swift`.

## Build and run

1. The SDK comes from the repo's root `Package.swift`. No pod install.
2. Regenerate the project after editing `project.yml`:

   ```sh
   cd samples/feed-demo-ios && xcodegen generate
   ```

3. Build from the repo root:

   ```sh
   xcodebuild -project samples/feed-demo-ios/SellwildSample.xcodeproj -scheme SellwildSample \
     -destination "platform=iOS Simulator,name=iPhone 17" build
   ```

4. Or build, install and test it on a simulator in one step: `bash scripts/e2e/run.sh ios`.

## Element ids

1. `SellwildSample/SampleIDs.swift` holds the ids the flows use.
2. The one list is `contracts/e2e/ids.json`. Add an id there first.
3. The SDK feed sets `sw.listing.card` and `sw.feed.ad` on its own rows.

## Lint

```sh
tools/bin/swiftlint lint --strict --config .swiftlint.yml samples/feed-demo-ios/SellwildSample/*.swift
```

Pass the files, not the folder: `.swiftlint.yml` excludes `samples/`, and SwiftLint then lints the configured paths instead.
