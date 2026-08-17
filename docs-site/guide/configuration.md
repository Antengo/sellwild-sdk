# Configuration Reference

Complete reference for all Sellwild SDK configuration options. These fields apply across all platforms (iOS, Android, React Native, Flutter) unless noted otherwise.

---

## The first-class path: `configure(partnerCode, slug)`

In 1.2.0+, partners integrate the SDK with two strings:

```ts
// React Native / TypeScript
const config = await configure('weatherbug', 'weatherbug-weatherbug')
```

```swift
// iOS
let config = await SellwildSDK.configure(
    partnerCode: "weatherbug", slug: "weatherbug-weatherbug"
)
```

```kotlin
// Android
val config = SellwildSDK.configure(
    partnerCode = "weatherbug", slug = "weatherbug-weatherbug"
)
```

```dart
// Flutter
final config = await SellwildSDK.configure(
  partnerCode: 'weatherbug', slug: 'weatherbug-weatherbug',
);
```

`configure()` fetches `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`,
applies it onto SDK defaults, and returns a fully-built `SellwildConfig`. Every
field below — ad zones, refresh intervals, waterfall partners,
compliance flags, app identity — is populated from the CMS without an app
update. On any network failure, timeout, or 404 the SDK falls back to
deterministic defaults so ads still render.

The rest of this page documents every field that the CMS can populate.

---

## Table of Contents

