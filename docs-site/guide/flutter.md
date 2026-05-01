# Sellwild SDK -- Flutter Integration Guide

This guide covers everything needed to integrate the Sellwild SDK into a Flutter application, from installation through production deployment.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Platform Configuration](#platform-configuration)
4. [Quick Start](#quick-start)
5. [Widgets Reference](#widgets-reference)
6. [Remote Config](#remote-config)
7. [Prebid Server (S2S) Configuration](#prebid-server-s2s-configuration)
8. [Native Listing Fetch with SellwildAPIClient](#native-listing-fetch-with-sellwildapiclient)
9. [GDPR and Consent Management](#gdpr-and-consent-management)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Minimum Version |
|-------------|-----------------|
| Flutter     | 3.10.0          |
| Dart SDK    | 3.0.0           |
| iOS         | 13.0+           |
| Android     | API 21+ (minSdk 21) |
| Xcode       | 14.0+           |
| Android Studio / Gradle | AGP 7.0+ |

Verify your environment before proceeding:

```bash
flutter doctor -v
dart --version
```

---

## Installation

Add the Sellwild SDK to your `pubspec.yaml`:

```yaml
dependencies:
  sellwild_sdk: ^1.2.0
```

The SDK pulls in two transitive dependencies automatically:

| Dependency         | Version | Purpose                       |
|--------------------|---------|-------------------------------|
| `webview_flutter`  | ^4.4.0  | WebView rendering for widgets |
| `http`             | ^1.1.0  | REST API calls for listings   |

Run the install:

```bash
flutter pub get
```

Import the SDK in your Dart code:

```dart
import 'package:sellwild_sdk/sellwild_sdk.dart';
```

---

## Platform Configuration

### iOS -- Info.plist

The SDK loads ad content in a WebView. iOS requires the following entries in `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoadsInWebContent</key>
  <true/>
</dict>
```

This permits the WebView to load ad creatives and tracking pixels served over HTTP. It does not affect your app's own network calls.

If your app requests IDFA for attribution or frequency capping, also add:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier is used to deliver relevant ads and measure campaign performance.</string>
```

For SKAdNetwork support, add the relevant network identifiers provided by your SSPs:

```xml
<key>SKAdNetworkItems</key>
<array>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cstr6suwn9.skadnetwork</string>
  </dict>
  <!-- Add identifiers for each SSP -->
</array>
```

### Android -- AndroidManifest.xml

Add the `INTERNET` permission (usually present by default) and WebView configuration to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:usesCleartextTraffic="false"
        ...>

        <!-- Required for multi-process WebView safety on API 28+ -->
        <meta-data
            android:name="android.webkit.WebView.MetricOptOut"
            android:value="true" />

        <activity ...>
            <!-- existing activity config -->
        </activity>
    </application>
</manifest>
```

If your app targets API 28+ and uses multiple processes, call `WebView.setDataDirectorySuffix()` in your `Application` subclass to avoid multi-process crashes. See the [Android WebView multi-process documentation](https://developer.android.com/reference/android/webkit/WebView#setDataDirectorySuffix(java.lang.String)) for details.

### Android -- Minimum SDK

Ensure your `android/app/build.gradle` sets a minimum SDK of 21 or higher:

```groovy
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

---

## Quick Start

A minimal integration requires two values: your partner code and your listings API URL.

```dart
import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

class MarketplaceScreen extends StatelessWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = SellwildConfig(
      partnerCode: 'weatherbug',
      listingsUrl: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
      appBundleId: 'com.aws.android',
      appStoreUrl: 'https://play.google.com/store/apps/details?id=com.aws.android',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Marketplace')),
      body: SellwildWidget(
        config: config,
        onListingTap: (listing) {
          debugPrint('Tapped listing: ${listing.title} -- ${listing.url}');
        },
        onAdImpression: (zoneId) {
          debugPrint('Ad impression in zone: $zoneId');
        },
        onError: (error) {
          debugPrint('Widget error: $error');
        },
      ),
    );
  }
}
```

**Important:** Always set `appBundleId` and `appStoreUrl`. Without these fields, Prebid.js classifies bid requests as web traffic (`ortb2.site`) instead of in-app traffic (`ortb2.app`). DSPs that segment app and web inventory will not bid, and app-ads.txt enforcement is bypassed.

---

## Widgets Reference

### SellwildWidget

The primary widget. Renders the full Sellwild marketplace experience -- listing carousel, ad placements, and header bidding -- inside a WebView.

```dart
SellwildWidget(
  config: config,
  onListingTap: (SellwildListing listing) {
    // User tapped a listing. Navigate to detail screen or open URL.
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ListingDetailScreen(listing: listing),
    ));
  },
  onAdImpression: (String zoneId) {
    // Track ad impression in your analytics.
    analytics.logEvent('ad_impression', {'zone_id': zoneId});
  },
  onLoad: () {
    // Widget finished loading. Hide any external loading indicators.
  },
  onError: (Object error) {
    // Log or report errors.
    crashlytics.recordError(error);
  },
)
```

**Constructor parameters:**

| Parameter        | Type                              | Required | Description                                      |
|------------------|-----------------------------------|----------|--------------------------------------------------|
| `config`         | `SellwildConfig`                  | Yes      | SDK configuration object                         |
| `onListingTap`   | `void Function(SellwildListing)?` | No       | Called when the user taps a listing               |
| `onAdImpression` | `void Function(String)?`          | No       | Called on ad impression with the zone ID          |
| `onLoad`         | `void Function()?`                | No       | Called when the widget finishes loading           |
| `onError`        | `void Function(Object)?`          | No       | Called on WebView or widget errors                |

**Layout considerations:** `SellwildWidget` expands to fill its parent. Wrap it in a `SizedBox`, `Expanded`, or `Flexible` to control its dimensions:

```dart
SizedBox(
  height: 400,
  child: SellwildWidget(config: config),
)
```

### SellwildBanner

A standalone banner ad unit. Use this for ad placements outside the main widget, such as between content sections or in a sticky footer.

```dart
SellwildBanner(
  config: config,
  adSize: SellwildAdSize.banner320x50,
  zoneId: '12345',
  onImpression: () {
    analytics.logEvent('banner_impression');
  },
  onClick: () {
    analytics.logEvent('banner_click');
  },
  onError: (error) {
    debugPrint('Banner error: $error');
  },
)
```

**Constructor parameters:**

| Parameter      | Type                    | Required | Description                       |
|----------------|-------------------------|----------|-----------------------------------|
| `config`       | `SellwildConfig`        | Yes      | SDK configuration object          |
| `adSize`       | `SellwildAdSize`        | Yes      | IAB standard ad dimensions        |
| `zoneId`       | `String?`               | No       | Sellwild ad zone identifier       |
| `onImpression` | `void Function()?`      | No       | Called when the ad renders         |
| `onClick`      | `void Function()?`      | No       | Called when the user taps the ad   |
| `onError`      | `void Function(Object)?`| No       | Called on load errors              |

**Supported ad sizes (`SellwildAdSize`):**

| Enum Value             | Dimensions | IAB Name          |
|------------------------|------------|-------------------|
| `banner320x50`         | 320 x 50   | Mobile Banner     |
| `mrec300x250`          | 300 x 250  | Medium Rectangle  |
| `leaderboard728x90`    | 728 x 90   | Leaderboard       |
| `halfPage300x600`      | 300 x 600  | Half Page         |
| `wideSkyscraper160x600`| 160 x 600  | Wide Skyscraper   |

**Google Ad Manager integration:** If you use GAM, pass `gamTag` in `SellwildConfig` instead of `zoneId`:

```dart
final config = SellwildConfig(
  partnerCode: 'weatherbug',
  listingsUrl: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
  gamTag: '/12345678/weatherbug_mobile_banner',
);

SellwildBanner(
  config: config,
  adSize: SellwildAdSize.mrec300x250,
)
```

### SellwildListingCard

A native Flutter widget for rendering a single listing. Use this when building custom listing layouts outside the WebView widget, such as a grid or list backed by the `SellwildAPIClient`.

```dart
SellwildListingCard(
  listing: listing,
  config: config,
  onTap: (listing) {
    Navigator.pushNamed(context, '/listing/${listing.id}');
  },
)
```

**Constructor parameters:**

| Parameter | Type                              | Required | Description                          |
|-----------|-----------------------------------|----------|--------------------------------------|
| `listing` | `SellwildListing`                 | Yes      | The listing data to render           |
| `config`  | `SellwildConfig`                  | Yes      | Used for styling (colors, font size) |
| `onTap`   | `void Function(SellwildListing)?` | No       | Called when the card is tapped        |

The card renders at a fixed width of 160px with an image, price badge, and title. Customize colors through `SellwildConfig`:

```dart
final config = SellwildConfig(
  partnerCode: 'weatherbug',
  listingsUrl: '...',
  priceColor: '#FF5722',       // Price badge background
  priceFontColor: '#FFFFFF',   // Price badge text
  fontSize: 14,                // Title font size
);
```

**Building a custom listing grid:**

```dart
class ListingGrid extends StatefulWidget {
  final SellwildConfig config;
  const ListingGrid({super.key, required this.config});

  @override
  State<ListingGrid> createState() => _ListingGridState();
}

class _ListingGridState extends State<ListingGrid> {
  List<SellwildListing> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    try {
      final response = await SellwildAPIClient.instance
          .fetchListings(widget.config);
      setState(() {
        _listings = response.listings;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Failed to load listings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      padding: const EdgeInsets.all(16),
      itemCount: _listings.length,
      itemBuilder: (context, index) => SellwildListingCard(
        listing: _listings[index],
        config: widget.config,
        onTap: (listing) {
          // Handle listing tap
        },
      ),
    );
  }
}
```

---

## Remote Config (the first-class path)

`SellwildSDK.configure(partnerCode:, slug:)` is the recommended way to integrate the SDK. It fetches a JSON document from the Sellwild CDN at app launch and returns a fully-built `SellwildConfig` — listings URL, ad zones, refresh intervals, app identity, waterfall partners, compliance flags, and more — so you can change everything without an app update.

```dart
import 'package:sellwild_sdk/sellwild_sdk.dart';

final config = await SellwildSDK.configure(
  partnerCode: 'weatherbug',
  slug: 'weatherbug-main',
);
// Hand `config` to your SellwildWidget / SellwildBanner.
```

The CDN URL is `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`. Your Sellwild contact provisions the `slug` in the CMS.

**Failure handling.** On any network error, timeout, or 404 the call falls back to a `SellwildConfig(partnerCode: ...)` with deterministic defaults. The `listingsUrl` derives from `partnerCode`, so ads still render even with the CDN offline. Remote config is **additive, never blocking**.

See [Configuration → Remote Config](./configuration#remote-config) for the full CDN field reference.

---

## Prebid Server (S2S) Configuration

By default, the SDK runs Prebid.js client-side inside the WebView. For higher fill rates and to bypass WebView cookie limitations, route header bidding through Prebid Server using the `prebidServer` field.

```dart
final config = SellwildConfig(
  partnerCode: 'weatherbug',
  listingsUrl: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
  appBundleId: 'com.aws.android',
  appStoreUrl: 'https://play.google.com/store/apps/details?id=com.aws.android',
  prebidServer: PrebidServerConfig(
    accountId: 'weatherbug',
    endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
    bidders: ['appnexus', 'pubmatic', 'ix', 'rubicon', 'openx'],
    timeout: 1500,
  ),
);
```

**`PrebidServerConfig` fields:**

| Field          | Type           | Required | Default | Description                                        |
|----------------|----------------|----------|---------|----------------------------------------------------|
| `accountId`    | `String`       | Yes      | --      | Your Prebid Server account ID                      |
| `endpoint`     | `String`       | Yes      | --      | Full URL to the auction endpoint                   |
| `bidders`      | `List<String>` | Yes      | --      | Bidder codes to route server-side                  |
| `timeout`      | `int`          | No       | 1500    | S2S auction timeout in milliseconds                |
| `syncEndpoint` | `String?`      | No       | null    | Cookie sync endpoint (derived from endpoint if omitted) |

When `prebidServer` is set, the SDK automatically injects the `s2sConfig` block into Prebid.js before the auction runs. No additional JavaScript configuration is needed.

For a complete Prebid Server configuration reference, see the [Prebid Server Configuration Guide](./prebid-server.md).

---

## Native Listing Fetch with SellwildAPIClient

`SellwildAPIClient` is a singleton HTTP client for fetching listing data directly, without the WebView. Use it when you need listing data for native UI components like `SellwildListingCard` or your own custom widgets.

### Basic Usage

```dart
final client = SellwildAPIClient.instance;

final response = await client.fetchListings(config);
for (final listing in response.listings) {
  print('${listing.title} -- ${listing.displayPrice}');
}
```

### Response Structure

`fetchListings` returns a `SellwildListingsResponse`:

| Field                   | Type                     | Description                                |
|-------------------------|--------------------------|--------------------------------------------|
| `listings`              | `List<SellwildListing>`  | The listing objects                        |
| `config`                | `Map<String, dynamic>`   | Server-side widget configuration overrides |
| `widgetCacheVersionId`  | `String?`                | Cache version for conditional refresh      |

### SellwildListing Fields

| Field          | Type                  | Description                                     |
|----------------|-----------------------|-------------------------------------------------|
| `id`           | `String`              | Unique listing identifier                       |
| `status`       | `String`              | Listing status (e.g., `active`)                 |
| `title`        | `String`              | Listing title                                   |
| `text`         | `String?`             | Description body text                           |
| `url`          | `String?`             | Canonical URL for the listing                   |
| `categoryId`   | `String?`             | Category identifier                             |
| `currency`     | `String?`             | ISO 4217 currency code (USD, EUR, GBP, etc.)    |
| `price`        | `String?`             | Price as a string                                |
| `strikePrice`  | `String?`             | Original price before discount                  |
| `hasPhoto`     | `bool`                | Whether the listing has at least one photo       |
| `photos`       | `List<SellwildPhoto>` | Photo objects with `url` and `thumbUrl`          |
| `createdDate`  | `String?`             | ISO 8601 creation date                           |
| `shippable`    | `String?`             | Shipping availability flag                       |
| `dataSourceId` | `String?`             | Source identifier for multi-feed integrations    |
| `user`         | `SellwildUser?`       | Seller information                               |
| `distance`     | `double?`             | Distance from search origin (when geo-sorted)    |

**Computed properties:**

- `listing.displayPrice` -- returns the formatted price string, or `null` if the price is zero or unparseable.
- `listing.primaryPhoto` -- returns the first `SellwildPhoto`, or `null` if no photos exist.

### Caching

`fetchListings` caches responses by URL. Subsequent calls with the same `listingsUrl` return the cached result without a network request. To force a refresh:

```dart
SellwildAPIClient.instance.clearCache();
final fresh = await SellwildAPIClient.instance.fetchListings(config);
```

### Lifecycle

The HTTP client is created once and persists for the lifetime of the app. In test environments, call `dispose()` to close the client and release resources:

```dart
// In test tearDown:
SellwildAPIClient.instance.dispose();
```

### Error Handling

Network and parsing errors throw `SellwildException`:

```dart
try {
  final response = await SellwildAPIClient.instance.fetchListings(config);
} on SellwildException catch (e) {
  debugPrint('Sellwild API error: ${e.message}');
} catch (e) {
  debugPrint('Unexpected error: $e');
}
```

---

## GDPR and Consent Management

### TCF v2 Consent

The SDK supports IAB Transparency and Consent Framework (TCF) v2. Enable it in your config:

```dart
final config = SellwildConfig(
  partnerCode: 'weatherbug',
  listingsUrl: '...',
  tcfVersion: 2,
  gppEnabled: true,
);
```

### Native CMP Integration

If your app uses a native Consent Management Platform (OneTrust, Didomi, Usercentrics, etc.), the consent string stored in `SharedPreferences` (Android) or `UserDefaults` (iOS) is **not** automatically bridged to the WebView. Prebid.js looks for `window.__tcfapi`, which will not exist in the isolated WebView context.

**Workaround:** After your CMP collects consent, inject the TC string into the WebView before the widget loads. This requires accessing the WebView controller, which is not currently exposed by the SDK. If your app requires native CMP bridging, consider using Prebid Server (S2S mode) where GDPR consent is passed server-side via `regs.ext.gdpr` in the OpenRTB request.

### Prebid Server GDPR Handling

When using Prebid Server S2S mode, the server enforces GDPR based on the `regs.ext.gdpr` field in the OpenRTB bid request. The Sellwild Prebid Server instance at `prebid.sellwild.com` is configured with `gdpr.default-value: 1`, meaning GDPR enforcement is applied by default unless the request explicitly opts out. See the [Prebid Server Configuration Guide](./prebid-server.md) for details on how consent signals propagate.

### IAB Category Declaration

Declare IAB content categories for your app to improve ad relevance and brand safety:

```dart
final config = SellwildConfig(
  partnerCode: 'weatherbug',
  listingsUrl: '...',
  iabCats: ['IAB15', 'IAB15-10'],  // Technology > Weather
);
```

---

## Troubleshooting

### Widget shows a blank white screen

**Cause:** The WebView failed to load `https://widget.sellwild.com/partner.js`.

**Steps:**
1. Verify network connectivity. Open the URL in a device browser to confirm it loads.
2. On iOS, confirm `NSAllowsArbitraryLoadsInWebContent` is set in `Info.plist`.
3. Check `onError` callback output for specific error messages.
4. Enable debug mode (`debug: true` in `SellwildConfig`) and inspect the WebView console output.

### Listings do not appear

**Cause:** The `listingsUrl` returned no results or an unexpected response format.

**Steps:**
1. Test the URL directly: `curl -s "https://api.sellwild.com/widget/listings?partner=weatherbug" | python3 -m json.tool`
2. Verify the response contains a `result.rs` array with listing objects.
3. Check that `partnerCode` matches an active partner account.

### `onListingTap` is never called

**Cause:** The web widget sends a URL-based `LISTING_CLICK` event via `window.open()`. The SDK constructs a minimal `SellwildListing` stub with the URL. If neither a full listing object nor a URL is present in the bridge message, the callback is skipped.

**Steps:**
1. Confirm the `onListingTap` callback is set on the `SellwildWidget`.
2. Tap a listing and check debug output for bridge messages.
3. The `listing.url` field on the stub will contain the target URL. Use it to navigate.

### Ads are not filling (no impressions)

**Cause:** Header bidding requires correct in-app traffic signals.

**Steps:**
1. Set `appBundleId` and `appStoreUrl` in `SellwildConfig`. Without these, bid requests are classified as web traffic and most SSPs will not bid.
2. If using Prebid Server, verify the endpoint is reachable: `curl -I https://prebid.sellwild.com/openrtb2/auction`
3. Check that the bidder codes in `PrebidServerConfig.bidders` match your server-side configuration.
4. Enable `debug: true` and look for Prebid.js auction results in the console.

### WebView crashes on Android API 28+

**Cause:** Multiple processes sharing the same WebView data directory.

**Fix:** Set a unique data directory suffix in your `Application.onCreate()`:

```kotlin
// In your Android Application class
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
    WebView.setDataDirectorySuffix("sellwild_webview")
}
```

### GDPR regions see no ads

**Cause:** Prebid.js cannot find a TCF consent string and suppresses all bidder calls.

**Steps:**
1. If using a native CMP, verify the consent string is available before loading the widget.
2. Consider switching to Prebid Server S2S mode, where GDPR enforcement is handled server-side.
3. Check that `tcfVersion` is set to `2` in your config if you are passing TCF v2 consent.

### Price badge shows `$` for non-USD listings

**Cause:** The `SellwildListingCard` maps currency codes to symbols. Supported codes: `USD`, `EUR`, `GBP`, `CAD`, `AUD`. All other currencies default to `$`.

**Fix:** If you need additional currency symbols, render your own price display using `listing.currency` and `listing.price`.

### Build fails with "Minimum OS version" error on iOS

**Fix:** Ensure your `ios/Podfile` specifies iOS 13.0 or higher:

```ruby
platform :ios, '13.0'
```

### Hot reload does not update the widget

**Expected behavior.** The WebView content is loaded in `initState()` and is not rebuilt on hot reload. Use hot restart (`flutter run --restart`) or navigate away and back to reload the widget.

---

## SellwildConfig Complete Reference

| Field                | Type                   | Default              | Description                                           |
|----------------------|------------------------|----------------------|-------------------------------------------------------|
| `partnerCode`        | `String`               | (required)           | Your Sellwild partner identifier                      |
| `listingsUrl`        | `String`               | (required)           | API endpoint for listing data                         |
| `slug`               | `String`               | `''`                 | Partner slug for URL construction                     |
| `name`               | `String`               | `''`                 | Partner display name                                  |
| `apiBaseUrl`         | `String`               | `https://api.sellwild.com` | Base URL for API calls                          |
| `title`              | `String?`              | null                 | Widget header title                                   |
| `linkText`           | `String?`              | `'View all'`         | Text for the "view all" link                          |
| `buyNowText`         | `String?`              | `'Buy now'`          | Text for the buy button                               |
| `titleColor`         | `String`               | `'#000000'`          | Widget title color (hex)                              |
| `titleSize`          | `int`                  | `16`                 | Widget title font size in px                          |
| `linkColor`          | `String`               | `'#0066cc'`          | Link text color (hex)                                 |
| `fontSize`           | `int`                  | `13`                 | Listing title font size in px                         |
| `fontColor`          | `String`               | `'#ffffff'`          | Listing title font color (hex)                        |
| `priceColor`         | `String`               | `'#333333'`          | Price badge background color (hex)                    |
| `priceFontColor`     | `String`               | `'#ffffff'`          | Price badge text color (hex)                          |
| `marginBottom`       | `int`                  | `10`                 | Bottom margin in px                                   |
| `colors`             | `List<String>`         | `['#333333']`        | Theme accent colors (hex)                             |
| `overlayTitle`       | `bool`                 | `false`              | Overlay title on listing image                        |
| `watermark`          | `bool`                 | `false`              | Show watermark                                        |
| `watermarkTitle`     | `String`               | `'Powered by Sellwild'` | Watermark text                                    |
| `adType`             | `String?`              | null (defaults to `PrebidOnly`) | Ad system selection                      |
| `bannerZid`          | `String?`              | null                 | Top banner zone ID                                    |
| `bottomBannerZid`    | `String?`              | null                 | Bottom banner zone ID                                 |
| `mobileBannerZid`    | `String?`              | null                 | Mobile-specific banner zone ID                        |
| `mobileZids`         | `List<String>`         | `[]`                 | Additional mobile zone IDs                            |
| `hideBannerTop`      | `bool`                 | `false`              | Hide the top banner placement                         |
| `hideBannerBottom`   | `bool`                 | `false`              | Hide the bottom banner placement                      |
| `gamTag`             | `String?`              | null                 | Google Ad Manager ad unit path                        |
| `gptProxyUrl`        | `String?`              | null                 | GPT script proxy URL                                  |
| `disableGpt`         | `bool`                 | `false`              | Disable GPT entirely                                  |
| `adDisableDisplay`   | `bool`                 | `false`              | Disable all display ads                               |
| `adRefreshMax`       | `int`                  | `0`                  | Max ad refreshes (0 = unlimited)                      |
| `adRefreshMaxMobile` | `int`                  | `0`                  | Max ad refreshes on mobile (0 = use `adRefreshMax`)   |
| `adRefreshInterval`  | `Duration`             | `30 seconds`         | Time between ad refreshes                             |
| `maxFailedAuctions`  | `int`                  | `3`                  | Stop refreshing after N consecutive no-fills          |
| `prebidSrc`          | `String?`              | null                 | Custom Prebid.js bundle URL                           |
| `floorMultiplier`    | `double`               | `1.0`                | Bid floor multiplier                                  |
| `gppEnabled`         | `bool`                 | `false`              | Enable IAB Global Privacy Platform                    |
| `tcfVersion`         | `int`                  | `0`                  | TCF version (0 = disabled, 2 = TCF v2)                |
| `iabCats`            | `List<String>`         | `[]`                 | IAB content category codes                            |
| `boltive`            | `bool`                 | `false`              | Enable Boltive ad quality                             |
| `boltiveClientId`    | `String`               | `''`                 | Boltive client identifier                             |
| `lotame`             | `bool`                 | `false`              | Enable Lotame data enrichment                         |
| `appBundleId`        | `String?`              | null                 | App bundle ID for `ortb2.app.bundle`                  |
| `appStoreUrl`        | `String?`              | null                 | App store URL for `ortb2.app.storeurl`                |
| `prebidServer`       | `PrebidServerConfig?`  | null                 | Prebid Server S2S configuration                       |
| `debug`              | `bool`                 | `false`              | Enable debug logging                                  |
