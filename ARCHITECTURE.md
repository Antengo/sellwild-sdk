# Sellwild SDK Architecture

A grounded, current-as-of-1.2.0 picture of what the SDK actually is, how data flows through it, and which parts are native vs. WebView. No aspirational diagrams.

---

## TL;DR

- **Config** is fetched from a CDN as JSON. Identical flow on every platform.
- **Ad rendering** is WebView-based by default on every platform. GPT/Prebid.js runs *inside* the WebView.
- **Native Prebid Mobile** integration exists on iOS + Android as an *opt-in* bridge (`SellwildPrebidMobile`). Partners who want true-native auctions wire it up themselves and pair it with their own GAM ad view.
- **`config.remote`** is a passthrough bag of the raw CDN JSON. It exists so new bidders / new fields the CMS adds reach the WebView without an SDK release.

---

## High-level flow

```mermaid
flowchart TD
    subgraph CMS["Sellwild CMS"]
        CDN["widget.sellwild.com/app/{partnerCode}/{slug}.json<br/>(CONSTANT_CASE keys)"]
    end

    subgraph App["Partner App"]
        direction TB
        Configure["SellwildSDK.configure(partnerCode, slug)"]
        Config["SellwildConfig<br/>(typed fields + config.remote)"]
        AdView["SellwildAdView / SellwildBanner<br/>(banner placements)"]
        Widget["SellwildWidget<br/>(marketplace listings)"]
    end

    subgraph WebView["WebView (WKWebView / Android WebView / react-native-webview)"]
        HTML["Generated HTML page"]
        GPT["googletag (GPT)"]
        Prebid["Prebid.js"]
        Listings["Listing carousel JS"]
    end

    subgraph Auction["Auction Infra"]
        GAM["Google Ad Manager"]
        PBS["prebid.sellwild.com<br/>(Prebid Server, S2S)"]
        Bidders["IX, OpenX, Pubmatic,<br/>AppNexus, Rubicon,<br/>Medianet, Sovrn, ..."]
    end

    Configure -->|"HTTPS GET"| CDN
    CDN -->|"raw JSON"| Configure
    Configure -->|"map CONSTANT_CASE → camelCase<br/>+ stash raw under .remote"| Config

    Config --> AdView
    Config --> Widget

    AdView -->|"buildAdHTML()<br/>loadHTMLString"| HTML
    Widget -->|"htmlBuilder<br/>+ data attrs incl. config.remote"| HTML

    HTML --> GPT
    HTML --> Prebid
    HTML --> Listings

    GPT --> GAM
    Prebid --> PBS
    PBS --> Bidders
    GAM -->|"creative"| HTML
    Bidders -->|"bids"| PBS
```

---

## Step-by-step: what `configure()` actually does

```mermaid
sequenceDiagram
    participant App as Partner App
    participant SDK as SellwildSDK.configure
    participant CDN as widget.sellwild.com
    participant Config as SellwildConfig

    App->>SDK: configure("weatherbug", "weatherbug-weatherbug")
    SDK->>CDN: GET /app/weatherbug/weatherbug-weatherbug.json
    alt 200 OK
        CDN-->>SDK: { CODE, LISTINGS, BANNER_ZID, MEDIANET, ... }
        SDK->>SDK: mapRemoteConfig()<br/>typed fields → camelCase
        SDK->>SDK: stash raw JSON in .remote
        SDK->>SDK: coerceConfigValue(IAB_CATS)<br/>scalar → array
        SDK->>SDK: applyDefaults(merged)
    else 404 / network / timeout
        SDK->>SDK: silent fallback to defaults
    end
    SDK-->>App: SellwildConfig
    App->>Config: read .partnerCode, .bannerZid, .remote["MEDIANET"]
```

**Key invariants**
- `configure(partnerCode, slug)` never throws. Network failure → defaults.
- `config.remote` always populated when fetch succeeds; contains *every* CDN key including ones the SDK doesn't have a typed field for.
- All five platforms (TS core, RN, iOS, Android, Flutter) have their own `configure()` with the same shape.

