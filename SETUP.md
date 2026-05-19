# SDK Setup Guide

Per-platform instructions for integrating the Sellwild SDK into a host app.

---

## Prerequisites (all platforms)

You need a **partner code** and a **slug** from Sellwild. Contact sdk@sellwild.com to get these. They look like:

```
partnerCode: "mysite"
slug: "mysite-main"
```

At runtime, call `SellwildSDK.configure(partnerCode, slug)` and the SDK fetches everything else from the Sellwild CDN at `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`.

Optionally, you may also receive:
- A **GAM ad unit path** (`/12345678/my-ad-unit`) for Google Ad Manager
- **Zone IDs** for banner and inline placements
- **Prebid bidder credentials** (ix, openx, pubmatic, etc.)

---

## React Native

### 1. Install dependencies

```bash
npm install @sellwild/react-native-sdk react-native-webview
# or
yarn add @sellwild/react-native-sdk react-native-webview
```

### 2. iOS — link WebView (React Native 0.60+, auto-linking handles this)

```bash
cd ios && pod install
```

If you see `NSAllowsArbitraryLoads` warnings, add to `ios/YourApp/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

### 3. Android — allow cleartext traffic (for ad networks that still use HTTP)

In `android/app/src/main/AndroidManifest.xml`:
```xml
<application
  android:usesCleartextTraffic="true"
  ...>
```

Or use a Network Security Config for finer control (see Android section below).

### 4. Use in your app

```tsx
import { SellwildWidget, SellwildBanner } from '@sellwild/react-native-sdk'

// Full marketplace widget
<SellwildWidget
  config={{
    partnerCode: 'mysite',
    gamTag: '/12345678/mysite-mobile',
    bannerZid: '98765',
    mobileZids: ['11111', '22222'],
    adRefreshMaxMobile: 5,
    adRefreshInterval: 30000,
  }}
  style={{ flex: 1 }}
  onListingPress={(listing) => {
    // listing.url is the Sellwild product page
    Linking.openURL(listing.url)
  }}
/>

// Standalone 320x50 banner
<SellwildBanner
  config={config}
  size="320x50"
  zoneId="98765"
/>
```

### 5. Metro bundler — allow symlinks from local SDK (dev only)

If consuming the SDK from a local path instead of npm:

```js
// metro.config.js
module.exports = {
  watchFolders: [path.resolve(__dirname, '../sdk')],
}
```

---

## iOS (Swift)

### 1. Add the package

**Swift Package Manager** (recommended):

In Xcode: File → Add Package Dependencies → enter:
```
https://github.com/sellwild/sdk-ios.git
```
Select version `1.0.0` and add `SellwildSDK` to your target.

**CocoaPods:**
```ruby
# Podfile
pod 'SellwildSDK', '~> 1.0'
```
Then run `pod install`.

### 2. Info.plist — allow ad network traffic

Sellwild loads ad scripts from Google, Prebid CDN, and ad networks. Add:
```xml
<!-- ios/YourApp/Info.plist -->
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

For App Store submission, NSAllowsArbitraryLoads requires justification. If you prefer strict ATS, you can instead whitelist specific domains:
```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>sellwild.com</key>
    <dict><key>NSIncludesSubdomains</key><true/></dict>
    <key>doubleclick.net</key>
    <dict><key>NSIncludesSubdomains</key><true/></dict>
    <key>googlesyndication.com</key>
    <dict><key>NSIncludesSubdomains</key><true/></dict>
  </dict>
</dict>
```

### 3. UIKit usage

```swift
import SellwildSDK

class MyViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        var config = SellwildConfig(
            partnerCode: "mysite",
        )
        config.gamTag = "/12345678/mysite-mobile"
        config.bannerZid = "98765"
        config.adRefreshMaxMobile = 5

        let widget = SellwildWidgetView(config: config)
        widget.delegate = self
        widget.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(widget)

        NSLayoutConstraint.activate([
            widget.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            widget.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            widget.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            widget.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        widget.load()
    }
}

extension MyViewController: SellwildWidgetViewDelegate {
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didTapListing listing: SellwildListing) {
        if let urlStr = listing.url, let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }
}
```

