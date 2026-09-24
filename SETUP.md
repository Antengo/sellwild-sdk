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
npm install @sellwild/react-native-sdk
# or
yarn add @sellwild/react-native-sdk
```

### 2. iOS — install pods (React Native 0.60+, auto-linking handles the native module)

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
import { configure, SellwildFeed, SellwildBanner } from '@sellwild/react-native-sdk'

const config = await configure('mysite', 'mysite-main')

// All-in-one native feed (listings + interleaved ads)
<SellwildFeed
  config={config}
  style={{ flex: 1 }}
  // consumeListingTaps: you handle the tap; omit it and the SDK opens
  // listing.url in-app instead
  consumeListingTaps
  onListingTap={(listing) => {
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

Ad creatives load from Google and third-party ad networks. Add:
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

        // All-in-one native feed (listings + interleaved ads)
        let feed = SellwildFeedView(config: config)
        feed.delegate = self
        feed.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(feed)

        NSLayoutConstraint.activate([
            feed.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            feed.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feed.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            feed.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        feed.load()
    }
}

extension MyViewController: SellwildFeedViewDelegate {
    // Return false to let the SDK open listing.url in SFSafariViewController.
    func sellwildFeed(_ feed: SellwildFeedView, didTapListing listing: SellwildListing) -> Bool {
        false
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
        SellwildFeed(config: config)   // SDK opens listing taps in SFSafariViewController
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

        // All-in-one native feed (listings + interleaved ads)
        val feed = SellwildFeedView(this)
        feed.setup(config)
        feed.listener = object : SellwildFeedView.Listener {
            // Return false to let the SDK open listing.url in Chrome Custom Tabs.
            override fun onListingTap(listing: SellwildListing): Boolean = false
        }

        setContentView(feed)
        feed.load()
    }
}
```

**Lifecycle — standalone banners:** forward pause/resume/destroy to each `SellwildAdView`:
```kotlin
override fun onResume() { super.onResume(); banner.resume() }
override fun onPause()  { super.onPause();  banner.pause()  }
override fun onDestroy(){ super.onDestroy(); banner.destroy() }
```

### 4. Coroutines — fetch listings and render your own UI

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

The native banner path (Prebid Mobile → Google Mobile Ads) supports two demand mechanisms:

| Mechanism | Config Key | Notes |
|-----------|-----------|-------|
| Google Ad Manager | `gamTag` | Header-bidding auction runs in-process via Prebid Mobile; the winner renders in `AdManagerBannerView` / `AdManagerAdView` (GMA). |
| Zone-based (Bidstream) | `bannerZid`, `mobileZids`, etc. | Direct zone ID delivery |

**You must set at least one** of `gamTag` or a zone ID for ads to render. If both are set, GAM takes priority unless `disableGpt: true`.

---

## In-app signals (native path)

Prebid Mobile builds the OpenRTB request in-process and forwards real in-app signals automatically:

1. **ortb2.app** — set `appBundleId` (your iOS bundle ID or Android package name) and `appStoreUrl` in `SellwildConfig` so the auction carries `app.bundle` / `app.storeurl`. Prebid Mobile sends `app{}` (not `site{}`) natively.

2. **Device + consent** — IDFV / AAID, ATT status, and the IAB consent strings your CMP writes to device storage are read and forwarded by Prebid Mobile / GMA automatically. Initialize your CMP **before** the first ad request.

3. **Prebid Server S2S** — the auction resolves server-to-server through `prebid.sellwild.com`. No third-party cookies required.

**Full Prebid documentation:** [PREBID.md](./PREBID.md)

---

## Android — Multi-process WebView (API 28+)

GMA and Prebid render ad creatives in WebViews. If your app uses multiple
processes, call this before any WebView is created:

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

Set `debug: true` in your config to enable verbose SDK and Prebid Mobile logging:

```ts
config: {
  ...
  debug: true,
}
```

For server-side auction detail (per-bidder status, resolved request), also set `pbsDebug: true`. See [PREBID.md](./PREBID.md#debug-flags--debug-vs-pbsdebug).
