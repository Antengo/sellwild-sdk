# Prebid Integration Guide

The Sellwild SDK supports three Prebid integration modes. Choose the one that fits your needs.

---

## Modes at a Glance

| Mode | Where Bidding Runs | IDFA/GAID | 3rd-party Cookies | Extra Dependency |
|------|--------------------|-----------|-------------------|------------------|
| **A — Prebid.js in WebView** | Inside WebView (client) | ✗ | ✗ | None |
| **B — Prebid Server S2S** | Prebid Server (server-side) | ✗ | N/A (server call) | Self-hosted or managed Prebid Server |
| **C — Prebid Mobile SDK** | Native iOS/Android SDK | ✓ (with ATT) | N/A | `PrebidMobile` pod / gradle dependency |

All three modes inject `ortb2.app` into Prebid.js (Modes A & B) or set the app context natively (Mode C) so DSPs receive correct in-app traffic signals.

---

## Mode A — Prebid.js in WebView (default)

This is the default. No additional configuration is needed beyond the base `SellwildConfig`.

**Required fields to enable proper in-app signals:**

```swift
// iOS
c.appBundleId = Bundle.main.bundleIdentifier   // e.g. "com.mycompany.myapp"
c.appStoreUrl = "https://apps.apple.com/app/idXXXXXXXXX"
```

```kotlin
// Android
val config = SellwildConfig(
    appBundleId = BuildConfig.APPLICATION_ID,
    appStoreUrl = "https://play.google.com/store/apps/details?id=com.mycompany.myapp",
    // ...
)
```

```dart
// Flutter
SellwildConfig(
  appBundleId: 'com.mycompany.myapp',
  appStoreUrl: 'https://apps.apple.com/app/idXXXXXXXXX',
)
```

**What the SDK does automatically:**
- Injects `pbjs.setConfig({ ortb2: { app: { bundle, storeurl, publisher: { id } } } })` before `prebid.js` loads via `pbjs.que`.
- Disables iframe `userSync` (blocked in all WebViews — no 3rd-party cookies).
- Sets `syncDelay: 5000` so pixel syncs don't compete with the auction.

**Known limitations:**
- IDFA/GAID not available to Prebid.js (needs host-app ATT permission + `ortb2.user.eids`).
- TCF consent string is not auto-bridged from native CMP to WebView `window.__tcfapi`.
- 3rd-party cookie syncs (iframe mode) always fail in WKWebView and Android WebView.

---

## Mode B — Prebid Server S2S

Instead of running bidder adapters client-side, the WebView's Prebid.js makes a single call to a Prebid Server instance which fans out to all configured bidders server-side. This eliminates the cookie and IDFA limitations of Mode A.