---

## Ad rendering: the WebView path (default)

This is what runs when a partner drops a `SellwildAdView` (iOS/Android) or `SellwildBanner` (RN) into their app without doing anything else.

```mermaid
sequenceDiagram
    participant App as Partner App
    participant AdView as SellwildAdView
    participant WV as WKWebView / WebView
    participant GPT as googletag (in-WV)
    participant GAM as Google Ad Manager
    participant Prebid as Prebid.js (in-WV)
    participant PBS as prebid.sellwild.com

    App->>AdView: init(config:, adSize:, zoneId:)
    App->>AdView: addSubview / layout
    App->>AdView: load()
    AdView->>AdView: buildAdHTML()<br/>(injects config + GPT/zone script)
    AdView->>WV: loadHTMLString(html, base: widget.sellwild.com)
    WV->>GPT: load gpt.js
    WV->>Prebid: load prebid.js
    Prebid->>PBS: OpenRTB2 auction request
    PBS-->>Prebid: bid responses
    Prebid->>GPT: setTargeting(hb_*)
    GPT->>GAM: ad request
    GAM-->>WV: creative HTML
    WV->>AdView: postMessage("impression")<br/>via JS bridge
    AdView->>App: delegate.onAdImpression
```

**What lives where**
| Layer | iOS | Android | RN | Flutter |
|---|---|---|---|---|
| Native shell | `SellwildAdView: UIView` | `SellwildAdView: FrameLayout` | `SellwildBanner` (RN component) | `SellwildBannerView` |
| WebView | `WKWebView` | `android.webkit.WebView` | `react-native-webview` | `webview_flutter` |
| Auction JS | GPT + Prebid.js loaded *inside* WebView | same | same | same |
| Click/impression | `WKScriptMessageHandler` | `@JavascriptInterface` | RN bridge | platform channel |

---

## Ad rendering: the native Prebid path (opt-in)

Available today on iOS + Android via `SellwildPrebidMobile`. Partners who want true-native auctions opt in by adding the Prebid Mobile pod/dependency and pairing it with their own GAM `AdManagerAdView`.

```mermaid
sequenceDiagram
    participant App as Partner App
    participant Bridge as SellwildPrebidMobile
    participant Prebid as PrebidMobile SDK
    participant PBS as prebid.sellwild.com
    participant GAM as GAMBannerView (native)

    App->>Bridge: initialize(serverUrl, accountId)
    Bridge->>Prebid: Prebid.shared.setup
    App->>Bridge: makeBannerAdUnit(configId, size)
    Bridge-->>App: BannerAdUnit
    App->>Prebid: unit.fetchDemand(adObject: gamBannerView)
    Prebid->>PBS: OpenRTB2 auction (native HTTPS)
    PBS-->>Prebid: bids
    Prebid->>GAM: setCustomTargeting(hb_*)
    App->>GAM: load(GAMRequest())
    GAM-->>App: native creative (no WebView)
```

**Status**
- iOS file: `ios/Sources/SellwildSDK/SellwildPrebidMobile.swift` (gated on `#if canImport(PrebidMobile)`)
- Android file: `android/src/main/kotlin/com/sellwild/sdk/SellwildPrebidMobile.kt.reference` — **note the `.reference` suffix.** Not currently part of the Android build. Needs to be promoted to `.kt` and the Prebid Mobile dependency declared `compileOnly` in `build.gradle.kts`.
- No automated wiring from `SellwildConfig` → Prebid Mobile params yet. Partners read `config.bannerZid`, `config.s2sConfig`, etc. and pass them into `SellwildPrebidMobile.initialize` themselves.

---

## Config map: typed vs. passthrough

