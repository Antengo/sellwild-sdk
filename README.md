# Sellwild Mobile Ad SDK

Multi-platform SDK for embedding Sellwild marketplace listings and ad units in mobile apps. Converted from the `sellwild-widget` web widget.

## Platforms

| Platform | Directory | Language | Min Version |
|----------|-----------|----------|-------------|
| React Native | `react-native/` | TypeScript | RN 0.70+ |
| iOS | `ios/` | Swift 5.5 | iOS 13+ |
| Android | `android/` | Kotlin | API 21+ |
| Flutter | `flutter/` | Dart 3 | Flutter 3.10+ |
| Core (shared) | `core/` | TypeScript | Node / Browser |

---

## Architecture

```
sdk/
├── core/               # Shared TypeScript: types, API client, config, ad logic
├── react-native/       # React Native package (WebView + native listing cards)
├── ios/                # Swift Package + CocoaPod (WKWebView + UIKit views)
├── android/            # Gradle library (WebView + Kotlin views)
└── flutter/            # Flutter plugin (webview_flutter + Dart models)
```

All four platform SDKs:
1. Load listings from the Sellwild API
2. Render ad units (GPT/GAM, zone-based, or Prebid) via a thin WebView layer
3. Bridge listing clicks and ad impressions back to native callbacks
4. Support the full `SellwildConfig` customization system from the web widget

---

## Quick Start

### React Native

```bash
npm install @sellwild/react-native-sdk react-native-webview
```

```tsx
import { SellwildWidget } from '@sellwild/react-native-sdk'

<SellwildWidget
  config={{
    partnerCode: 'mysite',
    listingsUrl: 'https://api.sellwild.com/widget/listings?partner=mysite',
    gamTag: '/12345/my-ad-unit',
  }}
  style={{ flex: 1 }}
  onListingPress={(listing) => navigation.navigate('Detail', { listing })}
/>
```

**Banner ad only:**
```tsx
import { SellwildBanner } from '@sellwild/react-native-sdk'

<SellwildBanner
  config={config}
  size="320x50"
  zoneId="98765"
  onImpression={() => analytics.track('ad_impression')}
/>
```

**Fetch listings natively (no WebView):**
```tsx
import { useSellwildListings, SellwildListingCard } from '@sellwild/react-native-sdk'

function ListingsScreen() {
  const { listings, loading, error, refresh } = useSellwildListings(config)
  return (
    <FlatList
      data={listings}
      renderItem={({ item }) => (
        <SellwildListingCard
          listing={item}
          config={config}
          onPress={(l) => openListing(l)}
        />
      )}
      refreshing={loading}
      onRefresh={refresh}
    />
  )
}
```

---

### iOS (Swift)

**Swift Package Manager** — add to `Package.swift`:
```swift
.package(url: "https://github.com/sellwild/sdk-ios.git", from: "1.0.0")
```

**CocoaPods:**
```ruby
pod 'SellwildSDK', '~> 1.0'
```

**UIKit:**
```swift
import SellwildSDK

var config = SellwildConfig(
    partnerCode: "mysite",
    listingsUrl: "https://api.sellwild.com/widget/listings?partner=mysite"
)
config.gamTag = "/12345/my-ad-unit"

// Full widget
let widget = SellwildWidgetView(config: config)
widget.delegate = self
widget.load()
view.addSubview(widget)

// Banner ad
let banner = SellwildAdView(config: config, adSize: .mrec300x250, zoneId: "98765")
banner.delegate = self
banner.load()
view.addSubview(banner)
```

**SwiftUI:**
```swift
import SellwildSDK

struct ContentView: View {
    let config = SellwildConfig(
        partnerCode: "mysite",
        listingsUrl: "https://api.sellwild.com/widget/listings?partner=mysite"
    )

    var body: some View {
        VStack {
            SellwildWidget(config: config) { listing in
                print("Tapped: \(listing.title)")
            }
            .frame(height: 400)

            SellwildAdBanner(config: config, adSize: .banner320x50, zoneId: "98765")
        }
    }
}
```

---

### Android (Kotlin)

Add to `build.gradle.kts`:
```kotlin
dependencies {
    implementation("com.sellwild:sdk:1.0.0")
}
```

```kotlin
import com.sellwild.sdk.*

val config = SellwildConfig(
    partnerCode = "mysite",
    listingsUrl = "https://api.sellwild.com/widget/listings?partner=mysite",
    gamTag = "/12345/my-ad-unit",
)

// Full widget
val widget = SellwildWidgetView(this)
widget.setup(config)
widget.listener = object : SellwildWidgetView.Listener {
    override fun onListingTapped(listing: SellwildListing) {
        startActivity(DetailActivity.intent(this@MainActivity, listing))
    }
}
widget.load()

// Banner ad
val banner = SellwildAdView(this)
banner.setup(config, AdSize.MREC_300x250, zoneId = "98765")
banner.listener = object : SellwildAdView.Listener {
    override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
        analytics.track("ad_impression", mapOf("zoneId" to zoneId))
    }
}
banner.load()
```

**Fetch listings with coroutines:**
```kotlin
viewModelScope.launch {
    val result = SellwildAPIClient(context).fetchListings(config)
    result.onSuccess { response ->
        listingsAdapter.submitList(response.listings)
    }
}
```

---

### Flutter

Add to `pubspec.yaml`:
```yaml
dependencies:
  sellwild_sdk: ^1.0.0
```

