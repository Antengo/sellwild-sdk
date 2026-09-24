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
├── react-native/       # React Native package (bridges the native ad views + native feed)
├── ios/                # Swift Package + CocoaPod (native ad views + native feed)
├── android/            # Gradle library (native ad views + native feed)
└── flutter/            # Flutter plugin (webview_flutter — ad + widget; legacy)
```

All four platform SDKs:
1. Load listings from the Sellwild API
2. Render ad units natively via a Prebid Mobile → Google Mobile Ads auction (iOS, Android, React Native — **no WebView in the ad path**). Flutter still renders ads through a WebView (legacy track).
3. Render listings natively on iOS, Android, and React Native — the all-in-one `SellwildFeed` (listings + interleaved ads) or your own UI over `fetchListings` / `useSellwildListings`
4. Bridge listing clicks and ad impressions back to native callbacks
5. Support the full `SellwildConfig` customization system from the web widget

---

## Quick Start

### React Native

```bash
npm install @sellwild/react-native-sdk
```

**All-in-one native feed (listings + interleaved ads):**
```tsx
import { configure, SellwildFeed } from '@sellwild/react-native-sdk'

const config = await configure('mysite', 'mysite-slug')

<SellwildFeed
  config={config}
  style={{ flex: 1 }}
  consumeListingTaps // you navigate; omit to let the SDK open listing.url in-app
  onListingTap={(listing) => {
    navigation.navigate('Detail', { listing })
  }}
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

**Fetch listings and render your own UI:**
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
.package(url: "https://github.com/Antengo/sellwild-sdk.git", from: "1.7.0")
```

**CocoaPods:**
```ruby
pod 'SellwildSDK', '~> 1.7'
```

**UIKit:**
```swift
import SellwildSDK

var config = SellwildConfig(
    partnerCode: "mysite",
)
config.gamTag = "/12345/my-ad-unit"

// All-in-one native feed (listings + interleaved ads)
let feed = SellwildFeedView(config: config)
feed.delegate = self
feed.load()
view.addSubview(feed)

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
    )

    var body: some View {
        VStack {
            SellwildFeed(config: config, onListingTap: { listing in
                print("Tapped: \(listing.title)")
                return false // let the SDK open the listing
            })
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
    implementation("com.sellwild:sdk:1.7.0")
}
```

```kotlin
import com.sellwild.sdk.*

val config = SellwildConfig(
    partnerCode = "mysite",
    gamTag = "/12345/my-ad-unit",
)

// All-in-one native feed (listings + interleaved ads)
val feed = SellwildFeedView(this)
feed.setup(config)
feed.listener = object : SellwildFeedView.Listener {
    override fun onListingTap(listing: SellwildListing): Boolean {
        startActivity(DetailActivity.intent(this@MainActivity, listing))
        return true
    }
}
feed.load()

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
  sellwild_sdk: ^1.3.0
```

```dart
import 'package:sellwild_sdk/sellwild_sdk.dart';

const config = SellwildConfig(
  partnerCode: 'mysite',
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
| `appBundleId` | string | — | **Recommended.** iOS bundle ID or Android package name. Populates `app.bundle` in the OpenRTB request so DSPs receive in-app traffic signals. |
| `appStoreUrl` | string | — | App Store / Play Store URL. Populates `app.storeurl`. |
| `prebidServer` | object | — | Prebid Server S2S config. Set to route all Prebid bids server-side. See [PREBID.md](./PREBID.md). |
| `gamTag` | string | — | Google Ad Manager ad unit path |
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
| `debug` | bool | false | Enable verbose logging |

Ad network bidder configs (ix, openx, pubmatic, appnexus, rubicon) resolve server-side in the Prebid Server stored request for the placement.

---

## Prebid Integration

| Mode | Description |
|------|-------------|
| **B — Prebid Server S2S** | All bids resolve server-side through a Prebid Server instance. Set `prebidServer` in config. |
| **C — Prebid Mobile SDK** (default and only mobile path on iOS, Android, React Native) | Native bidding via a bundled Prebid Mobile → Google Mobile Ads auction. Supports IDFA/GAID. |

See **[PREBID.md](./PREBID.md)** for full setup instructions, comparison table, and migration guide.

---

## Ad Delivery Flow

Native ad path (iOS / Android / React Native):

```
App opens
  └─> SellwildSDK.configure(partnerCode, slug)   # remote config fetched from the Sellwild CDN
        └─> Prebid Mobile + Google Mobile Ads bootstrap (idempotent)
              └─> SellwildAdView.load()
                    ├─> Prebid Mobile runs the header-bidding auction (native, no WebView)
                    │     └─> Winning bid rendered via GAM (.both) or Prebid's own renderer (.prebidOnly)
                    ├─> Impression → delegate / listener → native callback
                    └─> Refresh (GAM: capped timer; .prebidOnly: internal auto-refresh — both floored + capped)
```

Listings render natively too: `SellwildFeed` / `SellwildFeedView` interleaves listing cards with the same native ad slots.

---

## Project Structure

```
core/src/
├── types.ts        # All TypeScript interfaces (incl. PrebidServerConfig)
├── config.ts       # Default config + builder
├── api.ts          # Listings fetch, session, event queue
└── ads.ts          # Prebid unit builders, GPT helpers, geo blocking

react-native/src/
├── SellwildBanner.tsx       # Banner ad (bridges the native ad view)
├── SellwildFeed.tsx         # All-in-one native feed (bridges SellwildFeedView)
├── SellwildListingCard.tsx  # Native listing card
└── useSellwildListings.ts   # Data-fetching hook

ios/Sources/SellwildSDK/
├── SellwildConfig.swift        # Configuration model (incl. PrebidServerConfig)
├── SellwildAPI.swift           # API client + data models
├── SellwildAdView.swift        # UIView banner ad
├── SellwildFeedView.swift      # UIView all-in-one native feed
├── SellwildNativeAdView.swift  # UIView native ad
├── SellwildSwiftUI.swift       # SwiftUI wrappers
└── SellwildPrebidMobile.swift  # Optional: Prebid Mobile SDK helper (#if canImport)

android/src/main/kotlin/com/sellwild/sdk/
├── SellwildConfig.kt           # Configuration model (incl. PrebidServerConfig)
├── SellwildAPI.kt              # API client + data models
├── SellwildAdView.kt           # View banner ad
├── SellwildFeedView.kt         # View all-in-one native feed
├── SellwildNativeAdView.kt     # View native ad
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
| [PREBID.md](./PREBID.md) | Prebid integration guide — Modes B/C, S2S setup, Prebid Mobile SDK |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | How to publish each platform package |
| [RELEASING.md](./RELEASING.md) | Release checklist + publish verification (Definition of Done) |