```mermaid
flowchart LR
    subgraph CDN["CDN JSON (CONSTANT_CASE)"]
        K1["CODE, SLUG, NAME"]
        K2["BANNER_ZID, MOBILE_ZID, GAM"]
        K3["AD_REFRESH_INTERVAL, IAB_CATS"]
        K4["IX, OPENX, PUBMATIC, RUBICON"]
        K5["MEDIANET, AMX, SOVRN, ONETAG, ..."]
        K6["S2S_CONFIG, GPP_ENABLED"]
    end

    subgraph SDK["SellwildConfig"]
        T1["partnerCode, slug, name"]
        T2["bannerZid, mobileZids, gamTag"]
        T3["adRefreshInterval, iabCats[]"]
        T4["ix, openx, pubmatic, rubicon<br/>(typed, @deprecated)"]
        R["remote: Record&lt;string, unknown&gt;<br/>(raw JSON, full bag)"]
    end

    K1 --> T1
    K2 --> T2
    K3 --> T3
    K4 --> T4
    K1 --> R
    K2 --> R
    K3 --> R
    K4 --> R
    K5 --> R
    K6 --> R

    R -->|"data attrs to WebView"| WV["WebView htmlBuilder"]
    T1 --> WV
    T2 --> WV
    T3 --> WV
    T4 --> WV
```

**Why both?**
- Typed fields exist for native code that *behaves* on values (e.g. `config.adRefreshInterval` drives the iOS `Timer`).
- `config.remote` exists so new bidders the CMS adds (Weatherbug has 15 unmapped today: MEDIANET, AMX, SOVRN, etc.) reach the WebView's Prebid.js without an SDK release.
- Typed bidder fields (`ix`, `openx`, `pubmatic`, `appnexus`) are `@deprecated`. Read from `config.remote["IX"]` etc. going forward.

---

## Per-platform integration ceremony

```mermaid
flowchart TD
    subgraph RN["React Native"]
        RN1["import { configure, SellwildBanner }"]
        RN2["const config = await configure(partnerCode, slug)"]
        RN3["&lt;SellwildBanner config={config} adSize='300x250' /&gt;"]
        RN1 --> RN2 --> RN3
    end

    subgraph iOS["Swift"]
        iOS1["let config = await SellwildSDK.configure(partnerCode:, slug:)"]
        iOS2["let adView = SellwildAdView(config: config, adSize: .mrec, zoneId: '280')"]
        iOS3["view.addSubview(adView)"]
        iOS4["adView.load()  ← required, separate call"]
        iOS1 --> iOS2 --> iOS3 --> iOS4
    end

    subgraph Android["Kotlin"]
        AND1["val config = SellwildSDK.configure(partnerCode, slug)"]
        AND2["val adView = SellwildAdView(context)"]
        AND3["adView.setup(config, AdSize.MREC_300x250, zoneId = '280')"]
        AND4["adView.load()  ← required, separate call"]
        AND1 --> AND2 --> AND3 --> AND4
    end
```

**Friction (real, not aspirational)**
- iOS `load()` is separate from `init`. Easy to forget.
- Android requires three calls (`new`, `setup`, `load`). Should collapse.
- `zoneId` is a positional string; partners have to remember it lives in `config.bannerZid` or `config.mobileZids[0]`.

---

## What's published (1.2.0)

| Platform | Package | Registry | Status |
|---|---|---|---|
| TS core | `@sellwild/sdk-core` | npm | ✅ live |
| React Native | `@sellwild/react-native-sdk` | npm | ✅ live |
| iOS | `SellwildSDK` | CocoaPods + SPM | ✅ live |
| Android | `com.sellwild:sdk` | `s3://maven.sellwild.com/releases/` | ✅ live |
| Flutter | `sellwild_sdk` | pub.dev | ✅ live |

**Known issues blocking 1.2.1**
- `iabCats` scalar-vs-array crash in `htmlBuilder` (fix committed, not yet published).
- Sample apps lead with the WebView widget tab on iOS/Android instead of the banner integration partners actually need.
- Android `SellwildPrebidMobile.kt.reference` not yet promoted to a real source file.