```dart
import 'package:sellwild_sdk/sellwild_sdk.dart';

const config = SellwildConfig(
  partnerCode: 'mysite',
  listingsUrl: 'https://api.sellwild.com/widget/listings?partner=mysite',
);

// Full widget
SellwildWidget(
  config: config,
  onListingTap: (listing) => Navigator.pushNamed(context, '/detail', arguments: listing),
)

// Banner ad
SellwildBanner(
  config: config,
  adSize: SellwildAdSize.mrec300x250,
  zoneId: '98765',
  onImpression: () => analytics.track('ad_impression'),
)

// Native listing card
SellwildListingCard(
  listing: listing,
  config: config,
  onTap: (l) => openDetail(l),
)
```

---

## Configuration Reference

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `partnerCode` | string | required | Publisher partner code |
| `listingsUrl` | string | required | API URL for listings feed |
| `appBundleId` | string | — | **Recommended.** iOS bundle ID or Android package name. Populates `ortb2.app.bundle` in Prebid.js so DSPs receive in-app traffic signals. |
| `appStoreUrl` | string | — | App Store / Play Store URL. Populates `ortb2.app.storeurl`. |
| `prebidServer` | object | — | Prebid Server S2S config. Set to route all Prebid bids server-side. See [PREBID.md](./PREBID.md). |
| `gamTag` | string | — | Google Ad Manager ad unit path |
| `gptProxyUrl` | string | — | GPT proxy URL (for ISP ad-block bypass) |
| `bannerZid` | string | — | Zone ID for top banner |
| `bottomBannerZid` | string | — | Zone ID for bottom banner |
| `mobileZids` | string[] | `[]` | Inline zone IDs (mobile) |
| `hideBannerTop` | bool | false | Suppress top banner |
| `hideBannerBottom` | bool | false | Suppress bottom banner |
| `adRefreshMax` | int | 0 | Max ad refreshes (0 = no limit) |
| `adRefreshMaxMobile` | int | 0 | Max refreshes on mobile |
| `adRefreshInterval` | duration | 30s | Delay between refreshes |
| `boltive` | bool | false | Enable Boltive ad quality wrapper |
| `boltiveClientId` | string | — | Boltive client ID |
| `prebidSrc` | string | — | Custom Prebid.js bundle URL |
| `debug` | bool | false | Enable verbose logging |

Ad network bidder configs (ix, openx, pubmatic, appnexus, rubicon) are passed through to Prebid.js for header bidding auctions.

---

## Prebid Integration

The SDK supports three Prebid integration modes:

| Mode | Description |
|------|-------------|
| **A — Prebid.js in WebView** (default) | Client-side bidding inside the WebView. Set `appBundleId` for proper in-app signals. |
| **B — Prebid Server S2S** | All bids routed through a Prebid Server instance. Solves cookie/IDFA WebView limitations. Set `prebidServer` in config. |
| **C — Prebid Mobile SDK** | True native bidding (iOS/Android only). Supports IDFA/GAID. Requires `PrebidMobile` dependency. |

See **[PREBID.md](./PREBID.md)** for full setup instructions, comparison table, and migration guide.

---

## Ad Delivery Flow

```
App opens
  └─> SellwildConfig loaded (partnerCode, listingsUrl, ad config)
        └─> API fetch: listings + widgetCacheVersionId
              └─> WebView renders widget HTML
                    ├─> Prebid.js runs header bidding auction
                    │     └─> Winning bid rendered via GPT or direct
                    ├─> Boltive wraps ad (if enabled)
                    ├─> Impression → JS bridge → native callback
                    └─> Ad refresh timer (adRefreshInterval)
```

---

## Project Structure

```
core/src/
├── types.ts        # All TypeScript interfaces (incl. PrebidServerConfig)
├── config.ts       # Default config + builder
├── api.ts          # Listings fetch, session, event queue
└── ads.ts          # Prebid unit builders, GPT helpers, geo blocking

react-native/src/
├── SellwildWidget.tsx       # Full widget (WebView)
├── SellwildBanner.tsx       # Banner ad (WebView)
├── SellwildListingCard.tsx  # Native listing card
├── useSellwildListings.ts   # Data-fetching hook
└── htmlBuilder.ts           # HTML generation for WebViews (ortb2.app + S2S injection)

ios/Sources/SellwildSDK/
├── SellwildConfig.swift        # Configuration model (incl. PrebidServerConfig)
├── SellwildAPI.swift           # API client + data models
├── SellwildAdView.swift        # UIView banner ad
├── SellwildWidgetView.swift    # UIView full widget
├── SellwildSwiftUI.swift       # SwiftUI wrappers
└── SellwildPrebidMobile.swift  # Optional: Prebid Mobile SDK helper (#if canImport)

android/src/main/kotlin/com/sellwild/sdk/
├── SellwildConfig.kt           # Configuration model (incl. PrebidServerConfig)
├── SellwildAPI.kt              # API client + data models
├── SellwildAdView.kt           # View banner ad
├── SellwildWidgetView.kt       # View full widget (incl. SellwildWebViewCompat)
└── SellwildPrebidMobile.kt     # Optional: Prebid Mobile SDK helper (reflection-based)

flutter/lib/
├── sellwild_sdk.dart        # Package barrel export
└── src/
    ├── sellwild_config.dart       # Configuration model (incl. PrebidServerConfig)
    ├── sellwild_models.dart       # Listing + photo models
    ├── sellwild_widget.dart       # Widget + Banner widgets (ortb2.app + S2S injection)
    ├── sellwild_api.dart          # API client
    └── sellwild_listing_card.dart # Native listing card widget
```

---

## Documentation

| File | Contents |
|------|----------|
| [README.md](./README.md) | This file — overview, quick-start, config reference |
| [SETUP.md](./SETUP.md) | Per-platform integration instructions |
| [PREBID.md](./PREBID.md) | Prebid integration guide — Modes A/B/C, S2S setup, Prebid Mobile SDK |
| [VALIDATION.md](./VALIDATION.md) | Correctness report — all bugs found and fixed |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | How to publish each platform package |