1. [Remote Config](#remote-config) — the JSON shape served by the CDN
2. [SellwildConfig](#sellwildconfig) — every field the SDK reads
3. [PrebidServerConfig](#prebidserverconfig)
4. [Ad Size Reference](#ad-size-reference)
5. [Ad Refresh Configuration](#ad-refresh-configuration)
6. [Debug Mode](#debug-mode)

---

## SellwildConfig

The primary configuration object passed to all SDK components. Every ad view, widget, and API client reads from this object. All fields below can be set by the CDN via [Remote Config](#remote-config); only `partnerCode` is truly required.

### Identity

| Field | Type | Description |
|-------|------|-------------|
| `partnerCode` | `String` | Your Sellwild partner identifier. Used as `ortb2.app.publisher.id` in bid requests. **Required.** |

### App Identity

These fields ensure bid requests are classified as in-app traffic. Without them, DSPs treat impressions as anonymous web traffic and most will not bid.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `appBundleId` | `String?` | `null` | App bundle identifier (e.g., `"com.example.myapp"`). Sent as `ortb2.app.bundle`. |
| `appStoreUrl` | `String?` | `null` | App store listing URL. Sent as `ortb2.app.storeurl`. Required for app-ads.txt verification. |

### Prebid Server

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `prebidServer` | `PrebidServerConfig?` | `null` | Prebid Server configuration used by the native Prebid Mobile auction. See [PrebidServerConfig](#prebidserverconfig). When `null`, no programmatic auction runs and only `gamTag` / zone fallbacks are used. |
| `prebidSrc` | `String?` | `null` | Reserved. Used only by `SellwildWidget` (marketplace listings) when it needs to load a custom Prebid.js bundle inside its WebView surface. Does not affect banner ads. |

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

### How It's Used

When `prebidServer` is set, the native Prebid Mobile SDK is bootstrapped on first banner load with the configured `accountId`, `endpoint`, and `timeout`. The SDK constructs an OpenRTB 2.6 bid request containing:

- `app.bundle` and `app.storeurl` from your config
- `app.publisher.id` set to your `partnerCode`
- Real device signals (IDFV / AAID, ATT status, OS version) supplied by Prebid Mobile
- TCF v2 consent string when GDPR applies
- The `bidders` list as enabled adapters on the server side

The bid response is matched to the GAM ad request via Prebid Mobile's targeting keywords (`hb_pb`, `hb_cache_id`, `hb_size`, …) so the line item resolves the cached creative.

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
    adRefreshMaxMobile = 10,
    adRefreshIntervalMs = 30_000L,
    maxFailedAuctions = 3,
    // ...
)
```

---

## Remote Config

The first-class integration path. Each platform exposes a `SellwildSDK.configure(partnerCode, slug)` (TypeScript: `configure(partnerCode, slug)`) helper that fetches partner config from the Sellwild CDN at app launch and returns a fully-populated `SellwildConfig`. This lets your Sellwild contact change ad zones, refresh intervals, geo blocks, and waterfall partners without an app update.

### URL pattern

```
https://widget.sellwild.com/app/{partnerCode}/{slug}.json
```

Your Sellwild contact provisions the `slug` in the CMS. The JSON uses CONSTANT_CASE keys (e.g. `AD_REFRESH_MAX`, `HIDE_BANNER_TOP`) which the SDK maps to the camelCase fields documented above.

### Merge order

1. SDK defaults
2. Remote CDN config (overrides defaults)
3. App-controlled overrides (the optional callback to `configure()`)

### Failure handling

If the fetch fails (network error, timeout, 404), the SDK falls back silently to a `SellwildConfig(partnerCode:)` with deterministic defaults, so ads still render even with the CDN offline. Remote config is **additive, never blocking**.

### Usage

::: code-group

```ts [React Native / TypeScript]
import { configure } from '@sellwild/react-native-sdk';

const config = await configure('weatherbug', 'weatherbug-weatherbug');
```

```swift [iOS]
let config = await SellwildSDK.configure(
    partnerCode: "weatherbug",
    slug: "weatherbug-weatherbug"
) { c in
    c.appBundleId = Bundle.main.bundleIdentifier
}
```

```kotlin [Android]
val config = SellwildSDK.configure(
    partnerCode = "weatherbug",
    slug = "weatherbug-weatherbug",
) { c -> c.copy(appBundleId = packageName) }
```

```dart [Flutter]
final config = await SellwildSDK.configure(
  partnerCode: 'weatherbug',
  slug: 'weatherbug-weatherbug',
);
```

:::

See the [API Reference](./api-reference#configure) for full options.

### CDN field reference

The CDN may carry any subset of these keys. Unknown keys are ignored, so the CMS can add fields without breaking the app.

| CDN key | Maps to (camelCase) | Type |
|---|---|---|
| `CODE` | `partnerCode` | string |
| `SLUG` | `slug` | string |
| `NAME` | `name` | string |
| `TITLE`, `LINK_TEXT`, `BUY_NOW_TEXT` | `title`, `linkText`, `buyNowText` | string |
| `TITLE_COLOR`, `LINK_COLOR`, `FONT_COLOR`, `PRICE_COLOR`, `PRICE_FONT_COLOR` | matching camelCase | string |
| `MARGIN_BOTTOM` | `marginBottom` | int |
| `COLORS` | `colors` | string[] |
| `OVERLAY_TITLE`, `WATERMARK` | matching camelCase | bool |
| `WATERMARK_TITLE` | `watermarkTitle` | string |
| `BANNER_ZID`, `BOTTOM_BANNER_ZID`, `MOBILE_BANNER_ZID` | matching camelCase | string |
| `MOBILE_BANNER_ZID_IOS`, `MOBILE_BANNER_ZID_ANDROID` | `mobileBannerZid` (per-OS) | string |
| `MOBILE_ZID` | `mobileZids` | string[] |
| `MOBILE_ZID_IOS`, `MOBILE_ZID_ANDROID` | `mobileZids` (per-OS) | string[] |
| `MOBILE_ZID_ALL_IOS`, `MOBILE_ZID_ALL_ANDROID` | platform-wide fallback for all mobile placements | string |
| `MOBILE_HOUSE_AD_ENABLED` | house-ad master kill switch (mobile only) | bool |
| `MOBILE_HOUSE_AD_IMAGE`, `MOBILE_HOUSE_AD_URL` | app-wide house creative + click-through (mobile only) | string |
| `MOBILE_HOUSE_AD_BY_SIZE` | per-size house overrides, keyed `"<w>x<h>"` (mobile only) | object |
| `MOBILE_HOUSE_AD_BY_ZONE` | per-zone house overrides, keyed by zone id (mobile only) | object |
| `HIDE_BANNER_TOP`, `HIDE_BANNER_BOTTOM`, `DISABLE_GPT`, `AD_DISABLE_DISPLAY` | matching camelCase | bool |
| `GAM` | `gamTag` | string |
| `AD_REFRESH_MAX`, `AD_REFRESH_MAX_MOBILE`, `MAX_FAILED_AUCTIONS` | matching camelCase | int |
| `AD_REFRESH_INTERVAL` | `adRefreshInterval` (**milliseconds**) | int |
| `GPP_ENABLED` | `gppEnabled` | bool |
| `TCF_VERSION` | `tcfVersion` | int |
| `IAB_CATS` | `iabCats` | string[] |
| `ENABLE_INTERSTITIAL`, `ENABLE_FULLSCREEN_VIDEO` | matching camelCase | bool |
| `INTERSTITIALS_PER_SESSION`, `VIDEO_TAKEOVERS_PER_SESSION` | matching camelCase | int |
| `BOLTIVE`, `LOTAME` | matching camelCase | bool |
| `BOLTIVE_CLIENT_ID` | `boltiveClientId` | string |

---

## Per-platform ad zones

The two mobile zone keys — `MOBILE_ZID` (interleaved feed ad zones) and `MOBILE_BANNER_ZID` (the mobile banner) — can resolve to **different Prebid Server stored-impression IDs on iOS and Android**. Resolution is **three tiers, most specific first**, per placement:

| Tier | Key(s) | Scope |
|---|---|---|
| 1 — per-placement, per-OS | `MOBILE_ZID_IOS` / `_ANDROID`, `MOBILE_BANNER_ZID_IOS` / `_ANDROID` | one placement on one OS |
| 2 — platform-wide "ALL" | `MOBILE_ZID_ALL_IOS` / `MOBILE_ZID_ALL_ANDROID` | every mobile placement (feed + banner) on one OS |
| 3 — shared base | `MOBILE_ZID` / `MOBILE_BANNER_ZID` | all platforms (today's behavior) |

For each placement on the device's OS: use the tier-1 per-placement key if set & non-empty; else the tier-2 platform-wide `*_ALL_*` value; else the tier-3 shared base. So you can set **one `*_ALL_*` value and every placement on that OS uses it**, and still override any individual placement — "all the same per platform, or per-placement when you want."

The pick happens in the native mapper (Swift on iOS, Kotlin on Android), so it is keyed on the **runtime OS, not the SDK type**. React Native and Flutter inherit their host OS — an RN app on an iPhone resolves the iOS keys; the same app on Android resolves the Android keys.

**Backward compatible**: with no suffixed/ALL keys, resolution falls through to the unsuffixed base, so existing CDN documents behave exactly as before.

**Naming**: placements are dynamic-/multi-size now, so the size no longer belongs in the stored-imp id — name the per-platform imps **size-less** (e.g. `weatherbug-mobile`, `weatherbug-mobile-ios`, `weatherbug-mobile-android`). The legacy `…-300x250` imp keeps working for placements not yet migrated.

```json
{
  "MOBILE_ZID": ["weatherbug-mobile-300x250"],
  "MOBILE_ZID_ALL_IOS": "weatherbug-mobile-ios",
  "MOBILE_ZID_ALL_ANDROID": "weatherbug-mobile-android",
  "MOBILE_BANNER_ZID_IOS": "weatherbug-banner-ios"
}
```

With the document above — **iOS**: the feed uses `weatherbug-mobile-ios` (tier-2 ALL) and the banner uses `weatherbug-banner-ios` (tier-1 override wins). **Android**: feed + banner both use `weatherbug-mobile-android` (tier-2 ALL). Neither OS falls to the shared `MOBILE_ZID`, because an ALL value is set for both.

---

## House ads (mobile)

A **house-ad backdrop** renders *behind* every mobile ad slot and shows through only when a paid creative is absent — a no-fill, or the transient blank while a `prebidOnly` slot tears down one creative and renders the next on refresh. When a real creative renders it covers the backdrop, so the slot auto-reverts to the paid ad. This removes the "ad goes blank then pops back" flash on the `prebidOnly` refresh path and backfills no-fills with your own inventory (an advertisement shown only when a paid ad is absent).

It is **mobile-only** — the web widget ignores every `MOBILE_HOUSE_AD_*` key. Everything is resolved from remote CDN config, so you change creatives, click-throughs, and the kill switch **without an app release**.

> **`prebidOnly` refresh.** The `prebidOnly` path uses Prebid's own in-place auto-refresh, which briefly tears the current creative down before the next renders; the house-ad backdrop shows through that gap (and any no-fill), so the slot never flashes empty when a house creative or listing fallback is configured. `AD_REFRESH_INTERVAL` is in **milliseconds**.

> **`MOBILE_PAUSE_REFRESH_DETACHED`** (bool, default `false`, mobile SDK only). Prototype toggle for A/B testing. When `true`, an ad view pauses its refresh cadence while it is **fully detached** from the window (a recycled/pooled feed cell) and resumes on re-attach — trimming refreshes on views that are never on screen (the invalid-traffic edge), while **keeping** off-screen-but-attached refreshes. The first auction (fired at bind) is unaffected. Leave `false` to keep today's behavior.

### Content precedence (per placement)

1. **CMS house image** — a creative you configure via the `MOBILE_HOUSE_AD_*` keys below, with a click-through URL.
2. **A Sellwild listing** — used **only in the feed**, **only for the MREC (300×250)** slot (a 320×50 banner is too small for a listing card), and only when no image is configured for that placement. The feed supplies it automatically.
3. **Nothing** — the slot stays blank (today's behavior).

### Remote keys

| CDN key | Type | Default | Description |
|---|---|---|---|
| `MOBILE_HOUSE_AD_ENABLED` | bool | `true` | **Master kill switch.** `false` = no backfill at all (image *or* listing); slots stay blank. Fully remote. |
| `MOBILE_HOUSE_AD_IMAGE` | string (URL) **or** array of URL strings | — | App-wide house creative(s), sized to the slot. An array **rotates**: one URL is chosen at random on each no-fill (lazily fetched, then cached per URL). |
| `MOBILE_HOUSE_AD_URL` | string **or** array of URL strings | — | Click-through URL(s). A single string is **shared** across all images; an **array pairs one click URL per image by index** (index-matched to `MOBILE_HOUSE_AD_IMAGE`; a missing/blank paired entry means no click). |
| `MOBILE_HOUSE_AD_BY_SIZE` | object | — | Per-size overrides, keyed `"<w>x<h>"` — e.g. `{"300x250":{"image":"…","url":"…"}}`. Each `image` may itself be a single URL or an array of URLs. |
| `MOBILE_HOUSE_AD_BY_ZONE` | object | — | Per-zone overrides (most specific), keyed by zone id — e.g. `{"weatherbug-mobile-300x250":{"image":"…","url":"…"}}`. Each `image` may be a single URL or an array of URLs. |

### Image resolution precedence

For a given placement, the image (and its click-through URL) resolves **most specific first**:

`MOBILE_HOUSE_AD_BY_ZONE[zoneId]` → `MOBILE_HOUSE_AD_BY_SIZE["<w>x<h>"]` → `MOBILE_HOUSE_AD_IMAGE` / `MOBILE_HOUSE_AD_URL`.

If none resolve, the SDK falls to the listing fallback (feed MREC only) and then to a blank slot. When `MOBILE_HOUSE_AD_ENABLED` is `false`, none of this runs.

### Local image caching

House images are cached on-device — **in-memory plus on-disk in the app's caches directory** — so each image is fetched **at most once per device**. This is a deliberate request-saving measure; no personal data is involved (see [Privacy & Consent](/guide/privacy)). When `image` is an **array**, images stay lazy: only the URL picked for a given no-fill is fetched, and each distinct URL is cached the first time it's selected — so a rotation of N creatives costs at most N fetches per device.

```json
{
  "MOBILE_HOUSE_AD_ENABLED": true,
  "MOBILE_HOUSE_AD_IMAGE": [
    "https://cdn.sellwild.com/house/weatherbug-default-1.png",
    "https://cdn.sellwild.com/house/weatherbug-default-2.png"
  ],
  "MOBILE_HOUSE_AD_URL": [
    "https://weatherbug.com/app?c=default-1",
    "https://weatherbug.com/app?c=default-2"
  ],
  "MOBILE_HOUSE_AD_BY_SIZE": {
    "300x250": { "image": "https://cdn.sellwild.com/house/wb-mrec.png",   "url": "https://weatherbug.com/mrec" },
    "320x50":  { "image": "https://cdn.sellwild.com/house/wb-banner.png", "url": "https://weatherbug.com/banner" }
  },
  "MOBILE_HOUSE_AD_BY_ZONE": {
    "weatherbug-mobile-300x250": { "image": "https://cdn.sellwild.com/house/wb-weather-mrec.png", "url": "https://weatherbug.com/weather" }
  }
}
```

The native SDKs also expose an impression callback for house backfills so you can report them **separately from paid impressions** — see [iOS → House ads](/guide/ios#house-ads), [Android → House ads](/guide/android#house-ads), and the [API Reference](/guide/api-reference).

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
| Prebid Mobile debug output | Enables verbose logging in Prebid Mobile (auction events, bid values, errors). |
| GMA debug output | Enables verbose logging in the Google Mobile Ads SDK. |
| SDK lifecycle logging | Prints ad load, impression, click, error, and refresh events to the platform logger (`print` on iOS, `Log.d` on Android, `console.log` on RN, `debugPrint` on Flutter). |
| Response telemetry | Logs per-bidder response times from `ext.responsetimemillis` after each auction. |

### Inspecting Native Logs

**iOS:** Use the Xcode console or `Console.app` filtered to your app's process. Prebid Mobile and GMA logs appear with `Prebid` / `Google` prefixes.

**Android:** Use `adb logcat` filtered by tag. Prebid Mobile uses tags starting with `Prebid`; GMA uses `Ads`.

**React Native:** Native logs surface in Xcode (iOS) or `adb logcat` (Android). The `<SellwildBanner>` `onError` event also reports load failures back to JS.

**Flutter:** Same as native -- inspect Xcode or `adb logcat` for the platform you're running on.

### Production Warning

Do not ship with `debug: true`. Debug mode increases CPU usage, network logging, and exposes auction CPM values in the device log. Always set `debug: false` (or omit the field) for production builds.
