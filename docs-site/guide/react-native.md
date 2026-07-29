# Sellwild SDK -- React Native Integration Guide

Server-side header bidding for React Native applications, powered by Prebid Server.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Native Feed (1.3.5+)](#native-feed-1-3-5) ⭐ **Recommended**
4. [Native Banner (1.3.0+)](#native-banner-path-1-3-0)
5. [iOS Configuration](#ios-configuration)
6. [Android Configuration](#android-configuration)
7. [Basic Integration](#basic-integration)
8. [Native Listing Cards](#native-listing-cards)
9. [Direct Prebid Server Auction](#direct-prebid-server-auction)
10. [Prebid Server Configuration](#prebid-server-configuration)
11. [Metro Configuration](#metro-configuration)
12. [GDPR and Privacy](#gdpr-and-privacy)
13. [TypeScript Reference](#typescript-reference)
14. [Troubleshooting](#troubleshooting)
15. [Migration Guide: Widget → Feed](#migration-guide)

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|-------------|-----------------|-------|
| Node.js | 18.0+ | LTS recommended |
| React Native | 0.72+ | New Architecture (Fabric) supported on 0.74+ |
| Xcode | 15.0+ | Required for iOS builds; macOS Sonoma or later |
| Android Studio | Hedgehog (2023.1.1)+ | JDK 17 bundled |
| CocoaPods | 1.14+ | `sudo gem install cocoapods` if not installed |
| `react-native-webview` | 11.0+ | Peer dependency. Required only if you use `<SellwildWidget>` (the marketplace listings surface). The native banner path does not depend on it. |

Verify your environment before proceeding:

```bash
npx react-native doctor
```

---

## Installation

### 1. Install packages

```bash
npm install @sellwild/react-native-sdk
```

Or with Yarn:

```bash
yarn add @sellwild/react-native-sdk
```

`react-native-webview` is declared as a peer dependency. It is only required if your integration uses `<SellwildWidget>` (the marketplace listings surface). If you do, install it alongside the SDK:

```bash
npm install react-native-webview
# or
yarn add react-native-webview
```

### 2. iOS -- Install native dependencies

```bash
cd ios && pod install && cd ..
```

If you are using the New Architecture, ensure your Podfile includes:

```ruby
ENV['RCT_NEW_ARCH_ENABLED'] = '1'
```

### 3. Android -- Auto-linking

No additional steps are required. React Native auto-linking resolves the Sellwild RN bridge automatically during the Gradle build.

Confirm auto-linking registered the package:

```bash
npx react-native config
```

The output should list `@sellwild/react-native-sdk` under `dependencies`.

---

## Native Feed (1.3.5+)

> ⭐ **Recommended for marketplace listings.** Higher CPMs than the WebView widget, native scrolling performance, and reliable tap handling.

`<SellwildFeed>` is an all-in-one native surface: a single-column scroll of native listing cards interleaved with native Prebid + GAM ads. There is **no WebView** — every row is native on both iOS (UITableView) and Android (RecyclerView).

```tsx
import React, { useEffect, useState } from 'react';
import { SafeAreaView, ActivityIndicator } from 'react-native';
import { SellwildFeed, configure } from '@sellwild/react-native-sdk';

export default function MarketplaceScreen() {
  const [config, setConfig] = useState(null);

  useEffect(() => {
    configure('weatherbug', 'weatherbug-weatherbug').then(setConfig);
  }, []);

  if (!config) return <ActivityIndicator />;

  return (
    <SafeAreaView style={{ flex: 1 }}>
      <SellwildFeed
        config={config}
        style={{ flex: 1 }}
        onLoad={() => console.log('Feed loaded')}
        onListingTap={(listing) => {
          console.log('Tapped:', listing.title);
          return false; // Let SDK open in browser
        }}
        onAdImpression={(zoneId) => console.log('Ad impression:', zoneId)}
        onError={(err) => console.warn('Feed error:', err.message)}
      />
    </SafeAreaView>
  );
}
```

### Props

| Prop | Type | Description |
|------|------|-------------|
| `config` | `SellwildConfig` | Resolved config from `configure(partnerCode, slug)`. |
| `style` | `ViewStyle?` | Optional style override. Feed expands to fill container by default. |

### Events

| Event | Signature | Fires when |
|-------|-----------|------------|
| `onLoad` | `() => void` | Initial listings fetch completes successfully. |
| `onListingTap` | `(listing: SellwildListing) => boolean \| void` | User taps a listing card. Return `true` to consume (handle yourself); return `false`/omit to let SDK open the URL in-app browser. |
| `onAdImpression` | `(zoneId: string) => void` | A native ad row records an impression. |
| `onAdClicked` | `(zoneId: string) => void` | A native ad row is clicked. |
| `onError` | `(error: Error) => void` | Listings fetch fails or a row fails to render. |

### Migrating from SellwildWidget

If you're currently using `<SellwildWidget>` (the WebView-based component), see the [Migration Guide](./migration-widget-to-feed.md) for step-by-step instructions.

---

## Native banner path (1.3.0+)

As of 1.3.0, `<SellwildBanner>` is backed by a native iOS/Android view bridged through `RCTViewManager`. The ad-rendering path no longer uses `react-native-webview` — it runs a Prebid Mobile auction natively and renders the winning bid in `AdManagerBannerView` (iOS) or `AdManagerAdView` (Android).

```tsx
import { SellwildBanner } from '@sellwild/react-native-sdk';

<SellwildBanner
  config={config}
  size="320x50"
  zoneId="home_top_banner"
  onImpression={() => console.log('impression')}
  onClick={() => console.log('click')}
  onError={(err) => console.warn('failed', err.message)}
/>
```

**Props**

| Prop | Type | Description |
|------|------|-------------|
| `config` | `SellwildConfig` | Resolved config (typically from `configure(partnerCode, slug)`). |
| `size` | `AdSize` | Banner size — one of `'320x50'`, `'300x250'`, `'728x90'`, `'160x600'`, `'300x600'`, `'1x1'`. |
| `zoneId` | `number \| string` | Ad zone / placement identifier, mapped to a GAM ad unit on the server. |
| `style` | `ViewStyle?` | Optional override for the host `View` style. The slot starts at the chosen `size` and then **auto-sizes** to the rendered creative (see below); a `height` you set here is overridden once an ad renders. |

**Events**

| Event | Signature | Fires when |
|-------|-----------|-----------|
| `onImpression` | `() => void` | GMA reports an impression on the rendered creative. |
| `onClick` | `() => void` | The user taps the ad. |
| `onError` | `(err: Error) => void` | The Prebid auction or GMA load fails. `err.message` contains a human-readable reason. |

**Dynamic slot sizing.** `<SellwildBanner>` **resizes itself to the rendered creative** — a multi-size fallback (e.g. no 300×250 fill → a 320×50 renders), an outstream video, or the capped native template. The native view reports its size on render and the component updates its own width/height, so the slot never clips tall content or leaves whitespace under a smaller fill. You don't wire anything; just don't hard-lock `height` in `style` if you want it to track.

The slot's **baseline is the bounding box of the requested size set** (the widest and tallest across the primary `size` and any `BANNER_SIZES` fallbacks, which `<SellwildBanner>` reads from `config.remote`), not the primary alone — so a *wider* fallback (a 320-wide creative in a 300-wide MREC request) never clips horizontally before the resize event lands. `onAdResize` then tightens the slot to the actual creative. (Gaps: a `prebidOnly` multi-size slot stays at the reserved bounding box — the rendering view doesn't surface the winning creative size, so it won't tighten, but it no longer clips; feed ad rows are not yet self-sizing.)

**Required platform setup.** GMA still needs `GADApplicationIdentifier` (iOS `Info.plist`) and `com.google.android.gms.ads.APPLICATION_ID` (Android `AndroidManifest.xml`) to initialize. See the [iOS Configuration](#ios-configuration) and [Android Configuration](#android-configuration) sections below.

**Marketplace listings.** `<SellwildWidget>` is a separate component for the marketplace listings surface and is not part of the ad path. If your integration only requires banner ads, you do not need to install `react-native-webview` or use this component.

---

## iOS Configuration

### Info.plist

Add the following entries to `ios/<YourApp>/Info.plist`.

#### App Transport Security

Allow the SDK to communicate with Sellwild auction and widget endpoints over HTTPS. If your app already permits arbitrary loads, this block is not required.

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoadsInWebContent</key>
  <true/>
  <key>NSExceptionDomains</key>
  <dict>
    <key>prebid.sellwild.com</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <false/>
      <key>NSExceptionRequiresForwardSecrecy</key>
      <true/>
      <key>NSIncludesSubdomains</key>
      <true/>
    </dict>
    <key>widget.sellwild.com</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <false/>
      <key>NSExceptionRequiresForwardSecrecy</key>
      <true/>
      <key>NSIncludesSubdomains</key>
      <true/>
    </dict>
  </dict>
</dict>
```

#### User Tracking (ATT)

Required if you intend to pass IDFA to demand partners for improved fill rates.

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This app uses your advertising identifier to deliver personalized ads and measure campaign performance.</string>
```

---

## Android Configuration

### AndroidManifest.xml

Add the following to `android/app/src/main/AndroidManifest.xml`.

#### Internet permission

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

#### Cleartext traffic (development only)

Required when testing against local Prebid Server instances or non-HTTPS staging environments. Remove or restrict for production builds.

```xml
<application
  android:usesCleartextTraffic="true"
  ...>
```

For production, use a network security configuration instead:

```xml
<!-- android/app/src/main/res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <domain-config cleartextTrafficPermitted="false">
    <domain includeSubdomains="true">prebid.sellwild.com</domain>
    <domain includeSubdomains="true">widget.sellwild.com</domain>
    <domain includeSubdomains="true">cache.sellwild.com</domain>
  </domain-config>
</network-security-config>
```

Reference it in your manifest:

```xml
<application
  android:networkSecurityConfig="@xml/network_security_config"
  ...>
```

---

## Basic Integration

The following `App.tsx` demonstrates a complete integration with banner ads and the full listing widget.

::: tip Recommended: use `configure()`
For most integrations, call `configure(partnerCode, slug)` instead of building
a config object by hand. It fetches your partner config from
`https://widget.sellwild.com/app/{partnerCode}/{slug}.json` and populates every
field below automatically:

```tsx
import { configure } from '@sellwild/react-native-sdk';

const config = await configure('weatherbug', 'weatherbug-weatherbug');
```

The static example below is shown only to document each field.
:::

```tsx
// App.tsx
import React, { useCallback } from 'react';
import { SafeAreaView, ScrollView, StyleSheet, Alert } from 'react-native';
import {
  SellwildWidget,
  SellwildBanner,
  buildConfig,
  type SellwildConfig,
  type SellwildListing,
  type PartialSellwildConfig,
} from '@sellwild/react-native-sdk';

// ---------------------------------------------------------------------------
// 1. Configure the SDK
// ---------------------------------------------------------------------------
const partialConfig: PartialSellwildConfig = {
  partnerCode: 'weatherbug',

  // Mobile app identity -- required for proper in-app bid classification.
  appBundleId: 'com.aws.android',
  appStoreUrl: 'https://play.google.com/store/apps/details?id=com.aws.android',

  // Prebid Server S2S -- routes header bidding through Sellwild's managed
  // Prebid Server instance instead of running client-side adapters.
  prebidServer: {
    accountId: 'weatherbug',
    endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
    bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
    timeout: 1500,
  },

  // Display customization
  titleColor: '#1a1a1a',
  priceColor: '#2d8c3c',
  priceFontColor: '#ffffff',
  fontSize: 13,
};

// Build a full config object for components that require it.
const sdkConfig: SellwildConfig = buildConfig(partialConfig);

// Tip: in 1.2.0+ the first-class integration path is
// `await configure('weatherbug', 'weatherbug-weatherbug')`, which fetches every
// runtime field — ad zones, refresh intervals, waterfall
// partners — from the Sellwild CDN. See `Configuration > Remote Config`.

// ---------------------------------------------------------------------------
// 2. Application root
// ---------------------------------------------------------------------------
export default function App() {
  const handleImpression = useCallback(() => {
    console.log('[Sellwild] Banner impression recorded');
  }, []);

  const handleBannerError = useCallback((error: Error) => {
    console.warn('[Sellwild] Banner error:', error.message);
  }, []);

  const handleListingPress = useCallback((listing: SellwildListing) => {
    // Navigate to the listing URL or a detail screen.
    if (listing.url) {
      console.log('[Sellwild] Listing tapped:', listing.url);
    }
  }, []);

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView>
        {/* ----------------------------------------------------------------- */}
        {/* Mobile leaderboard banner -- 320x50                               */}
        {/* ----------------------------------------------------------------- */}
        <SellwildBanner
          config={sdkConfig}
          size="320x50"
          zoneId={12345}
          onImpression={handleImpression}
          onError={handleBannerError}
          style={styles.banner}
        />

        {/* ----------------------------------------------------------------- */}
        {/* Full listing widget with embedded Prebid header bidding            */}
        {/* ----------------------------------------------------------------- */}
        <SellwildWidget
          config={partialConfig}
          onListingPress={handleListingPress}
          onAdImpression={(zoneId) => {
            console.log('[Sellwild] Widget ad impression, zone:', zoneId);
          }}
          onError={(error) => {
            console.warn('[Sellwild] Widget error:', error.message);
          }}
          onLoad={() => {
            console.log('[Sellwild] Widget loaded');
          }}
          style={styles.widget}
        />

        {/* ----------------------------------------------------------------- */}
        {/* Medium rectangle banner -- 300x250                                */}
        {/* ----------------------------------------------------------------- */}
        <SellwildBanner
          config={sdkConfig}
          size="300x250"
          zoneId={12346}
          onImpression={handleImpression}
          onError={handleBannerError}
          style={styles.mediumRectangle}
        />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
  },
  banner: {
    alignSelf: 'center',
    marginVertical: 12,
  },
  widget: {
    height: 420,
    marginHorizontal: 8,
  },
  mediumRectangle: {
    alignSelf: 'center',
    marginVertical: 16,
  },
});
```

### Component Reference

| Component | Config Type | Description |
|-----------|------------|-------------|
| `SellwildWidget` | `PartialSellwildConfig` | Full listing carousel with embedded Prebid auctions |
| `SellwildBanner` | `SellwildConfig` (full) | Standalone IAB banner ad unit |

`SellwildWidget` calls `buildConfig()` internally. `SellwildBanner` requires a pre-built `SellwildConfig` -- call `buildConfig()` before passing it.

---

## Native Listing Cards

For full control over layout and rendering, use the `useSellwildListings` hook with the `SellwildListingCard` component. This approach renders listings as native React Native views.

### Basic FlatList integration

```tsx
import React, { useCallback } from 'react';
import {
  FlatList,
  View,
  StyleSheet,
  ActivityIndicator,
  Text,
  RefreshControl,
  Linking,
} from 'react-native';
import {
  useSellwildListings,
  SellwildListingCard,
  SellwildBanner,
  buildConfig,
  type SellwildConfig,
  type SellwildListing,
} from '@sellwild/react-native-sdk';

const sdkConfig: SellwildConfig = buildConfig({
  partnerCode: 'weatherbug',
  appBundleId: 'com.aws.android',
  prebidServer: {
    accountId: 'weatherbug',
    endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
    bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
    timeout: 1500,
  },
});

// ---------------------------------------------------------------------------
// Interleave ad placements between organic listings
// ---------------------------------------------------------------------------
type FeedItem =
  | { type: 'listing'; data: SellwildListing }
  | { type: 'ad'; zoneId: number };

function buildFeed(listings: SellwildListing[]): FeedItem[] {
  const feed: FeedItem[] = [];
  listings.forEach((listing, index) => {
    feed.push({ type: 'listing', data: listing });
    // Insert an ad after every 4th listing
    if ((index + 1) % 4 === 0) {
      feed.push({ type: 'ad', zoneId: 12345 + Math.floor(index / 4) });
    }
  });
  return feed;
}

export default function ListingFeed() {
  const { listings, loading, error, refresh } = useSellwildListings(sdkConfig);
  const feed = buildFeed(listings);

  const handlePress = useCallback((listing: SellwildListing) => {
    if (listing.url) {
      Linking.openURL(listing.url);
    }
  }, []);

  const renderItem = useCallback(
    ({ item }: { item: FeedItem }) => {
      if (item.type === 'ad') {
        return (
          <SellwildBanner
            config={sdkConfig}
            size="300x250"
            zoneId={item.zoneId}
            onImpression={() => console.log('[Ad] Impression:', item.zoneId)}
            onError={(err) => console.warn('[Ad] Error:', err.message)}
            style={styles.adCard}
          />
        );
      }
      return (
        <SellwildListingCard
          listing={item.data}
          config={sdkConfig}
          onPress={handlePress}
          style={styles.listingCard}
        />
      );
    },
    [handlePress],
  );

  const keyExtractor = useCallback(
    (item: FeedItem, index: number) =>
      item.type === 'listing' ? `listing-${item.data.id}` : `ad-${index}`,
    [],
  );

  if (loading && listings.length === 0) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.center}>
        <Text style={styles.errorText}>Failed to load listings.</Text>
        <Text style={styles.errorDetail}>{error.message}</Text>
      </View>
    );
  }

  return (
    <FlatList
      data={feed}
      renderItem={renderItem}
      keyExtractor={keyExtractor}
      numColumns={2}
      columnWrapperStyle={styles.row}
      contentContainerStyle={styles.list}
      refreshControl={
        <RefreshControl refreshing={loading} onRefresh={refresh} />
      }
    />
  );
}

const styles = StyleSheet.create({
  list: {
    padding: 8,
  },
  row: {
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  listingCard: {
    flex: 1,
    maxWidth: '48%',
    marginHorizontal: 4,
  },
  adCard: {
    alignSelf: 'center',
    marginVertical: 12,
  },
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  errorText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#c0392b',
  },
  errorDetail: {
    fontSize: 13,
    color: '#666',
    marginTop: 4,
  },
});
```

### `useSellwildListings` Hook API

```ts
function useSellwildListings(config: SellwildConfig): UseSellwildListingsResult;

interface UseSellwildListingsResult {
  listings: SellwildListing[];    // Fetched listing data
  config: Record<string, unknown>; // Remote widget configuration
  loading: boolean;                // True during fetch or refresh
  error: Error | null;             // Network or parse error, if any
  refresh: () => void;             // Trigger a cache-busting re-fetch
}
```

Calling `refresh()` clears the internal listing cache and re-fetches from the network. Use it with `RefreshControl` for pull-to-refresh.

---

## Direct Prebid Server Auction

For advanced integrations where you need full control over the bidding process, you can call the Prebid Server auction endpoint directly using `fetch()`. This bypasses `<SellwildBanner>` entirely and gives you raw bid responses to render however you choose.

### OpenRTB Bid Request

```ts
interface PrebidAuctionRequest {
  id: string;
  imp: Array<{
    id: string;
    banner: {
      format: Array<{ w: number; h: number }>;
    };
    ext: {
      prebid: {
        bidder: Record<string, Record<string, unknown>>;
      };
    };
  }>;
  app: {
    bundle: string;
    publisher: { id: string };
    storeurl?: string;
  };
  device: {
    ua: string;
    ip?: string;
    os: string;
    osv?: string;
  };
  regs?: {
    ext?: { gdpr?: number };
  };
  user?: {
    ext?: { consent?: string };
  };
  tmax: number;
}
```

### Sending an Auction Request

```ts
async function runPrebidAuction(): Promise<void> {
  const request: PrebidAuctionRequest = {
    id: `auction-${Date.now()}`,
    imp: [
      {
        id: 'banner-1',
        banner: {
          format: [{ w: 320, h: 50 }],
        },
        ext: {
          prebid: {
            bidder: {
              appnexus: { placement_id: 13144370 },
              ix: { siteId: '345678' },
            },
          },
        },
      },
      {
        id: 'banner-2',
        banner: {
          format: [{ w: 300, h: 250 }],
        },
        ext: {
          prebid: {
            bidder: {
              appnexus: { placement_id: 13144371 },
              openx: { unit: '540012345', delDomain: 'weatherbug-d.openx.net' },
            },
          },
        },
      },
    ],
    app: {
      bundle: 'com.aws.android',
      publisher: { id: 'weatherbug' },
      storeurl: 'https://play.google.com/store/apps/details?id=com.aws.android',
    },
    device: {
      ua: 'Mozilla/5.0 (Linux; Android 14; Pixel 8)',
      os: 'Android',
      osv: '14',
    },
    tmax: 1500,
  };

  try {
    const response = await fetch(
      'https://prebid.sellwild.com/openrtb2/auction',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
      },
    );

    if (!response.ok) {
      throw new Error(`Auction failed: ${response.status} ${response.statusText}`);
    }

    const auctionResult = await response.json();
    handleAuctionResponse(auctionResult);
  } catch (error) {
    console.error('[Prebid] Auction error:', error);
  }
}
```

### Parsing Bid Responses

The Prebid Server response follows the OpenRTB 2.6 `BidResponse` schema:

```ts
interface PrebidBidResponse {
  id: string;
  seatbid: Array<{
    bid: Array<{
      id: string;
      impid: string;       // Matches imp[].id from the request
      price: number;        // CPM in USD
      adm: string;          // Ad markup (HTML creative)
      adid: string;
      adomain: string[];    // Advertiser domains
      w: number;
      h: number;
      ext?: {
        prebid?: {
          type: string;     // "banner", "video", "native"
          targeting?: Record<string, string>;
        };
      };
    }>;
    seat: string;           // Bidder code (e.g., "appnexus")
  }>;
  cur: string;              // Currency code
  ext?: {
    responsetimemillis?: Record<string, number>; // Per-bidder latency
    errors?: Record<string, Array<{ code: number; message: string }>>;
  };
}

function handleAuctionResponse(response: PrebidBidResponse): void {
  if (!response.seatbid?.length) {
    console.log('[Prebid] No bids returned (no fill)');
    return;
  }

  // Collect all bids, grouped by impression ID
  const bidsByImp = new Map<string, Array<{ seat: string; price: number; adm: string }>>();

  for (const seatbid of response.seatbid) {
    for (const bid of seatbid.bid) {
      const existing = bidsByImp.get(bid.impid) ?? [];
      existing.push({
        seat: seatbid.seat,
        price: bid.price,
        adm: bid.adm,
      });
      bidsByImp.set(bid.impid, existing);
    }
  }

  // Select the winning bid for each impression (highest CPM)
  for (const [impId, bids] of bidsByImp) {
    const winner = bids.reduce((a, b) => (a.price > b.price ? a : b));
    console.log(
      `[Prebid] Winner for ${impId}: ${winner.seat} at $${winner.price.toFixed(2)} CPM`,
    );
    // Render winner.adm yourself (see "Rendering Winning Creatives" below).
  }

  // Log per-bidder latency for diagnostics
  if (response.ext?.responsetimemillis) {
    for (const [bidder, ms] of Object.entries(response.ext.responsetimemillis)) {
      console.log(`[Prebid] ${bidder} responded in ${ms}ms`);
    }
  }
}
```

### Rendering Winning Creatives

> **Note:** This is an advanced escape hatch for partners who want to render `adm` themselves instead of using `<SellwildBanner>`. It does not use Google Ad Manager or the SDK's native ad path -- you are responsible for impression tracking, viewability measurement, and click handling. The supported integration is `<SellwildBanner>`, which renders through `AdManagerBannerView` (iOS) or `AdManagerAdView` (Android) without a WebView.

If you choose to render the winning `adm` yourself, the simplest approach is to wrap the HTML creative in a WebView. You will need to install `react-native-webview` for this path.

```tsx
import React from 'react';
import { View } from 'react-native';
import { WebView } from 'react-native-webview';

interface WinningBidProps {
  adMarkup: string;
  width: number;
  height: number;
}

function WinningBidRenderer({ adMarkup, width, height }: WinningBidProps) {
  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { margin: 0; padding: 0; }
    html, body { width: ${width}px; height: ${height}px; overflow: hidden; }
  </style>
</head>
<body>${adMarkup}</body>
</html>`;

  return (
    <View style={{ width, height }}>
      <WebView
        source={{ html }}
        style={{ width, height }}
        javaScriptEnabled
        domStorageEnabled
        scrollEnabled={false}
        showsVerticalScrollIndicator={false}
        showsHorizontalScrollIndicator={false}
        originWhitelist={['*']}
      />
    </View>
  );
}
```

---

## Prebid Server Configuration

The `prebidServer` object on `SellwildConfig` controls server-side header bidding. When present, `<SellwildBanner>` bootstraps Prebid Mobile with these values and routes every auction through the specified Prebid Server instance.

### Configuration Object

```ts
interface PrebidServerConfig {
  /** Your Prebid Server account ID. */
  accountId: string;

  /**
   * Full URL to the Prebid Server auction endpoint.
   * Sellwild's managed instance: https://prebid.sellwild.com/openrtb2/auction
   */
  endpoint: string;

  /**
   * Bidder codes to route through Prebid Server.
   * Must match the adapter names configured on the server.
   */
  bidders: string[];

  /** Server-side auction timeout in milliseconds. Default: 1500. */
  timeout?: number;

  /**
   * Cookie sync endpoint. Derived from `endpoint` if omitted.
   * Only needed if your Prebid Server uses a non-standard path.
   */
  syncEndpoint?: string;
}
```

### Field Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `accountId` | `string` | Yes | -- | Your Prebid Server account ID |
| `endpoint` | `string` | Yes | -- | Full auction endpoint URL |
| `bidders` | `string[]` | Yes | -- | Bidder adapter codes for server-side routing |
| `timeout` | `number` | No | `1500` | Auction timeout in milliseconds |
| `syncEndpoint` | `string` | No | Derived | `/cookie_sync` URL override |

### Example

```ts
prebidServer: {
  accountId: 'weatherbug',
  endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
  bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
  timeout: 1500,
}
```

When `prebidServer` is set, `<SellwildBanner>`:

1. Bootstraps Prebid Mobile with `accountId`, `endpoint`, and `timeout` on first use.
2. Builds an OpenRTB 2.6 banner ad unit on every `load()`, including any passthrough bidder parameters from `SellwildConfig.remote`.
3. Posts the request to your Prebid Server endpoint and applies the winning bid's targeting keywords to the underlying GAM ad request.

---

## Metro Configuration

When developing against a local copy of the Sellwild SDK (e.g., the monorepo at `../sellwild-sdk`), configure Metro to resolve the local packages.

### metro.config.js

```js
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const path = require('path');

// Path to your local sellwild-sdk checkout
const sellwildSdkRoot = path.resolve(__dirname, '../sellwild-sdk');

const config = {
  watchFolders: [
    sellwildSdkRoot,
  ],
  resolver: {
    // Ensure Metro does not resolve duplicate React/React Native copies
    // from the SDK's own node_modules.
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
    ],
    // Redirect @sellwild/* imports to the local source
    extraNodeModules: {
      '@sellwild/sdk-core': path.resolve(sellwildSdkRoot, 'core'),
      '@sellwild/react-native-sdk': path.resolve(sellwildSdkRoot, 'react-native'),
    },
    // Block duplicate copies of these packages from the SDK workspace
    blockList: [
      new RegExp(
        path.resolve(sellwildSdkRoot, 'node_modules', 'react-native') + '/.*',
      ),
      new RegExp(
        path.resolve(sellwildSdkRoot, 'node_modules', 'react') + '/.*',
      ),
    ],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
```

### Common Metro issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Unable to resolve module @sellwild/sdk-core` | Missing `extraNodeModules` entry | Add the path mapping shown above |
| `Duplicate module name: react` | SDK workspace has its own `react` copy | Add `blockList` entries |
| `EMFILE: too many open files` | Watchman watching too many directories | Add `.watchmanconfig` with `"ignore_dirs"` |

---

## GDPR and Privacy

The Sellwild SDK supports GDPR consent signaling through the Prebid Server auction flow. When `prebidServer` is configured, Prebid Mobile attaches `regs.ext.gdpr` and `user.ext.consent` to every OpenRTB request, and the Google Mobile Ads SDK consumes the same TCF values for its own EU User Consent enforcement.

### Configuration

Pass GDPR parameters through the `SellwildConfig`:

```ts
const config: PartialSellwildConfig = {
  partnerCode: 'weatherbug',

  // GDPR consent signals
  gdprApplies: true,
  tcString: 'CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA',

  // IAB TCF version (2 = TCF v2.x)
  tcfVersion: 2,

  // GPP (Global Privacy Platform) support
  gppEnabled: true,

  prebidServer: {
    accountId: 'weatherbug',
    endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
    bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
    timeout: 1500,
  },
};
```

### How Consent Flows Through the SDK

1. The host app collects consent through its own CMP (OneTrust, Didomi, etc.). Per the IAB TCF v2.x specification, the CMP writes `IABTCF_TCString` and `IABTCF_gdprApplies` to `UserDefaults` (iOS) and `SharedPreferences` (Android).
2. Prebid Mobile reads those keys directly when building each OpenRTB request and attaches them as `regs.ext.gdpr` and `user.ext.consent`.
3. Prebid Server forwards the consent string to all bidders. Bidders that lack consent for required purposes are excluded from the auction.

You can also pass `gdprApplies` and `tcString` explicitly through `SellwildConfig` if your app does not write the standard IAB keys.

### Direct Auction Requests

When calling the Prebid Server auction endpoint directly via `fetch()`, include GDPR signals in the OpenRTB request body:

```ts
const request = {
  // ...imp, app, device...
  regs: {
    ext: { gdpr: 1 },
  },
  user: {
    ext: {
      consent: 'CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA',
    },
  },
  tmax: 1500,
};
```

### Important Notes

- **Prebid Server defaults to `gdpr=1`** (GDPR applies). If no consent string is present, all bidder calls are suppressed. Always explicitly set `gdprApplies: false` for non-GDPR traffic.
- **Native CMP bridging is not automatic.** If the host app uses a native CMP, it must read the consent string from `NSUserDefaults` (key: `IABTCF_TCString`) or `SharedPreferences` and pass it through `SellwildConfig`.
- **CCPA/US Privacy** is supported through the GPP framework when `gppEnabled: true`.

---

## TypeScript Reference

The SDK exports all types from `@sellwild/react-native-sdk` for convenience. The canonical definitions live in `@sellwild/sdk-core`.

### Exported Types

```ts
// Configuration
import type {
  SellwildConfig,
  PartialSellwildConfig,
  PrebidServerConfig,
} from '@sellwild/react-native-sdk';

// Listings
import type {
  SellwildListing,
  SellwildPhoto,
  SellwildUser,
  SellwildListingsResponse,
} from '@sellwild/react-native-sdk';

// Ads
import type {
  AdSize,            // '300x250' | '320x50' | '728x90' | '160x600' | '300x600' | '1x1'
  AdPlacement,
  AdPlacementType,   // 'banner_top' | 'banner_bottom' | 'inline' | 'interstitial'
} from '@sellwild/react-native-sdk';

// Component props
import type {
  SellwildWidgetProps,
  SellwildBannerProps,
  SellwildListingCardProps,
  UseSellwildListingsResult,
} from '@sellwild/react-native-sdk';
```

### Key Interfaces

#### SellwildConfig (abridged)

```ts
interface SellwildConfig {
  // Required
  partnerCode: string;

  // App identity
  appBundleId?: string;
  appStoreUrl?: string;

  // Prebid Server
  prebidServer?: PrebidServerConfig;

  // Display
  titleColor: string;
  priceColor: string;
  priceFontColor: string;
  fontSize: number;
  fontFamily: string;
  fontColor: string;
  cardWidth: string;
  cardHeight: string;
  colors: string[];

  // Ads
  bannerZid: number | string;
  gamTag: string;
  adRefreshMax: number;
  adRefreshMaxMobile: number;
  adRefreshInterval: number;

  // Privacy
  gppEnabled: boolean;
  tcfVersion: number;

  // Debug
  debug: boolean;
}
```

#### SellwildListing

```ts
interface SellwildListing {
  id: string;
  status: string;
  title: string;
  text: string;
  url: string;
  categoryId: string;
  categoryGroupId: string;
  currency: string;
  price: string;
  strikePrice: string;
  has_photo: boolean;
  photo_count: number;
  photos: SellwildPhoto[];
  createdDate: string;
  videoUrl: string;
  shippable: string;
  listingType: string;
  dataSourceId: string;
  user: SellwildUser;
  distance?: number;
}
```

#### SellwildPhoto

```ts
interface SellwildPhoto {
  url: string;
  thumbUrl: string;
  background?: string;
}
```

#### SellwildUser

```ts
interface SellwildUser {
  id: string;
  firstName: string;
  lastName: string;
  username: string;
  membershipType: string;
  trustLevel: string;
  has_photo: string;
  photos: SellwildPhoto[];
  isPhoneVerified: boolean;
}
```

### Utility Functions

```ts
import {
  buildConfig,
  currencyToSymbol,
  type SellwildConfig,
} from '@sellwild/react-native-sdk';

// Build a full SellwildConfig from partial input with defaults applied
const config: SellwildConfig = buildConfig({
  partnerCode: 'weatherbug',
});

// Convert ISO currency code to symbol
currencyToSymbol('USD'); // '$'
currencyToSymbol('EUR'); // '\u20ac'
currencyToSymbol('GBP'); // '\u00a3'
```

---

## Troubleshooting

### Metro bundler cannot resolve `@sellwild/sdk-core`

**Symptom:** `error: Error: Unable to resolve module @sellwild/sdk-core`

**Cause:** The core package is not installed or Metro cannot locate it.

**Fix:**

```bash
# Verify the package is installed
npm ls @sellwild/sdk-core

# If missing, reinstall
npm install @sellwild/react-native-sdk

# Clear Metro cache and restart
npx react-native start --reset-cache
```

If developing against a local SDK checkout, ensure `extraNodeModules` is configured in `metro.config.js` (see [Metro Configuration](#metro-configuration)).

---

### `pod install` fails on iOS

**Symptom:** `[!] CocoaPods could not find compatible versions for pod "SellwildSDK"` or `"react-native-webview"`.

**Fix:**

```bash
cd ios
pod deintegrate
pod cache clean --all
pod install --repo-update
cd ..
```

If using Xcode 15+, ensure your deployment target is iOS 13.0 or later in `ios/Podfile`:

```ruby
platform :ios, '13.0'
```

---

### App Transport Security (ATS) blocks network requests

**Symptom:** iOS console shows `App Transport Security has blocked a cleartext HTTP resource load`.

**Cause:** The SDK endpoints use HTTPS, but a misconfigured proxy or redirect may downgrade to HTTP.

**Fix:** Add the ATS exception domains listed in [iOS Configuration](#ios-configuration). For development with a local Prebid Server over HTTP, temporarily allow arbitrary loads:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

Remove this before submitting to the App Store.

---

### No fill -- banner renders blank

**Symptom:** `<SellwildBanner>` mounts but no ad creative appears, or `onAdFailed` fires with a "no fill" reason.

**Cause:** No bidder returned a bid above floor price, the configured GAM ad unit is empty, or the bidder configuration is incorrect.

**Diagnostic steps:**

1. Enable debug mode:

```ts
const config = buildConfig({
  partnerCode: 'weatherbug',
  debug: true,
});
```

2. Inspect Prebid Mobile and GMA logs natively. On iOS, run the app under Xcode and filter the console by `Sellwild`, `PrebidMobile`, and `Google`. On Android, run `adb logcat` and filter by the same tags.

3. Verify the Prebid Server is responding:

```bash
curl -X POST https://prebid.sellwild.com/openrtb2/auction \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-1",
    "imp": [{
      "id": "imp-1",
      "banner": { "format": [{ "w": 320, "h": 50 }] },
      "ext": {
        "prebid": {
          "bidder": {
            "appnexus": { "placement_id": 13144370 }
          }
        }
      }
    }],
    "app": {
      "bundle": "com.aws.android",
      "publisher": { "id": "weatherbug" }
    },
    "tmax": 1500
  }'
```

4. Check the response for `ext.errors` or `ext.responsetimemillis` to identify bidder-level issues.

---

### Banner re-mounts on every parent render

**Symptom:** The banner resets or re-runs the auction when unrelated state changes in the parent component.

**Cause:** A new `config` object reference is created on each render, causing the native bridge to tear down and rebuild the underlying ad view.

**Fix:** Memoize the `config` object so it has a stable identity across renders:

```tsx
const sdkConfig = useMemo(
  () => buildConfig({ partnerCode: 'weatherbug' }),
  [],
);
```

---

### Android cleartext traffic error

**Symptom:** `java.io.IOException: Cleartext HTTP traffic to prebid.sellwild.com not permitted`

**Cause:** Android 9+ blocks cleartext HTTP by default. The Sellwild production endpoints use HTTPS, so this error indicates either a redirect issue or a local development server.

**Fix:** See [Android Configuration](#android-configuration) for network security config setup.

---

### `useSellwildListings` refresh returns stale data

**Symptom:** Calling `refresh()` does not fetch new listings.

**Cause:** This was a known issue in earlier SDK versions where the listing cache was not cleared on refresh. Current versions call `clearListingCache()` when `refreshKey > 0`.

**Fix:** Update to the latest version of `@sellwild/react-native-sdk`:

```bash
npm install @sellwild/react-native-sdk@latest
```

---

## Further Reading

- [Prebid Server OpenRTB Auction Endpoint](https://docs.prebid.org/prebid-server/endpoints/openrtb2/pbs-endpoint-auction.html)
- [Prebid.js S2S Module Documentation](https://docs.prebid.org/dev-docs/modules/prebidServer.html)
- [OpenRTB 2.6 Specification](https://www.iab.com/wp-content/uploads/2022/04/OpenRTB-2-6_FINAL.pdf)
- [IAB TCF v2.2](https://iabeurope.eu/tcf-2-0/)
- [Prebid Server Configuration](/guide/prebid-server)
