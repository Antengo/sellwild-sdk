# Configuration Reference

Complete reference for all Sellwild SDK configuration options. These fields apply across all platforms (iOS, Android, React Native, Flutter) unless noted otherwise.

---

## Table of Contents

1. [SellwildConfig](#sellwildconfig)
2. [PrebidServerConfig](#prebidserverconfig)
3. [Ad Size Reference](#ad-size-reference)
4. [Ad Refresh Configuration](#ad-refresh-configuration)
5. [Remote Config](#remote-config)
6. [Debug Mode](#debug-mode)

---

## SellwildConfig

The primary configuration object passed to all SDK components. Every ad view, widget, and API client reads from this object.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `partnerCode` | `String` | Your Sellwild partner identifier. Used as `ortb2.app.publisher.id` in bid requests. |
| `listingsUrl` | `String` | Full URL to the Sellwild listings API endpoint for your partner account. |

### App Identity

These fields ensure bid requests are classified as in-app traffic. Without them, DSPs treat impressions as anonymous web traffic and most will not bid.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `appBundleId` | `String?` | `null` | App bundle identifier (e.g., `"com.example.myapp"`). Sent as `ortb2.app.bundle`. |
| `appStoreUrl` | `String?` | `null` | App store listing URL. Sent as `ortb2.app.storeurl`. Required for app-ads.txt verification. |
| `apiBaseUrl` | `String` | `"https://api.sellwild.com"` | Base URL for Sellwild API calls. Override for staging environments. |

### Prebid Server

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `prebidServer` | `PrebidServerConfig?` | `null` | Server-side header bidding configuration. See [PrebidServerConfig](#prebidserverconfig). When `null`, Prebid.js runs client-side adapters in the WebView. |
| `prebidSrc` | `String?` | `null` | Custom Prebid.js bundle URL. When `null`, the SDK uses the default CDN-hosted build. |

### Display Customization

These fields control the appearance of the listing widget and listing cards.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `title` | `String?` | `null` | Widget header title text. |
| `titleColor` | `String` | `"#000000"` | Widget title color (CSS hex). |
| `titleSize` | `Int` | `16` | Widget title font size in pixels. |
| `linkText` | `String?` | `"View all"` | Text for the "view all" link in the widget header. |
| `linkColor` | `String` | `"#0066cc"` | Link text color (CSS hex). |
| `buyNowText` | `String?` | `"Buy now"` | Call-to-action button text. |
| `fontSize` | `Int` | `13` | Listing title font size in pixels. |
| `fontFamily` | `String` | `""` | CSS font family for listing text. Empty string uses the system default. |
| `fontColor` | `String` | `"#ffffff"` | Listing title font color (CSS hex). |
| `priceColor` | `String` | `"#333333"` | Price badge background color (CSS hex). |
| `priceFontColor` | `String` | `"#ffffff"` | Price badge text color (CSS hex). |
| `marginBottom` | `Int` | `10` | Bottom margin in pixels. |
| `colors` | `List<String>` | `["#333333"]` | Theme accent colors (CSS hex values). |
| `overlayTitle` | `Bool` | `false` | Overlay listing title on top of the listing image. |
| `cardWidth` | `String` | `""` | Listing card width (CSS value). Empty string uses the default. |
| `cardHeight` | `String` | `""` | Listing card height (CSS value). Empty string uses the default. |

### Watermark

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `watermark` | `Bool` | `false` | Show a watermark on the widget. |
| `watermarkTitle` | `String` | `"Powered by Sellwild"` | Watermark text content. |

### Ad Zone IDs

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `bannerZid` | `String?` | `null` | Zone ID for the top banner placement. |
| `bottomBannerZid` | `String?` | `null` | Zone ID for the bottom banner placement. |
| `mobileBannerZid` | `String?` | `null` | Mobile-specific banner zone ID (overrides `bannerZid` on mobile). |
| `mobileZids` | `List<String>` | `[]` | Additional mobile zone IDs for multi-slot layouts. |

### Ad Display Control

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `gamTag` | `String?` | `null` | Google Ad Manager ad unit path (e.g., `"/12345678/weatherbug_mrec"`). Enables GAM as the primary ad server with Prebid as header bidding. |
| `gptProxyUrl` | `String?` | `null` | Proxy URL for the GPT (Google Publisher Tag) script. Use when direct GPT loading is blocked. |
| `disableGpt` | `Bool` | `false` | Disable Google Publisher Tag entirely. |
| `adDisableDisplay` | `Bool` | `false` | Disable all display ad rendering. Listings still load. |
| `hideBannerTop` | `Bool` | `false` | Hide the top banner ad placement in the widget. |
| `hideBannerBottom` | `Bool` | `false` | Hide the bottom banner ad placement in the widget. |
| `adType` | `String?` | `null` | Ad system selection. Defaults to `"PrebidOnly"` when `null`. |
| `floorMultiplier` | `Double` | `1.0` | Multiplier applied to bid floor prices. Values above `1.0` raise floors. |

### Ad Refresh

See [Ad Refresh Configuration](#ad-refresh-configuration) for detailed behavior.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `adRefreshMax` | `Int` | `0` | Maximum ad refresh cycles (all platforms). `0` = disabled. |
| `adRefreshMaxMobile` | `Int` | `0` | Maximum ad refresh cycles on mobile. Overrides `adRefreshMax` when nonzero. |
| `adRefreshInterval` | `Duration/Number` | `30 seconds` | Time between refresh cycles. iOS uses `TimeInterval` (seconds), Android uses `Long` (milliseconds), RN/Flutter use seconds. |
| `maxFailedAuctions` | `Int` | `3` | Stop refreshing after N consecutive no-fill auctions. |

### Privacy and Consent

See [Privacy & Consent](/guide/privacy) for detailed usage.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `gppEnabled` | `Bool` | `false` | Enable IAB Global Privacy Platform support. |
| `tcfVersion` | `Int` | `0` | TCF version. `0` = disabled, `2` = TCF v2.x. |
| `gdprApplies` | `Bool?` | `null` | Whether GDPR applies. `null` = determined by Prebid Server. RN/Flutter only. |
| `tcString` | `String?` | `null` | TCF v2 consent string. RN/Flutter only. |
| `iabCats` | `List<String>` | `[]` | IAB content category codes for brand safety (e.g., `["IAB15", "IAB15-10"]`). |

### Third-Party Integrations

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `boltive` | `Bool` | `false` | Enable Boltive ad quality monitoring. |
| `boltiveClientId` | `String` | `""` | Your Boltive client identifier. |
| `lotame` | `Bool` | `false` | Enable Lotame data enrichment. |

### Debug

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `debug` | `Bool` | `false` | Enable verbose debug logging. See [Debug Mode](#debug-mode). |

---

## PrebidServerConfig

Controls server-side header bidding through Prebid Server. Set this on `SellwildConfig.prebidServer` to route all bid requests through the managed Prebid Server instance.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `accountId` | `String` | Yes | -- | Your Prebid Server account ID. Typically matches your partner code. |
| `endpoint` | `String` | Yes | -- | Full URL to the OpenRTB 2.6 auction endpoint. Use `"https://prebid.sellwild.com/openrtb2/auction"`. |
| `bidders` | `List<String>` | Yes | -- | SSP bidder adapter codes to include in the server-side auction. Must match adapters configured on the Prebid Server instance. |
| `timeout` | `Int` | No | `1500` | Maximum time in milliseconds the server waits for SSP responses before closing the auction. |
| `syncEndpoint` | `String?` | No | `null` | Cookie sync endpoint URL. Derived from `endpoint` if omitted (replaces `/openrtb2/auction` with `/cookie_sync`). |

### Example

```swift
// iOS
config.prebidServer = PrebidServerConfig(
    accountId: "weatherbug-prod",
    endpoint: "https://prebid.sellwild.com/openrtb2/auction",
    bidders: ["appnexus", "rubicon", "ix", "openx"],
    timeout: 1500
)
```

```kotlin
// Android
prebidServer = PrebidServerConfig(
    accountId = "sellwild",
    endpoint = "https://prebid.sellwild.com/openrtb2/auction",
    bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx"),
    timeout = 1500
)
```

```ts
// React Native / Flutter
prebidServer: {
  accountId: 'weatherbug',
  endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
  bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
  timeout: 1500,
}
```

### What Gets Injected

When `prebidServer` is set, the SDK injects the following into the WebView before Prebid.js loads:

```js
pbjs.setConfig({
    ortb2: {
        app: {
            bundle: "com.example.myapp",
            storeurl: "https://play.google.com/store/apps/details?id=com.example.myapp",
            publisher: { id: "weatherbug" }
        }
    },
    userSync: {
        filterSettings: {
            iframe: { bidders: "*", filter: "exclude" }
        },
        syncDelay: 5000
    },
    s2sConfig: {
        accountId: "weatherbug-prod",
        bidders: ["appnexus", "rubicon", "ix", "openx"],
        timeout: 1500,
        adapter: "prebidServer",
        endpoint: {
            p1Consent: "https://prebid.sellwild.com/openrtb2/auction",
            noP1Consent: "https://prebid.sellwild.com/openrtb2/auction"
        }
    }
});
```

### Available Bidders

The following SSPs are configured on `prebid.sellwild.com`. Use the bidder code in your `bidders` list.

| SSP | Bidder Code |
|-----|------------|
| AppNexus / Xandr | `appnexus` |
| PubMatic | `pubmatic` |
| Index Exchange | `ix` |
| Rubicon / Magnite | `rubicon` |
| OpenX | `openx` |
| TripleLift | `triplelift` |
| Sharethrough | `sharethrough` |
| InMobi | `inmobi` |
| Smaato | `smaato` |
| Yieldmo | `yieldmo` |
| 33Across | `33across` |
| Sovrn | `sovrn` |
| GumGum | `gumgum` |
| Unruly | `unruly` |
| Criteo | `criteo` |
| Media.net | `medianet` |
| Amazon TAM | `amazontam` |

Contact sdk@sellwild.com to enable additional bidders for your account.

---

## Ad Size Reference

Predefined ad dimensions for banner ad units. Use these values when constructing `SellwildAdView` or `SellwildBanner`.

| Enum / String | Width | Height | IAB Name | Recommended Placement |
|--------------|-------|--------|----------|----------------------|
| `.banner320x50` / `"320x50"` | 320 | 50 | Mobile Banner | Top or bottom of screen |
| `.mrec300x250` / `"300x250"` | 300 | 250 | Medium Rectangle (MREC) | In-feed, between content sections |
| `.leaderboard728x90` / `"728x90"` | 728 | 90 | Leaderboard | Tablet top or bottom |
| `.halfPage300x600` / `"300x600"` | 300 | 600 | Half Page | Sidebar (tablet landscape) |
| `.wideSkyscraper160x600` / `"160x600"` | 160 | 600 | Wide Skyscraper | Sidebar (tablet landscape) |

### Platform-Specific Names

| Platform | Type Name | Values |
|----------|-----------|--------|
| iOS (Swift) | `AdSize` enum | `.banner320x50`, `.mrec300x250`, `.leaderboard728x90`, `.halfPage300x600`, `.wideSkyscraper160x600` |
| Android (Kotlin) | `AdSize` enum | `BANNER_320x50`, `MREC_300x250`, `LEADERBOARD_728x90`, `HALF_PAGE_300x600`, `WIDE_SKYSCRAPER_160x600` |
| React Native (TS) | `AdSize` string literal | `"320x50"`, `"300x250"`, `"728x90"`, `"160x600"`, `"300x600"`, `"1x1"` |
| Flutter (Dart) | `SellwildAdSize` enum | `banner320x50`, `mrec300x250`, `leaderboard728x90`, `halfPage300x600`, `wideSkyscraper160x600` |

### Choosing Ad Sizes

| Device | Recommended Sizes |
|--------|-------------------|
| Phone (portrait) | `320x50` (banner), `300x250` (MREC) |
| Phone (landscape) | `320x50` (banner), `300x250` (MREC) |
| Tablet (portrait) | `728x90` (leaderboard), `300x250` (MREC) |
| Tablet (landscape) | `728x90` (leaderboard), `300x600` (half page) |

---

## Ad Refresh Configuration

The SDK supports automatic ad refresh -- after a successful impression, the ad slot re-auctions after a configurable interval.

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `adRefreshMaxMobile` | `Int` | `0` (disabled) | Maximum number of refresh cycles per ad view instance on mobile. Set to `0` to disable ad refresh. |
| `adRefreshMax` | `Int` | `0` | Maximum refresh cycles for desktop/tablet widget layouts. `adRefreshMaxMobile` takes precedence on mobile when nonzero. |
| `adRefreshInterval` | `Duration` | `30 seconds` | Time between refresh cycles. IAB guidelines recommend a minimum of 30 seconds. |
| `maxFailedAuctions` | `Int` | `3` | Number of consecutive no-fill auctions before the SDK stops refreshing that ad slot. |

### Platform-Specific Types

| Platform | `adRefreshInterval` Type | Example |
|----------|-------------------------|---------|
| iOS | `TimeInterval` (seconds, `Double`) | `config.adRefreshInterval = 30.0` |
| Android | `Long` (milliseconds) | `adRefreshIntervalMs = 30_000L` |
| React Native | `number` (seconds) | `adRefreshInterval: 30` |
| Flutter | `Duration` | `adRefreshInterval: Duration(seconds: 30)` |

### Behavior

1. The refresh timer starts after the first `onAdImpression` callback fires.
2. Each cycle triggers a new Prebid Server auction for the same ad slot.
3. Calling `pause()` cancels the pending refresh timer. Calling `resume()` does not restart it -- the next impression triggers a new cycle.
4. Calling `load()` resets the internal refresh counter to zero.
5. When `maxFailedAuctions` consecutive auctions return no fill, refresh stops for that ad slot.
6. Each `SellwildAdView` / `SellwildBanner` instance has its own independent refresh counter.

### Example

```swift
// iOS -- refresh every 45 seconds, up to 8 times
config.adRefreshMaxMobile = 8
config.adRefreshInterval = 45.0
config.maxFailedAuctions = 5
```

```kotlin
// Android -- refresh every 30 seconds, up to 10 times
config = SellwildConfig(
    partnerCode = "weatherbug",
    listingsUrl = "...",
    adRefreshMaxMobile = 10,
    adRefreshIntervalMs = 30_000L,
    maxFailedAuctions = 3,
    // ...
)
```

---

## Remote Config

The SDK can fetch its config from the Sellwild CDN at app launch instead of (or in addition to) hardcoding settings in your binary. This lets your Sellwild contact change ad zones, refresh intervals, geo blocks, and waterfall partners without an app update.

### URL pattern

```
https://widget.sellwild.com/app/{partnerCode}/{slug}.json
```

Your Sellwild contact provides the `slug`. The JSON uses CONSTANT_CASE keys (e.g. `AD_REFRESH_MAX`, `HIDE_BANNER_TOP`) which the SDK maps to the camelCase fields documented above.

### Merge order

1. SDK defaults
2. Static partial config you pass in
3. Remote CDN config (overrides everything above)

### Failure handling

If the fetch fails (network error, timeout, 404), the SDK falls back silently to your static config. Remote config is **additive, never blocking** — your app always renders, even with the CDN offline.

### Usage (React Native / TypeScript)

```ts
import { buildConfigWithRemote } from '@sellwild/react-native-sdk';

const config = await buildConfigWithRemote(
  { partnerCode: 'weatherbug', listingsUrl: '...' },
  'weatherbug-main',
);
```

See the [API Reference](./api-reference#buildconfigwithremote) for full options.

### Native platforms (iOS / Android / Flutter)

iOS, Android, and Flutter consume the same remote config JSON, but you fetch and apply it at app launch. The recipes below match the TypeScript merge semantics:

- **Merge order:** SDK defaults → your static config → remote CDN config (remote wins)
- **Failure handling:** any network error, timeout, or non-2xx response falls back silently to your static config so the app still renders
- **Timeout:** 5 seconds (recommended)
- **Caching:** the recipes fetch once per app launch — call again on app foreground if you want a refresh

The CDN JSON uses CONSTANT_CASE keys (e.g. `AD_REFRESH_MAX`, `HIDE_BANNER_TOP`, `MOBILE_ZID`). Each recipe includes the full key map.

#### iOS (Swift)

```swift
import Foundation
import SellwildSDK

enum SellwildRemoteConfig {

    /// Fetch the partner's remote config from the Sellwild CDN, merge it onto a
    /// static base config, and return a fully-populated `SellwildConfig`.
    /// Falls back silently to `base` on any network/parse failure.
    static func build(
        base: SellwildConfig,
        slug: String,
        timeout: TimeInterval = 5.0
    ) async -> SellwildConfig {
        let url = URL(string:
            "https://widget.sellwild.com/app/\(base.partnerCode)/\(slug).json"
        )!

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let raw = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else { return base }
            return apply(raw, to: base)
        } catch {
            return base
        }
    }

    /// Maps CONSTANT_CASE CDN keys onto the corresponding `SellwildConfig` fields.
    private static func apply(
        _ raw: [String: Any],
        to base: SellwildConfig
    ) -> SellwildConfig {
        var c = base

        // Identity
        if let v = raw["CODE"]      as? String { c.partnerCode = v }
        if let v = raw["SLUG"]      as? String { c.slug = v }
        if let v = raw["NAME"]      as? String { c.name = v }
        if let v = raw["LISTINGS"]  as? String { c.listingsUrl = v }

        // Display
        if let v = raw["TITLE"]            as? String   { c.title = v }
        if let v = raw["LINK_TEXT"]        as? String   { c.linkText = v }
        if let v = raw["BUY_NOW_TEXT"]     as? String   { c.buyNowText = v }
        if let v = raw["TITLE_COLOR"]      as? String   { c.titleColor = v }
        if let v = raw["LINK_COLOR"]       as? String   { c.linkColor = v }
        if let v = raw["FONT_COLOR"]       as? String   { c.fontColor = v }
        if let v = raw["PRICE_COLOR"]      as? String   { c.priceColor = v }
        if let v = raw["PRICE_FONT_COLOR"] as? String   { c.priceFontColor = v }
        if let v = raw["MARGIN_BOTTOM"]    as? Int      { c.marginBottom = v }
        if let v = raw["COLORS"]           as? [String] { c.colors = v }
        if let v = raw["OVERLAY_TITLE"]    as? Bool     { c.overlayTitle = v }
        if let v = raw["WATERMARK"]        as? Bool     { c.watermark = v }
        if let v = raw["WATERMARK_TITLE"]  as? String   { c.watermarkTitle = v }

        // Ad zones
        if let v = raw["BANNER_ZID"]         as? String   { c.bannerZid = v }
        if let v = raw["BOTTOM_BANNER_ZID"]  as? String   { c.bottomBannerZid = v }
        if let v = raw["MOBILE_BANNER_ZID"]  as? String   { c.mobileBannerZid = v }
        if let v = raw["MOBILE_ZID"]         as? [String] { c.mobileZids = v }
        if let v = raw["HIDE_BANNER_TOP"]    as? Bool     { c.hideBannerTop = v }
        if let v = raw["HIDE_BANNER_BOTTOM"] as? Bool     { c.hideBannerBottom = v }
        if let v = raw["GAM"]                as? String   { c.gamTag = v }
        if let v = raw["DISABLE_GPT"]        as? Bool     { c.disableGpt = v }
        if let v = raw["AD_DISABLE_DISPLAY"] as? Bool     { c.adDisableDisplay = v }

        // Refresh
        if let v = raw["AD_REFRESH_MAX"]        as? Int { c.adRefreshMax = v }
        if let v = raw["AD_REFRESH_MAX_MOBILE"] as? Int { c.adRefreshMaxMobile = v }
        if let v = raw["AD_REFRESH_INTERVAL"]   as? Double {
            c.adRefreshInterval = v
        }
        if let v = raw["MAX_FAILED_AUCTIONS"]   as? Int { c.maxFailedAuctions = v }

        // Compliance
        if let v = raw["GPP_ENABLED"] as? Bool     { c.gppEnabled = v }
        if let v = raw["TCF_VERSION"] as? Int      { c.tcfVersion = v }
        if let v = raw["IAB_CATS"]    as? [String] { c.iabCats = v }

        // Mobile ad controls
        if let v = raw["ENABLE_INTERSTITIAL"]         as? Bool { c.enableInterstitial = v }
        if let v = raw["ENABLE_FULLSCREEN_VIDEO"]     as? Bool { c.enableFullscreenVideo = v }
        if let v = raw["INTERSTITIALS_PER_SESSION"]   as? Int  { c.interstitialsPerSession = v }
        if let v = raw["VIDEO_TAKEOVERS_PER_SESSION"] as? Int  { c.videoTakeoversPerSession = v }

        // Third-party
        if let v = raw["BOLTIVE"]           as? Bool   { c.boltive = v }
        if let v = raw["BOLTIVE_CLIENT_ID"] as? String { c.boltiveClientId = v }
        if let v = raw["LOTAME"]            as? Bool   { c.lotame = v }

        return c
    }
}
```

Usage:

```swift
// At app launch (e.g. in your AppDelegate / @main App)
Task {
    let base = SellwildConfig(
        partnerCode: "weatherbug",
        listingsUrl: "https://api.sellwild.com/widget/listings?partner=weatherbug"
    )
    let config = await SellwildRemoteConfig.build(base: base, slug: "weatherbug-main")
    // Hand `config` to your SellwildAdView / SellwildAdBanner / SellwildWidget.
}
```

#### Android (Kotlin)

```kotlin
package com.example.app

import com.sellwild.sdk.SellwildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object SellwildRemoteConfig {

    /**
     * Fetch the partner's remote config from the Sellwild CDN, merge it onto a
     * static base config, and return a fully-populated [SellwildConfig].
     * Falls back silently to [base] on any network/parse failure.
     */
    suspend fun build(
        base: SellwildConfig,
        slug: String,
        timeoutMs: Long = 5_000L,
    ): SellwildConfig = withContext(Dispatchers.IO) {
        val raw = withTimeoutOrNull(timeoutMs) { fetch(base.partnerCode, slug) }
        if (raw == null) base else apply(raw, base)
    }

    private fun fetch(partnerCode: String, slug: String): JSONObject? {
        val url = URL("https://widget.sellwild.com/app/$partnerCode/$slug.json")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 5_000
            readTimeout = 5_000
            requestMethod = "GET"
        }
        return try {
            if (conn.responseCode !in 200..299) return null
            JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
        } catch (_: Exception) {
            null
        } finally {
            conn.disconnect()
        }
    }

    private fun apply(r: JSONObject, base: SellwildConfig): SellwildConfig {
        fun str(k: String) = if (r.has(k) && !r.isNull(k)) r.optString(k) else null
        fun int(k: String) = if (r.has(k) && !r.isNull(k)) r.optInt(k) else null
        fun bool(k: String) = if (r.has(k) && !r.isNull(k)) r.optBoolean(k) else null
        fun strs(k: String): List<String>? {
            val a = r.optJSONArray(k) ?: return null
            return List(a.length()) { a.optString(it) }
        }

        return base.copy(
            // Identity
            partnerCode      = str("CODE")             ?: base.partnerCode,
            slug             = str("SLUG")             ?: base.slug,
            name             = str("NAME")             ?: base.name,
            listingsUrl      = str("LISTINGS")         ?: base.listingsUrl,

            // Display
            title            = str("TITLE")            ?: base.title,
            linkText         = str("LINK_TEXT")        ?: base.linkText,
            buyNowText       = str("BUY_NOW_TEXT")     ?: base.buyNowText,
            titleColor       = str("TITLE_COLOR")      ?: base.titleColor,
            linkColor        = str("LINK_COLOR")       ?: base.linkColor,
            fontColor        = str("FONT_COLOR")       ?: base.fontColor,
            priceColor       = str("PRICE_COLOR")      ?: base.priceColor,
            priceFontColor   = str("PRICE_FONT_COLOR") ?: base.priceFontColor,
            marginBottom     = int("MARGIN_BOTTOM")    ?: base.marginBottom,
            colors           = strs("COLORS")          ?: base.colors,
            overlayTitle     = bool("OVERLAY_TITLE")   ?: base.overlayTitle,
            watermark        = bool("WATERMARK")       ?: base.watermark,
            watermarkTitle   = str("WATERMARK_TITLE")  ?: base.watermarkTitle,

            // Ad zones
            bannerZid        = str("BANNER_ZID")         ?: base.bannerZid,
            bottomBannerZid  = str("BOTTOM_BANNER_ZID")  ?: base.bottomBannerZid,
            mobileBannerZid  = str("MOBILE_BANNER_ZID")  ?: base.mobileBannerZid,
            mobileZids       = strs("MOBILE_ZID")        ?: base.mobileZids,
            hideBannerTop    = bool("HIDE_BANNER_TOP")    ?: base.hideBannerTop,
            hideBannerBottom = bool("HIDE_BANNER_BOTTOM") ?: base.hideBannerBottom,
            gamTag           = str("GAM")                 ?: base.gamTag,
            disableGpt       = bool("DISABLE_GPT")        ?: base.disableGpt,
            adDisableDisplay = bool("AD_DISABLE_DISPLAY") ?: base.adDisableDisplay,

            // Refresh — note: Android uses milliseconds (Long)
            adRefreshMax        = int("AD_REFRESH_MAX")        ?: base.adRefreshMax,
            adRefreshMaxMobile  = int("AD_REFRESH_MAX_MOBILE") ?: base.adRefreshMaxMobile,
            adRefreshIntervalMs = (int("AD_REFRESH_INTERVAL")?.toLong()?.times(1000L))
                                   ?: base.adRefreshIntervalMs,
            maxFailedAuctions   = int("MAX_FAILED_AUCTIONS")   ?: base.maxFailedAuctions,

            // Compliance
            gppEnabled = bool("GPP_ENABLED") ?: base.gppEnabled,
            tcfVersion = int("TCF_VERSION")  ?: base.tcfVersion,
            iabCats    = strs("IAB_CATS")    ?: base.iabCats,

            // Mobile ad controls
            enableInterstitial       = bool("ENABLE_INTERSTITIAL")       ?: base.enableInterstitial,
            enableFullscreenVideo    = bool("ENABLE_FULLSCREEN_VIDEO")   ?: base.enableFullscreenVideo,
            interstitialsPerSession  = int("INTERSTITIALS_PER_SESSION")  ?: base.interstitialsPerSession,
            videoTakeoversPerSession = int("VIDEO_TAKEOVERS_PER_SESSION") ?: base.videoTakeoversPerSession,

            // Third-party
            boltive          = bool("BOLTIVE")           ?: base.boltive,
            boltiveClientId  = str("BOLTIVE_CLIENT_ID")  ?: base.boltiveClientId,
            lotame           = bool("LOTAME")            ?: base.lotame,
        )
    }
}
```

Usage:

```kotlin
// At app launch (e.g. in your Application.onCreate or first Activity)
lifecycleScope.launch {
    val base = SellwildConfig(
        partnerCode = "weatherbug",
        listingsUrl = "https://api.sellwild.com/widget/listings?partner=weatherbug",
    )
    val config = SellwildRemoteConfig.build(base, slug = "weatherbug-main")
    // Hand `config` to your SellwildAdView / SellwildWidgetView.
}
```

> Android `adRefreshIntervalMs` is in **milliseconds**, while the CDN value `AD_REFRESH_INTERVAL` is in **seconds** (matching the JS convention). The recipe multiplies by 1000.

#### Flutter (Dart)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sellwild_sdk/sellwild_sdk.dart';

class SellwildRemoteConfig {
  /// Fetch the partner's remote config from the Sellwild CDN, merge it onto a
  /// static base config, and return a fully-populated [SellwildConfig].
  /// Falls back silently to [base] on any network/parse failure.
  static Future<SellwildConfig> build({
    required SellwildConfig base,
    required String slug,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final uri = Uri.parse(
        'https://widget.sellwild.com/app/${base.partnerCode}/$slug.json',
      );
      final res = await http.get(uri).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return base;
      final raw = jsonDecode(res.body) as Map<String, dynamic>;
      return _apply(raw, base);
    } catch (_) {
      return base;
    }
  }

  static SellwildConfig _apply(Map<String, dynamic> r, SellwildConfig b) {
    String?       s(String k) => r[k] is String ? r[k] as String : null;
    int?          i(String k) => r[k] is num ? (r[k] as num).toInt() : null;
    bool?         z(String k) => r[k] is bool ? r[k] as bool : null;
    List<String>? a(String k) =>
        r[k] is List ? (r[k] as List).map((e) => e.toString()).toList() : null;

    return SellwildConfig(
      // Identity
      partnerCode:      s('CODE')      ?? b.partnerCode,
      slug:             s('SLUG')      ?? b.slug,
      name:             s('NAME')      ?? b.name,
      listingsUrl:      s('LISTINGS')  ?? b.listingsUrl,
      apiBaseUrl:       b.apiBaseUrl,

      // Display
      title:            s('TITLE')             ?? b.title,
      linkText:         s('LINK_TEXT')         ?? b.linkText,
      buyNowText:       s('BUY_NOW_TEXT')      ?? b.buyNowText,
      titleColor:       s('TITLE_COLOR')       ?? b.titleColor,
      linkColor:        s('LINK_COLOR')        ?? b.linkColor,
      fontColor:        s('FONT_COLOR')        ?? b.fontColor,
      priceColor:       s('PRICE_COLOR')       ?? b.priceColor,
      priceFontColor:   s('PRICE_FONT_COLOR')  ?? b.priceFontColor,
      marginBottom:     i('MARGIN_BOTTOM')     ?? b.marginBottom,
      colors:           a('COLORS')            ?? b.colors,
      overlayTitle:     z('OVERLAY_TITLE')     ?? b.overlayTitle,
      watermark:        z('WATERMARK')         ?? b.watermark,
      watermarkTitle:   s('WATERMARK_TITLE')   ?? b.watermarkTitle,

      // Ad zones
      bannerZid:        s('BANNER_ZID')         ?? b.bannerZid,
      bottomBannerZid:  s('BOTTOM_BANNER_ZID')  ?? b.bottomBannerZid,
      mobileBannerZid:  s('MOBILE_BANNER_ZID')  ?? b.mobileBannerZid,
      mobileZids:       a('MOBILE_ZID')         ?? b.mobileZids,
      hideBannerTop:    z('HIDE_BANNER_TOP')    ?? b.hideBannerTop,
      hideBannerBottom: z('HIDE_BANNER_BOTTOM') ?? b.hideBannerBottom,
      gamTag:           s('GAM')                ?? b.gamTag,
      disableGpt:       z('DISABLE_GPT')        ?? b.disableGpt,
      adDisableDisplay: z('AD_DISABLE_DISPLAY') ?? b.adDisableDisplay,

      // Refresh — CDN value is in seconds; Flutter uses Duration.
      adRefreshMax:       i('AD_REFRESH_MAX')        ?? b.adRefreshMax,
      adRefreshMaxMobile: i('AD_REFRESH_MAX_MOBILE') ?? b.adRefreshMaxMobile,
      adRefreshInterval:  i('AD_REFRESH_INTERVAL') != null
          ? Duration(seconds: i('AD_REFRESH_INTERVAL')!)
          : b.adRefreshInterval,
      maxFailedAuctions:  i('MAX_FAILED_AUCTIONS')   ?? b.maxFailedAuctions,

      // Compliance
      gppEnabled: z('GPP_ENABLED') ?? b.gppEnabled,
      tcfVersion: i('TCF_VERSION') ?? b.tcfVersion,
      iabCats:    a('IAB_CATS')    ?? b.iabCats,

      // Mobile ad controls
      enableInterstitial:       z('ENABLE_INTERSTITIAL')       ?? b.enableInterstitial,
      enableFullscreenVideo:    z('ENABLE_FULLSCREEN_VIDEO')   ?? b.enableFullscreenVideo,
      interstitialsPerSession:  i('INTERSTITIALS_PER_SESSION') ?? b.interstitialsPerSession,
      videoTakeoversPerSession: i('VIDEO_TAKEOVERS_PER_SESSION') ?? b.videoTakeoversPerSession,

      // Third-party
      boltive:         z('BOLTIVE')           ?? b.boltive,
      boltiveClientId: s('BOLTIVE_CLIENT_ID') ?? b.boltiveClientId,
      lotame:          z('LOTAME')            ?? b.lotame,

      // Carry forward fields not exposed via remote config
      appBundleId:    b.appBundleId,
      appStoreUrl:    b.appStoreUrl,
      prebidServer:   b.prebidServer,
      debug:          b.debug,
    );
  }
}
```

Usage:

```dart
// At app launch (e.g. in main() before runApp)
final base = SellwildConfig(
  partnerCode: 'weatherbug',
  listingsUrl: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
);
final config = await SellwildRemoteConfig.build(
  base: base,
  slug: 'weatherbug-main',
);
// Hand `config` to your SellwildAdView / SellwildWidgetView.
```

#### Field reference

The CDN may carry any subset of these keys. Unknown keys are ignored, so the CMS can add fields without breaking the app.

| CDN key | Maps to (camelCase) | Type |
|---|---|---|
| `CODE` | `partnerCode` | string |
| `SLUG` | `slug` | string |
| `NAME` | `name` | string |
| `LISTINGS` | `listingsUrl` | string |
| `TITLE`, `LINK_TEXT`, `BUY_NOW_TEXT` | `title`, `linkText`, `buyNowText` | string |
| `TITLE_COLOR`, `LINK_COLOR`, `FONT_COLOR`, `PRICE_COLOR`, `PRICE_FONT_COLOR` | matching camelCase | string |
| `MARGIN_BOTTOM` | `marginBottom` | int |
| `COLORS` | `colors` | string[] |
| `OVERLAY_TITLE`, `WATERMARK` | matching camelCase | bool |
| `WATERMARK_TITLE` | `watermarkTitle` | string |
| `BANNER_ZID`, `BOTTOM_BANNER_ZID`, `MOBILE_BANNER_ZID` | matching camelCase | string |
| `MOBILE_ZID` | `mobileZids` | string[] |
| `HIDE_BANNER_TOP`, `HIDE_BANNER_BOTTOM`, `DISABLE_GPT`, `AD_DISABLE_DISPLAY` | matching camelCase | bool |
| `GAM` | `gamTag` | string |
| `AD_REFRESH_MAX`, `AD_REFRESH_MAX_MOBILE`, `MAX_FAILED_AUCTIONS` | matching camelCase | int |
| `AD_REFRESH_INTERVAL` | `adRefreshInterval` (seconds) | int |
| `GPP_ENABLED` | `gppEnabled` | bool |
| `TCF_VERSION` | `tcfVersion` | int |
| `IAB_CATS` | `iabCats` | string[] |
| `ENABLE_INTERSTITIAL`, `ENABLE_FULLSCREEN_VIDEO` | matching camelCase | bool |
| `INTERSTITIALS_PER_SESSION`, `VIDEO_TAKEOVERS_PER_SESSION` | matching camelCase | int |
| `BOLTIVE`, `LOTAME` | matching camelCase | bool |
| `BOLTIVE_CLIENT_ID` | `boltiveClientId` | string |

---

## Debug Mode

Enable verbose logging to diagnose integration issues.

```swift
config.debug = true   // iOS
```

```kotlin
SellwildConfig(debug = true, ...)   // Android
```

```ts
buildConfig({ debug: true, ... })   // React Native
```

```dart
SellwildConfig(debug: true, ...)    // Flutter
```

### What Debug Mode Enables

| Feature | Description |
|---------|-------------|
| Prebid.js debug output | Enables `pbjs.setConfig({ debug: true })` in the WebView. All auction events, bid values, and errors are logged to the WebView console. |
| SDK lifecycle logging | Prints ad load, impression, click, error, and refresh events to the platform logger (`print` on iOS, `Log.d` on Android, `console.log` on RN, `debugPrint` on Flutter). |
| Response telemetry | Logs per-bidder response times from `ext.responsetimemillis` after each auction. |

### Inspecting WebView Console Output

**iOS (Simulator or Device):**

1. On your iOS device or simulator, enable **Settings > Safari > Advanced > Web Inspector**.
2. In Safari on your Mac, select **Develop > [Device Name] > [Your App]**.
3. The Prebid.js auction output appears in the Safari Web Inspector console.

**Android:**

1. Open Chrome on your development machine.
2. Navigate to `chrome://inspect/#devices`.
3. Your app's WebView appears under the device. Click **Inspect** to open DevTools.

**React Native:**

1. Enable remote debugging in the RN developer menu.
2. Use Chrome DevTools or Flipper to view console output from `react-native-webview`.

**Flutter:**

1. On Android, use `chrome://inspect/#devices`.
2. On iOS, use Safari Web Inspector as described above.

### Production Warning

Do not ship with `debug: true`. Debug mode increases CPU usage, network logging, and exposes auction CPM values in the console. Always set `debug: false` (or omit the field) for production builds.
