# Sellwild Sample (Android)

The native Android sample app (Jetpack Compose). It is also what the Android e2e flows drive (`e2e/README.md`).

## Screens

1. Feed: `SellwildFeed` (Compose). Native listing cards with native ads between them. It opens first.
2. Ads: `SellwildAdView` at 320x50 and 300x250, and `SellwildNativeAdView`. Each slot shows its measured size and the ad's last status. Test ads may not fill.
3. Listings: `SellwildAPIClient.fetchListings`, drawn by the app. Refresh calls `clearCache()` and fetches again.
4. Diagnostics: SDK version, partner code and slug, config source (remote or fallback), listings URL, and `SellwildFailures.context`. Failure codes show "not available on this platform": Android has no public failure sink.

## Config

1. `SellwildSDK.configure(partnerCode = "sellwild", slug = "sellwild-sample")` runs at launch. Then `SellwildSDK.prewarm` starts the ad stack.
2. There is no CDN config for that slug (it answers 403). So the SDK keeps its built-in config and Google's test ad units. That is expected.
3. The app sets `listingsUrl` to `https://cache.sellwild.com/listings-img-data-sm-avif-fandom`, plus COL1 and zone ids when the CDN has none.
4. Everything is in `app/src/main/java/com/sellwild/sample/SampleModel.kt`.
5. Debug builds call `WebView.setWebContentsDebuggingEnabled(true)`. Release builds do not.

## Build and run

1. Use a JDK 17. Set `ANDROID_HOME` (or write `local.properties`).
2. Publish the SDK in this repo to mavenLocal:

   ```sh
   cd android && ./gradlew publishReleasePublicationToMavenLocal
   ```

3. Build and install the sample:

   ```sh
   cd samples/feed-demo-android && ./gradlew :app:installDebug
   adb shell am start -n com.sellwild.sample/.MainActivity
   ```

4. Or build, install and test it on an emulator in one step: `bash scripts/e2e/run.sh android`.

## Dependencies

1. `com.sellwild:sdk` comes only from mavenLocal. Its version is read from `android/build.gradle.kts`, so the sample always gets the build you just published.
2. The SDK's POM brings the rest: the Prebid Mobile fork `com.sellwild:PrebidMobile-*:3.3.2-sw4` and `com.sellwild:omsdk-android` (both from maven.sellwild.com, origin a1bed54 and 01d4d8e) and Google Mobile Ads.
3. Compose 1.6.8, the version the SDK's `SellwildFeed` builds against.

## Element ids

1. `app/src/main/java/com/sellwild/sample/SampleIds.kt` holds the ids the flows use. They are Compose test tags.
2. `SampleApp` turns on `testTagsAsResourceId`, so UI Automator and Maestro read each tag as a resource-id.
3. The one list is `contracts/e2e/ids.json`. Add an id there first.
4. The SDK feed sets `sw.listing.card` and `sw.feed.ad` on its own rows.

## Lint

```sh
cd samples/feed-demo-android && ./gradlew detektDebug lintDebug
```

1. detekt runs the SDK's rules (`android/config/detekt/detekt.yml`), plus two Compose changes in `app/detekt.yml`.
2. Android Lint fails on any warning, as in the SDK.
