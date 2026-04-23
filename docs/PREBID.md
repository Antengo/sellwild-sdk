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
