# API Reference

Per-platform reference for all public classes, methods, delegates, and types in the Sellwild SDK.

---

## Table of Contents

1. [iOS (Swift)](#ios-swift)
2. [Android (Kotlin)](#android-kotlin)
3. [React Native (TypeScript)](#react-native-typescript)
4. [Flutter (Dart)](#flutter-dart)
5. [Core Types](#core-types)

---

## iOS (Swift)

### SellwildConfig

Primary configuration struct. All ad views and widgets read from this object.

```swift
public struct SellwildConfig: Codable {
    // Required
    public var partnerCode: String
    public var listingsUrl: String

    // App identity
    public var apiBaseUrl: String               // default: "https://api.sellwild.com"
    public var appBundleId: String?
    public var appStoreUrl: String?

    // Prebid Server
    public var prebidServer: PrebidServerConfig?

    // Ad refresh
    public var adRefreshMax: Int                 // default: 0
    public var adRefreshMaxMobile: Int           // default: 0
    public var adRefreshInterval: TimeInterval   // default: 30.0
    public var maxFailedAuctions: Int            // default: 3

    // Privacy
    public var gppEnabled: Bool                  // default: false
    public var tcfVersion: Int                   // default: 0

    // Debug
    public var debug: Bool                       // default: false
}
```

**Initializer:**

```swift
public init(partnerCode: String, listingsUrl: String)
```

For the complete list of fields, see [Configuration Reference](/guide/configuration).

---

### SellwildAdView (UIKit)

A `UIView` subclass that renders a single ad unit in a managed WebView.

**Initializer:**

```swift
public init(config: SellwildConfig, adSize: AdSize, zoneId: String? = nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `config` | `SellwildConfig` | SDK configuration. |
| `adSize` | `AdSize` | Ad dimensions (e.g., `.mrec300x250`). |
| `zoneId` | `String?` | Optional zone identifier for the ad slot. |

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `delegate` | `SellwildAdViewDelegate?` | Delegate for ad lifecycle callbacks. |

**Methods:**

| Method | Description |
|--------|-------------|
| `load()` | Start or reload the ad auction. Call after the view is in the view hierarchy. |
| `pause()` | Stop the refresh timer and pause WebView JavaScript execution. Call in `viewDidDisappear`. |

**Lifecycle notes:**
- The view manages its own `WKWebView` internally. Do not add subviews or modify its frame directly.
- In `deinit`, the view invalidates its refresh timer and removes the `WKScriptMessageHandler` to break retain cycles.
- Each instance uses a separate `WKProcessPool`. Ad sessions are isolated between instances.

---

### SellwildAdViewDelegate

```swift
@objc public protocol SellwildAdViewDelegate: AnyObject {
    @objc optional func sellwildAdViewDidLoad(_ adView: SellwildAdView)
    @objc optional func sellwildAdView(_ adView: SellwildAdView,
                                       didReceiveImpressionForZoneId zoneId: String)
    @objc optional func sellwildAdViewDidRecordClick(_ adView: SellwildAdView)
    @objc optional func sellwildAdView(_ adView: SellwildAdView,
                                       didFailWithError error: Error)
}
```

| Callback | When It Fires |
|----------|---------------|
| `sellwildAdViewDidLoad(_:)` | Creative markup has been rendered in the WebView. |
| `sellwildAdView(_:didReceiveImpressionForZoneId:)` | A viewable impression has been recorded (MRC standard). |
| `sellwildAdViewDidRecordClick(_:)` | The user tapped the ad creative. |
| `sellwildAdView(_:didFailWithError:)` | The auction returned no fill, or an error occurred during rendering. |

All callbacks are dispatched on the main thread. All methods are optional (`@objc optional`).

---

### SellwildAdBanner (SwiftUI)

A `UIViewRepresentable` wrapper around `SellwildAdView` for use in SwiftUI. Requires iOS 14+.

```swift
SellwildAdBanner(
    config: config,
    adSize: .mrec300x250,
    zoneId: nil,
    onImpression: { /* ... */ },
    onError: { error in /* ... */ }
)
.frame(width: 300, height: 250)
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `config` | `SellwildConfig` | Yes | SDK configuration. |
| `adSize` | `AdSize` | Yes | Ad dimensions. |
| `zoneId` | `String?` | No | Optional zone identifier. |
| `onImpression` | `(() -> Void)?` | No | Impression callback. |
| `onError` | `((Error) -> Void)?` | No | Error callback. |

The view calls `load()` automatically when it appears. Refresh timers are managed internally.

---

### SellwildWidgetView (UIKit)

A `UIView` subclass that renders the full Sellwild marketplace widget (listing carousel with embedded ad placements) in a WebView.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `delegate` | `SellwildWidgetViewDelegate?` | Delegate for widget lifecycle callbacks. |

**Methods:**

| Method | Description |
|--------|-------------|
| `pause()` | Pause WebView and ad refresh. |
| `resume()` | Resume WebView rendering. |
| `destroy()` | Release all WebView resources. Do not use the instance after calling. |

---

### SellwildWidget (SwiftUI)

SwiftUI wrapper for the marketplace widget. Requires iOS 14+.

```swift
SellwildWidget(
    config: config,
    onListingTap: { listing in /* ... */ },
    onLoad: { /* ... */ },
    onError: { error in /* ... */ }
)
.frame(height: 400)
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `config` | `SellwildConfig` | Yes | SDK configuration. |
| `onListingTap` | `((SellwildListing) -> Void)?` | No | Called when the user taps a listing. |
| `onLoad` | `(() -> Void)?` | No | Called when the widget finishes loading. |
| `onError` | `((Error) -> Void)?` | No | Called on widget errors. |

---

### SellwildAPIClient

Singleton HTTP client for fetching marketplace listing data.

```swift
// Singleton access
SellwildAPIClient.shared

// Callback-based (iOS 13+)
SellwildAPIClient.shared.fetchListings(config: config) { result in
    switch result {
    case .success(let response):
        // response.listings: [SellwildListing]
    case .failure(let error):
        // handle error
    }
}

// Async/await (iOS 15+)
let response = try await SellwildAPIClient.shared.fetchListings(config: config)

// Clear cached responses
SellwildAPIClient.shared.clearCache()
```

| Method | Return Type | Description |
|--------|-------------|-------------|
| `fetchListings(config:completion:)` | `Result<SellwildListingsResponse, Error>` | Fetch listings with completion handler. |
| `fetchListings(config:)` (async) | `SellwildListingsResponse` | Fetch listings with async/await. Throws on error. |
| `clearCache()` | `Void` | Clear the internal response cache. |

Responses are cached by URL. Subsequent calls with the same `listingsUrl` return the cached result. Call `clearCache()` before re-fetching for fresh data.

---

## Android (Kotlin)

### SellwildConfig

Data class for SDK configuration.

```kotlin
data class SellwildConfig(
    val partnerCode: String,
    val listingsUrl: String,
    val appBundleId: String? = null,
    val appStoreUrl: String? = null,
    val prebidServer: PrebidServerConfig? = null,
    val adRefreshMax: Int = 0,
    val adRefreshMaxMobile: Int = 0,
    val adRefreshIntervalMs: Long = 30_000L,
    val maxFailedAuctions: Int = 3,
    val gppEnabled: Boolean = false,
    val tcfVersion: Int = 0,
    val debug: Boolean = false,
    // ... additional fields
)
```

For the complete list of fields, see [Configuration Reference](/guide/configuration).

---

### SellwildAdView

A `FrameLayout` subclass that renders a single ad unit.

**Constructor:**

```kotlin
SellwildAdView(context: Context)
```

**Setup:**

```kotlin
adView.setup(config: SellwildConfig, adSize: AdSize, zoneId: String? = null)
```

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `listener` | `SellwildAdView.Listener?` | Listener for ad lifecycle callbacks. |

**Methods:**

| Method | Description |
|--------|-------------|
| `setup(config, adSize, zoneId?)` | Configure the ad view. Must be called before `load()`. |
| `load()` | Start or reload the ad auction. |
| `pause()` | Pause WebView and stop refresh timer. Call in `onPause()`. |
| `resume()` | Resume WebView rendering. Call in `onResume()`. |
| `destroy()` | Release all WebView resources. Call in `onDestroy()`. The instance must not be used after this call. |

---

### SellwildAdView.Listener

```kotlin
interface Listener {
    fun onAdLoaded(adView: SellwildAdView) {}
    fun onAdImpression(adView: SellwildAdView, zoneId: String) {}
    fun onAdClicked(adView: SellwildAdView) {}
    fun onAdFailed(adView: SellwildAdView, message: String) {}
}
```

| Callback | When It Fires |
|----------|---------------|
| `onAdLoaded(adView)` | Creative fetched and rendered in the WebView. |
| `onAdImpression(adView, zoneId)` | Viewable impression recorded. |
| `onAdClicked(adView)` | User tapped the ad. |
| `onAdFailed(adView, message)` | No fill or render error. |

All callbacks are dispatched on the main thread. All methods have default (empty) implementations -- override only what you need.

---

### SellwildWidgetView

A `FrameLayout` subclass that renders the full marketplace widget.

**Methods:**

| Method | Description |
|--------|-------------|
| `pause()` | Pause WebView and ad refresh. |
| `resume()` | Resume WebView rendering. |
| `destroy()` | Release all resources. |

**Listener:**

```kotlin
interface Listener {
    fun onWidgetLoaded() {}
    fun onListingTap(listing: SellwildListing) {}
    fun onAdImpression(zoneId: String) {}
    fun onError(message: String) {}
}
```

---

### SellwildAPIClient

Singleton HTTP client using Kotlin coroutines.

```kotlin
val client = SellwildAPIClient.getInstance(context)

// Suspend function -- call from a coroutine scope
val result: Result<SellwildListingsResponse> = client.fetchListings(config)

result.onSuccess { response ->
    // response.listings: List<SellwildListing>
}
result.onFailure { error ->
    // handle error
}

// Clear cache
client.clearCache()
```

| Method | Return Type | Description |
|--------|-------------|-------------|
| `fetchListings(config)` | `Result<SellwildListingsResponse>` | Suspend function. Switches to `Dispatchers.IO` internally. |
| `clearCache()` | `Unit` | Clear the response cache. |

---

### SellwildWebViewCompat

Utility for multi-process WebView safety on Android 9+ (API 28+).

```kotlin
// Call in Application.onCreate(), before any WebView is created
SellwildWebViewCompat.configureForMultiProcess(context)
```

---

## React Native (TypeScript)

### SellwildBanner

Standalone banner ad component. Renders a Prebid-powered ad in a WebView.

```tsx
import { SellwildBanner, buildConfig } from '@sellwild/react-native-sdk';

<SellwildBanner
  config={buildConfig({ partnerCode: 'weatherbug', listingsUrl: '...' })}
  size="300x250"
  zoneId={12345}
  onImpression={() => {}}
  onError={(error) => {}}
  style={{ alignSelf: 'center' }}
/>
```

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `config` | `SellwildConfig` | Yes | Full config (call `buildConfig()` first). |
| `size` | `AdSize` | Yes | Ad dimensions string: `"320x50"`, `"300x250"`, `"728x90"`, `"160x600"`, `"300x600"`, `"1x1"`. |
| `zoneId` | `number` | No | Ad zone identifier. |
| `onImpression` | `() => void` | No | Impression callback. |
| `onError` | `(error: Error) => void` | No | Error callback. |
| `style` | `ViewStyle` | No | React Native style object. |

---

### SellwildWidget

Full marketplace widget with listing carousel and embedded ad placements.

```tsx
import { SellwildWidget, type PartialSellwildConfig } from '@sellwild/react-native-sdk';

<SellwildWidget
  config={partialConfig}
  onListingPress={(listing) => {}}
  onAdImpression={(zoneId) => {}}
  onLoad={() => {}}
  onError={(error) => {}}
  style={{ height: 420 }}
/>
```

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `config` | `PartialSellwildConfig` | Yes | Partial config (calls `buildConfig()` internally). |
| `onListingPress` | `(listing: SellwildListing) => void` | No | Called when a listing is tapped. |
| `onAdImpression` | `(zoneId: string) => void` | No | Called on ad impression. |
| `onLoad` | `() => void` | No | Called when the widget finishes loading. |
| `onError` | `(error: Error) => void` | No | Called on widget errors. |
| `style` | `ViewStyle` | No | React Native style object. |

---

### SellwildListingCard

Native listing card component for custom listing layouts.

```tsx
import { SellwildListingCard } from '@sellwild/react-native-sdk';

<SellwildListingCard
  listing={listing}
  config={config}
  onPress={(listing) => {}}
  style={{ flex: 1 }}
/>
```

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `listing` | `SellwildListing` | Yes | Listing data to render. |
| `config` | `SellwildConfig` | Yes | Used for styling (colors, fonts). |
| `onPress` | `(listing: SellwildListing) => void` | No | Tap callback. |
| `style` | `ViewStyle` | No | React Native style object. |

---

### useSellwildListings

React hook for fetching marketplace listings.

```ts
import { useSellwildListings } from '@sellwild/react-native-sdk';

function ListingsScreen() {
  const { listings, loading, error, refresh } = useSellwildListings(config);
  // ...
}
```

**Return type:**

```ts
interface UseSellwildListingsResult {
  listings: SellwildListing[];     // Fetched listing data
  config: Record<string, unknown>; // Remote widget configuration
  loading: boolean;                // True during fetch or refresh
  error: Error | null;             // Network or parse error, if any
  refresh: () => void;             // Trigger a cache-busting re-fetch
}
```

---

### buildConfig

Utility function that applies default values to a partial configuration object.

```ts
import { buildConfig, type SellwildConfig, type PartialSellwildConfig } from '@sellwild/react-native-sdk';

const config: SellwildConfig = buildConfig({
  partnerCode: 'weatherbug',
  listingsUrl: 'https://api.sellwild.com/listings/weatherbug',
});
```

`SellwildBanner` requires a full `SellwildConfig` (call `buildConfig()` first). `SellwildWidget` accepts `PartialSellwildConfig` and calls `buildConfig()` internally.

---

### configure

**The first-class entry point.** Fetches partner config from the Sellwild CDN and returns a fully-built `SellwildConfig`. Two strings — `partnerCode` and `slug` — and the SDK is ready.

```ts
import { configure } from '@sellwild/react-native-sdk';

const config = await configure('weatherbug', 'weatherbug-main');
```

The remote config is fetched from `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`. Merge order:

1. SDK defaults
2. Remote CDN config (overrides defaults)
3. Optional `overrides` callback (overrides everything)

**Failure handling.** If the fetch fails (network error, timeout, 404), `configure()` returns a `SellwildConfig` with `partnerCode` set and deterministic defaults. The `listingsUrl` is derived from `partnerCode`. Your app always renders.

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `timeout` | `number` | `5000` | Request timeout in milliseconds. |
| `baseUrl` | `string` | `https://widget.sellwild.com` | Override the CDN base URL. |
| `signal` | `AbortSignal` | — | Optional abort signal to cancel the fetch. |
| `overrides` | `PartialSellwildConfig` | — | App-controlled values that win over CDN values. |

```ts
const config = await configure('weatherbug', 'weatherbug-main', {
  timeout: 1500,
  overrides: { debug: __DEV__ },
});
```

Results are cached in-memory per `(partnerCode, slug)` for the lifetime of the process. Call `clearRemoteConfigCache()` to force a re-fetch.

**Platform parity.** Native consumers get the same surface via `SellwildSDK.configure(partnerCode:slug:)` (iOS), `SellwildSDK.configure(partnerCode, slug)` (Android), and `SellwildSDK.configure(partnerCode:, slug:)` (Flutter).

---

### buildConfigWithRemote (deprecated)

Async helper that merges remote config onto a static base config. Superseded by [`configure()`](#configure) in 1.2.0; kept for backward compatibility.

```ts
import { buildConfigWithRemote } from '@sellwild/react-native-sdk';

const config = await buildConfigWithRemote(
  { partnerCode: 'weatherbug', listingsUrl: 'https://api.sellwild.com/listings/weatherbug' },
  'weatherbug-main',
);
```

---

### currencyToSymbol

```ts
import { currencyToSymbol } from '@sellwild/react-native-sdk';

currencyToSymbol('USD'); // '$'
currencyToSymbol('EUR'); // '\u20ac'
currencyToSymbol('GBP'); // '\u00a3'
```

---

## Flutter (Dart)

### SellwildConfig

Immutable configuration class. All fields are `final`.

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

Constructor accepts all fields from the [Configuration Reference](/guide/configuration). The class is `const`-constructible when all arguments are compile-time constants.

---

### SellwildWidget

The primary Flutter widget. Renders the full marketplace experience in a WebView.

```dart
SellwildWidget(
  config: config,
  onListingTap: (SellwildListing listing) { /* ... */ },
  onAdImpression: (String zoneId) { /* ... */ },
  onLoad: () { /* ... */ },
  onError: (Object error) { /* ... */ },
)
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `config` | `SellwildConfig` | Yes | SDK configuration. |
| `onListingTap` | `void Function(SellwildListing)?` | No | Called when a listing is tapped. |
| `onAdImpression` | `void Function(String)?` | No | Called on ad impression with zone ID. |
| `onLoad` | `void Function()?` | No | Called when the widget finishes loading. |
| `onError` | `void Function(Object)?` | No | Called on errors. |

The widget expands to fill its parent. Wrap it in a `SizedBox` or `Expanded` to control dimensions:

```dart
SizedBox(height: 400, child: SellwildWidget(config: config))
```

---

### SellwildBanner

Standalone banner ad widget.

```dart
SellwildBanner(
  config: config,
  adSize: SellwildAdSize.mrec300x250,
  zoneId: '12345',
  onImpression: () { /* ... */ },
  onClick: () { /* ... */ },
  onError: (Object error) { /* ... */ },
)
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `config` | `SellwildConfig` | Yes | SDK configuration. |
| `adSize` | `SellwildAdSize` | Yes | IAB standard ad dimensions. |
| `zoneId` | `String?` | No | Ad zone identifier. |
| `onImpression` | `void Function()?` | No | Called when the ad renders. |
| `onClick` | `void Function()?` | No | Called when the user taps the ad. |
| `onError` | `void Function(Object)?` | No | Called on errors. |

---

### SellwildListingCard

Native Flutter widget for rendering a single listing card.

```dart
SellwildListingCard(
  listing: listing,
  config: config,
  onTap: (SellwildListing listing) { /* ... */ },
)
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `listing` | `SellwildListing` | Yes | Listing data to render. |
| `config` | `SellwildConfig` | Yes | Used for styling (colors, font size). |
| `onTap` | `void Function(SellwildListing)?` | No | Called when the card is tapped. |

The card renders at a fixed width of 160px with an image, price badge, and title. Customize appearance through `SellwildConfig` fields (`priceColor`, `priceFontColor`, `fontSize`).

---

### SellwildAPIClient

Singleton HTTP client for fetching listing data.

```dart
final client = SellwildAPIClient.instance;

// Fetch listings
final response = await client.fetchListings(config);
for (final listing in response.listings) {
  print('${listing.title} -- ${listing.displayPrice}');
}

// Clear cache
client.clearCache();

// Dispose (for test teardown)
client.dispose();
```

| Method | Return Type | Description |
|--------|-------------|-------------|
| `fetchListings(config)` | `Future<SellwildListingsResponse>` | Fetch listings. Caches by URL. |
| `clearCache()` | `void` | Clear the response cache. |
| `dispose()` | `void` | Close the HTTP client. Call only in test teardown. |

**Error handling:** Throws `SellwildException` on network or parsing errors.

```dart
try {
  final response = await SellwildAPIClient.instance.fetchListings(config);
} on SellwildException catch (e) {
  debugPrint('API error: ${e.message}');
}
```

---

### SellwildAdSize

Enum of supported ad dimensions.

```dart
enum SellwildAdSize {
  banner320x50,          // 320 x 50  -- Mobile Banner
  mrec300x250,           // 300 x 250 -- Medium Rectangle
  leaderboard728x90,     // 728 x 90  -- Leaderboard
  halfPage300x600,       // 300 x 600 -- Half Page
  wideSkyscraper160x600, // 160 x 600 -- Wide Skyscraper
}
```

---

### PrebidServerConfig

```dart
class PrebidServerConfig {
  final String accountId;
  final String endpoint;
  final List<String> bidders;
  final int timeout;            // default: 1500
  final String? syncEndpoint;   // derived from endpoint if null
}
```

---

## Core Types

These types are shared across all platforms. Field names may vary slightly per platform convention (camelCase vs snake_case).

### SellwildListing

Represents a marketplace listing.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique listing identifier. |
| `status` | `String` | Listing status (e.g., `"active"`). |
| `title` | `String` | Listing title. |
| `text` | `String?` | Description body text. |
| `url` | `String?` | Deep link to the listing detail page. |
| `categoryId` | `String?` | Category identifier. |
| `categoryGroupId` | `String?` | Category group identifier. |
| `currency` | `String?` | ISO 4217 currency code (`USD`, `EUR`, `GBP`, etc.). |
| `price` | `String?` | Raw price string. |
| `strikePrice` | `String?` | Original price before discount. |
| `has_photo` | `Bool` | Whether the listing has at least one photo. |
| `photo_count` | `Int` | Number of photos. |
| `photos` | `[SellwildPhoto]` | Array of photo objects. |
| `createdDate` | `String?` | ISO 8601 creation timestamp. |
| `videoUrl` | `String?` | Video URL, if available. |
| `shippable` | `String?` | Shipping availability flag. |
| `listingType` | `String?` | Listing type identifier. |
| `dataSourceId` | `String?` | Source identifier for multi-feed integrations. |
| `user` | `SellwildUser?` | Seller information. |
| `distance` | `Double?` | Distance from the user (when geo-sorted). |

**Computed properties:**

| Property | Type | Description |
|----------|------|-------------|
| `displayPrice` | `String?` | Formatted price string, or `null` if price is zero or unparseable. |
| `primaryPhoto` | `SellwildPhoto?` | First photo, or `null` if no photos exist. |

---

### SellwildPhoto

| Field | Type | Description |
|-------|------|-------------|
| `url` | `String` | Full-size image URL. |
| `thumbUrl` | `String` | Thumbnail image URL. |
| `background` | `String?` | Background color hint (CSS hex). |

---

### SellwildUser

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | User identifier. |
| `firstName` | `String` | First name. |
| `lastName` | `String` | Last name. |
| `username` | `String` | Username. |
| `membershipType` | `String` | Membership tier. |
| `trustLevel` | `String` | Trust level. |
| `has_photo` | `String` | Whether the user has a profile photo. |
| `photos` | `[SellwildPhoto]` | User profile photos. |
| `isPhoneVerified` | `Bool` | Phone verification status. |

---

### AdSize

Ad dimensions. See [Ad Size Reference](/guide/configuration#ad-size-reference) for the full table.

| Value | Dimensions | IAB Name |
|-------|-----------|----------|
| `banner320x50` / `"320x50"` | 320 x 50 | Mobile Banner |
| `mrec300x250` / `"300x250"` | 300 x 250 | Medium Rectangle |
| `leaderboard728x90` / `"728x90"` | 728 x 90 | Leaderboard |
| `halfPage300x600` / `"300x600"` | 300 x 600 | Half Page |
| `wideSkyscraper160x600` / `"160x600"` | 160 x 600 | Wide Skyscraper |

---

### AdPlacement

Describes a single ad placement within the widget layout.

| Field | Type | Description |
|-------|------|-------------|
| `type` | `AdPlacementType` | Placement position: `"banner_top"`, `"banner_bottom"`, `"inline"`, `"interstitial"`. |
| `zoneId` | `String?` | Zone identifier for the placement. |
| `size` | `AdSize` | Ad dimensions for this placement. |

---

### SellwildListingsResponse

Response from `fetchListings`.

| Field | Type | Description |
|-------|------|-------------|
| `listings` | `[SellwildListing]` | Array of listing objects. |
| `config` | `Map<String, Any>` | Server-side widget configuration overrides. |
| `widgetCacheVersionId` | `String?` | Cache version for conditional refresh. |