### 4. SwiftUI usage

```swift
import SwiftUI
import SellwildSDK

struct ContentView: View {
    let config: SellwildConfig = {
        var c = SellwildConfig(
            partnerCode: "mysite",
        )
        c.gamTag = "/12345678/mysite-mobile"
        return c
    }()

    var body: some View {
        SellwildWidget(config: config) { listing in
            if let url = listing.url.flatMap(URL.init) {
                UIApplication.shared.open(url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

### 5. Banner-only ad

```swift
let banner = SellwildAdView(config: config, adSize: .mrec300x250, zoneId: "98765")
banner.delegate = self
banner.load()
// Add to view hierarchy + constrain to 300x250
```

---

## Android (Kotlin)

### 1. Add the dependency

**From local Maven** (see Deployment guide to publish):
```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        maven { url = uri("file://${rootProject.projectDir}/../sdk/android/build/repo") }
        google()
        mavenCentral()
    }
}
```

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("com.sellwild:sdk:1.0.0")
}
```

### 2. AndroidManifest.xml — permissions

Add to your app's `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

Allow ad network HTTP traffic (many ad networks still use HTTP endpoints):
```xml
<application
  android:usesCleartextTraffic="true"
  ...>
```

Or use a Network Security Config:
```xml
<!-- res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="true">sellwild.com</domain>
    <domain includeSubdomains="true">doubleclick.net</domain>
    <domain includeSubdomains="true">googlesyndication.com</domain>
  </domain-config>
</network-security-config>
```
Reference it in the manifest: `android:networkSecurityConfig="@xml/network_security_config"`

### 3. Usage

```kotlin
import com.sellwild.sdk.*

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val config = SellwildConfig(
            partnerCode = "mysite",
            gamTag = "/12345678/mysite-mobile",
            bannerZid = "98765",
            adRefreshMaxMobile = 5,
        )

        val widget = SellwildWidgetView(this)
        widget.setup(config)
        widget.listener = object : SellwildWidgetView.Listener {
            override fun onListingTapped(listing: SellwildListing) {
                listing.url?.let { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) }
            }
        }

        setContentView(widget)
        widget.load()
    }
}
```

**Lifecycle — important:** Wire up pause/resume to avoid WebView memory leaks:
```kotlin
override fun onResume() { super.onResume(); widget.resume() }
override fun onPause()  { super.onPause();  widget.pause()  }
override fun onDestroy(){ super.onDestroy(); widget.destroy() }
```

### 4. Coroutines — fetch listings natively (without WebView)

```kotlin
// ViewModel
viewModelScope.launch {
    SellwildAPIClient(applicationContext)
        .fetchListings(config)
        .onSuccess { response ->
            _listings.value = response.listings
        }
        .onFailure { error ->
            Log.e("Sellwild", "Failed to load listings", error)
        }
}
```

---

## Flutter

### 1. Add to pubspec.yaml

```yaml
dependencies:
  sellwild_sdk: ^1.0.0
```

Run:
```bash
flutter pub get
```

### 2. iOS — Info.plist

Same as the iOS section above — add `NSAllowsArbitraryLoads` or domain exceptions.

### 3. Android — AndroidManifest.xml

Same as the Android section above — add INTERNET permission and cleartext traffic.

### 4. iOS — enable WKWebView inline media

In `ios/Runner/AppDelegate.swift`:
```swift
// Already set by default in Flutter, but confirm:
GeneratedPluginRegistrant.register(with: self)
```

The `webview_flutter` plugin on iOS uses `WKWebView`. No extra config needed.

### 5. Usage