**Requirements:**
- A running Prebid Server instance (self-hosted or managed).
  - [AppNexus hosted](https://prebid.adnxs.com/pbs/v1/openrtb2/auction)
  - [Rubicon hosted](https://prebid-server.rubiconproject.com/openrtb2/auction)
  - [Self-hosted](https://docs.prebid.org/prebid-server/hosting/pbs-hosting.html)

**Configuration:**

```swift
// iOS — SellwildConfig.swift
c.prebidServer = PrebidServerConfig(
    accountId: "YOUR_ACCOUNT_ID",
    endpoint:  "https://prebid-server.example.com/openrtb2/auction",
    bidders:   ["appnexus", "rubicon", "ix", "openx"],
    timeout:   1500
)
```

```kotlin
// Android — SellwildConfig.kt
prebidServer = PrebidServerConfig(
    accountId = "YOUR_ACCOUNT_ID",
    endpoint  = "https://prebid-server.example.com/openrtb2/auction",
    bidders   = listOf("appnexus", "rubicon", "ix", "openx"),
    timeout   = 1500,
),
```

```typescript
// React Native / Core TypeScript
prebidServer: {
  accountId: 'YOUR_ACCOUNT_ID',
  endpoint:  'https://prebid-server.example.com/openrtb2/auction',
  bidders:   ['appnexus', 'rubicon', 'ix', 'openx'],
  timeout:   1500,
}
```

```dart
// Flutter
prebidServer: PrebidServerConfig(
  accountId: 'YOUR_ACCOUNT_ID',
  endpoint: 'https://prebid-server.example.com/openrtb2/auction',
  bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
  timeout: 1500,
),
```

**What the SDK injects (automatic when `prebidServer` is set):**

```javascript
pbjs.setConfig({
  ortb2: { app: { bundle, storeurl, publisher: { id } } },
  userSync: { filterSettings: { iframe: { bidders: '*', filter: 'exclude' } }, syncDelay: 5000 },
  s2sConfig: {
    accountId: "YOUR_ACCOUNT_ID",
    bidders: ["appnexus", "rubicon", "ix", "openx"],
    timeout: 1500,
    adapter: "prebidServer",
    endpoint: { p1Consent: "...", noP1Consent: "..." }
  }
});
```

**Remaining limitation:** IDFA/GAID still not passed automatically. The Prebid Server receives the request but cannot enrich it with device ID. Use Mode C for that.

---

## Mode C — Prebid Mobile SDK (native)

The Prebid Mobile SDK runs natively (no WebView for bidding). It supports IDFA (iOS, with ATT permission) and GAID (Android). Use it for standalone banner and interstitial placements that need the highest fill rate.

**This mode is additive** — you can still use `SellwildWidget` for the listing carousel and use Prebid Mobile for separate ad placements.

### iOS Setup

**1. Add dependency (Podfile):**
```ruby
pod 'PrebidMobile', '~> 2.3'
pod 'PrebidMobileGAMEventHandlers', '~> 2.3'  # if using Google Ad Manager
```

Or via Swift Package Manager:
- URL: `https://github.com/prebid/prebid-mobile-swift`
- Version: `2.3.x`

**2. Initialize in `AppDelegate`:**
```swift
import SellwildSDK

func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    SellwildPrebidMobile.initialize(
        serverHost: .appnexus,          // or .rubicon
        accountId:  "YOUR_ACCOUNT_ID"
    )
    // For self-hosted Prebid Server:
    // SellwildPrebidMobile.initialize(
    //     serverUrl: "https://prebid-server.example.com",
    //     accountId: "YOUR_ACCOUNT_ID"
    // )
    return true
}
```

**3. Create a banner ad unit:**
```swift
import GoogleMobileAds   // or your ad server SDK

let gamBanner = GAMBannerView(adSize: GADAdSizeBanner)
gamBanner.adUnitID = "/12345678/your-ad-unit"
gamBanner.rootViewController = self

let prebidBanner = SellwildPrebidMobile.makeBannerAdUnit(
    configId: "YOUR_PREBID_CONFIG_ID",
    adSize: CGSize(width: 320, height: 50)
)
prebidBanner?.fetchDemand(adObject: gamBanner) { _ in
    gamBanner.load(GAMRequest())
}
```

### Android Setup

**1. Add dependency (app `build.gradle.kts`):**
```kotlin
implementation("org.prebid:prebid-mobile-sdk-core:2.3.2")
implementation("org.prebid:prebid-mobile-sdk-gamEventHandlers:2.3.2")  // if using GAM
```

**2. Initialize in `Application.onCreate()`:**
```kotlin
import com.sellwild.sdk.SellwildPrebidMobile
import com.sellwild.sdk.SellwildWebViewCompat

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        SellwildWebViewCompat.configureForMultiProcess(this)  // required for API 28+
        SellwildPrebidMobile.initialize(
            context   = this,
            host      = "appnexus",             // or "rubicon" / "custom"
            accountId = "YOUR_ACCOUNT_ID",
            // For self-hosted: serverUrl = "https://prebid-server.example.com"
            debug     = BuildConfig.DEBUG,
        )
    }
}
```

**3. Create a banner ad unit (typed, requires PrebidMobile on classpath):**
```kotlin
// SellwildPrebidMobile.makeBannerAdUnit() returns Any? when using reflection.
// Cast it to BannerAdUnit if you have the PrebidMobile dependency directly:
val bannerUnit = org.prebid.mobile.BannerAdUnit("YOUR_PREBID_CONFIG_ID", 320, 50)
bannerUnit.fetchDemand(gamBannerView) {
    gamBannerView.loadAd(AdManagerAdRequest.Builder().build())
}
```

---

## External User IDs (eids) — partner-supplied

Authenticated universal IDs (UID2, ID5, LiveRamp RampID, …) restore addressability and
materially lift CPMs — but they are minted from the user's **email / login / consent**,
which only your app holds. **The SDK cannot generate them.** You obtain the ID(s) from
your identity provider and hand them to the SDK, which emits them as OpenRTB
`user.ext.eids` on every native Prebid auction (Mode C).

> This is **required partner wiring** — Sellwild provides the rail; you supply the IDs.

### Wiring

Set the IDs **once per user session**, after the SDK is configured/bootstrapped and
before (or at) your first ad load. Prebid Mobile does **not** persist eids across app
restarts — re-set them each launch after you resolve the user's identity.

**iOS**
```swift
import SellwildSDK

SellwildPrebidMobile.setExternalUserIds([
    SellwildEid(source: "uidapi.com", uids: [
        SellwildEidUID(id: uid2Token, atype: 3)                    // person-based
    ]),
    SellwildEid(source: "id5-sync.com", uids: [
        SellwildEidUID(id: id5Id, atype: 1, ext: ["linkType": 2])
    ]),
])
```

**Android**
```kotlin
import com.sellwild.sdk.SellwildPrebidMobile
import com.sellwild.sdk.SellwildEid
import com.sellwild.sdk.SellwildEidUid

SellwildPrebidMobile.setExternalUserIds(listOf(
    SellwildEid("uidapi.com", listOf(
        SellwildEidUid(uid2Token, atype = 3)
    )),
    SellwildEid("id5-sync.com", listOf(
        SellwildEidUid(id5Id, atype = 1, ext = mapOf("linkType" to 2))
    )),
))
```

Pass an empty array/list to clear previously set IDs (e.g. on logout).

### `atype` (OpenRTB agent type)

| Value | Meaning |
|---|---|
| 1 | Cookie / web |
| 2 | In-app device ID (IFA/DPID) |
| 3 | Person-based (authenticated — most universal IDs) |

Use the value your ID provider specifies; for an authenticated login-based ID, `3` is typical.

### Server-side permission

Emitting eids is necessary but not always sufficient: which bidders receive which eids is
governed by **eid permissions** in the Prebid Server stored request. By default Prebid
Server forwards eids to all bidders; if a bidder requires an explicit grant, coordinate
with your Prebid Server owner. Confirm delivery by inspecting a debug auction's resolved
request for `user.ext.eids`.

### What the SDK sources vs. what you supply

- **You (partner) supply** authenticated IDs (UID2/ID5/RampID) — the SDK cannot mint them.
- **Device-graph IDs** (e.g. Lotame Panorama) that Sellwild can resolve are a planned SDK
  enhancement; until then, pass any resolved ID through the same `setExternalUserIds` API.

---

## Geo (`device.geo`) — partner-supplied

Weather/utility apps usually know the user's location before the ad SDK would.
Passing it in lets DSPs value the impression on real geo instead of coarse IP,
and exposes `state` to non-ad consumers (e.g. per-state listing caches).

### Type

`SellwildGeo` — all fields optional; only what you set is sent. Maps to OpenRTB
`device.geo` (note `state` → `region`):

| field | OpenRTB | notes |
|---|---|---|
| `country` | `geo.country` | ISO-3166-1 alpha-3, e.g. `USA` |
| `state` | `geo.region` | also the key for per-state consumers |
| `city` | `geo.city` | |
| `zip` | `geo.zip` | |
| `metro` | `geo.metro` | DMA |
| `lat` / `lon` | `geo.lat` / `geo.lon` | |
| `type` | `geo.type` | 1 = GPS, 2 = IP, 3 = user |

### Wiring

Set at configure time (seeds both the auction and the shared store):

```swift
config.geo = SellwildGeo(country: "USA", state: "NY", zip: "10001")
```
```kotlin
config = config.copy(geo = SellwildGeo(country = "USA", state = "NY", zip = "10001"))
```

Or update at runtime — re-emits the combined ORTB config, preserving
`app.publisher.id`:

```swift
SellwildPrebidMobile.setGeo(SellwildGeo(state: "CA"))
```
```kotlin
SellwildPrebidMobile.setGeo(SellwildGeo(state = "CA"))
```

### Reading it outside the ad path

The current geo lives in a process-wide, thread-safe store — readable by the
listings feed or host-app code, not just the Prebid auction:

```swift
let state = SellwildGeoStore.current?.state
```
```kotlin
val state = SellwildGeoStore.current?.state
```

> **React Native:** the `pbsDebug` flag is bridged today. `geo` passthrough
> (nested marshalling) and a JS runtime `setGeo` are pending — RN's ad bridge is
> view-manager-only, so a callable `setGeo` needs a new native method module.

## Debug flags — `debug` vs `pbsDebug`

Two independent, locally-configurable toggles (also settable remotely via the
CDN `DEBUG` / `PBS_DEBUG` keys):

| flag | effect |
|---|---|
| `debug` | Raises Prebid Mobile SDK **log verbosity** and enables the SDK's own render/auction diagnostics. |
| `pbsDebug` | Flips Prebid Mobile's `pbsDebug` → adds `ext.prebid.debug=1` + `returnallbidstatus` to the auction so the **response** carries the full server debug block (per-bidder status, `resolvedrequest`, cache calls). Heavier responses — leave OFF in production. |

`pbsDebug` surfaces on-device the same auction detail you'd otherwise only get
from a `debug=1` server curl. The two are orthogonal — verbose logs without heavy
responses, or vice-versa.

```swift
config.debug = true      // SDK logs
config.pbsDebug = true   // server-side auction debug block
```
```kotlin
config = config.copy(debug = true, pbsDebug = true)
```

## Outstream Video

The SDK supports **outstream (in-banner) video** in the standard banner slot (e.g. 300×250) — autoplay muted, plays when in view. It's **off by default** and toggled entirely from remote config, so you enable/disable it per zone from the CDN with **no app release**.

**Enable (remote config / CDN):**
```json
{ "VIDEO_ENABLED": true }
```
```json
{ "VIDEO_ENABLED_BY_ZONE": { "43": true } }
```
When on, the SDK requests a multiformat (banner + video) impression; when off, it's banner-only (unchanged). Precedence mirrors `AD_STACK`: global flag, then per-zone.

**Rendering depends on the ad stack (`AD_STACK`):**

| Stack | Renders via | Extra setup |
|-------|-------------|-------------|
| `prebidOnly` | Prebid's own renderer | none — Prebid plays the outstream video itself |
| `both` (default) | GAM | **GAM outstream line item / renderer required** |

On `both` zones, provision the GAM outstream creative **before** enabling video, or a winning video bid can win-but-not-render (lost impression). On `prebidOnly` zones, just flip the flag.

**SDK video defaults:** mp4; VAST 2.0–4.0; autoplay sound-off; OMID + MRAID (no VPAID); in-banner / standalone; 5–30s.

**Requirements:** an SDK version that ships outstream video; SSPs with active video seats.

---

## Choosing Between Modes

| Scenario | Recommended Mode |
|----------|-----------------|
| Quick integration, no Prebid Server | A (default) |
| Cookie/IDFA issues, can run a server | B (S2S) |
| Maximum fill, IDFA available, own ad server | C (Prebid Mobile) |
| Maximum fill, no own ad server | A or B |
| Regulatory compliance (TCF, CCPA) | C (Prebid Mobile — CMP bridges natively) |

Modes A and B can be switched by toggling `prebidServer` in `SellwildConfig` — no other code changes needed.

Mode C requires adding the `PrebidMobile` dependency and calling `SellwildPrebidMobile.initialize()` at app launch. The `SellwildWidget` WebView still works alongside Mode C.

---

## Reference: `PrebidServerConfig` Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountId` | String | Yes | Your Prebid Server account ID |
| `endpoint` | String | Yes | Full auction endpoint URL |
| `bidders` | String[] | Yes | Bidder codes to route server-side |
| `timeout` | Int | No (default: 1500) | S2S auction timeout in ms |
| `syncEndpoint` | String? | No | `/cookie_sync` URL (derived from endpoint if omitted) |

---

## Further Reading

- [Prebid.js S2S documentation](https://docs.prebid.org/dev-docs/modules/prebidServer.html)
- [Prebid Server hosting guide](https://docs.prebid.org/prebid-server/hosting/pbs-hosting.html)
- [Prebid Mobile iOS SDK](https://docs.prebid.org/prebid-mobile/pbm-api/ios/pbm-api-ios.html)
- [Prebid Mobile Android SDK](https://docs.prebid.org/prebid-mobile/pbm-api/android/pbm-api-android.html)
- [ortb2.app specification (OpenRTB 2.6)](https://www.iab.com/wp-content/uploads/2022/04/OpenRTB-2-6_FINAL.pdf)
- [sdk/VALIDATION.md](./VALIDATION.md) — full correctness report including WebView caveats