```dart
import 'package:sellwild_sdk/sellwild_sdk.dart';

const config = SellwildConfig(
  partnerCode: 'mysite',
  gamTag: '/12345678/mysite-mobile',
  bannerZid: '98765',
  adRefreshMaxMobile: 5,
);

// Full widget
class WidgetScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SellwildWidget(
      config: config,
      onListingTap: (listing) {
        if (listing.url != null) {
          launchUrl(Uri.parse(listing.url!));
        }
      },
    ),
  );
}

// Banner
SellwildBanner(
  config: config,
  adSize: SellwildAdSize.mrec300x250,
  zoneId: '98765',
)
```

---

## Zone IDs and Ad Delivery

The SDK supports two ad delivery mechanisms:

| Mechanism | Config Key | Notes |
|-----------|-----------|-------|
| Google Ad Manager (GPT) | `gamTag` | Full header bidding via Prebid.js |
| Zone-based (Bidstream) | `bannerZid`, `mobileZids`, etc. | Direct zone ID delivery |

**You must set at least one** of `gamTag` or a zone ID for ads to render. If both are set, GPT takes priority unless `disableGpt: true`.

### Prebid.js (header bidding)

The web widget bundles its own Prebid.js. If you have a custom build (with your specific bidders), set `prebidSrc` to your hosted URL:
```
prebidSrc: 'https://cdn.yoursite.com/prebid.js'
```

Otherwise the SDK will load the default bundle from `https://widget.sellwild.com/prebid.js`.

---

## Prebid in Native WebViews

The SDK automatically addresses known Prebid.js + WebView issues:

1. **ortb2.app** — Prebid.js running in a native WebView sends `ortb2.site` (browser traffic) by default. The SDK injects `pbjs.setConfig({ ortb2: { app: {...} } })` before `prebid.js` loads. Set `appBundleId` (your iOS bundle ID or Android package name) in `SellwildConfig` to populate `ortb2.app.bundle`.

2. **userSync iframe** — Iframe-based cookie syncs always fail in native WebViews (no 3rd-party cookies). The SDK disables them and sets a 5-second delay for pixel syncs.

3. **Prebid Server S2S** — To solve cookie/IDFA limitations completely, set `prebidServer` in your config to route all Prebid bids through a Prebid Server instance server-side.

**Full Prebid documentation:** [PREBID.md](./PREBID.md)

---

## Android — Multi-process WebView (API 28+)

If your app uses multiple processes, call this before creating any WebView:

```kotlin
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        SellwildWebViewCompat.configureForMultiProcess(this)
    }
}
```

This sets a process-specific WebView data directory suffix to prevent crashes (crbug.com/558377).

---

## iOS — App Tracking Transparency

To unlock IDFA-based targeting (required for Prebid Mobile SDK Mode C):

```swift
import AppTrackingTransparency

ATTrackingManager.requestTrackingAuthorization { status in
    // status == .authorized means IDFA is available
}
```

Add to `Info.plist`:
```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads.</string>
```

ATT authorization must be requested after the app's initial UI has loaded.

---

## Ad Refresh

Control how many times an ad refreshes and at what interval:

```
adRefreshMax: 10        // max refreshes on desktop (web)
adRefreshMaxMobile: 5   // max refreshes on mobile (overrides adRefreshMax)
adRefreshInterval: 30000 // ms between refreshes (React Native / core)
adRefreshIntervalMs: 30000 // Android
adRefreshInterval: Duration(seconds: 30) // Flutter
```

Set `adRefreshMax: 0` and `adRefreshMaxMobile: 0` to disable refresh entirely.

---

## Debugging

Set `debug: true` in your config to enable console logging from the widget:

```ts
config: {
  ...
  debug: true,
}
```

On Android, also enable WebView debugging to inspect the embedded HTML:
```kotlin
WebView.setWebContentsDebuggingEnabled(true) // in Application.onCreate()
```
Then open `chrome://inspect` in Chrome on your dev machine.

On iOS, enable WebView inspection in Safari → Develop → [your device].
