# Quick Start

Get a 300x250 MREC ad rendering with server-side header bidding in under 5 minutes. Choose your platform below.

For full integration guides with all ad formats, listing cards, GDPR, lifecycle management, and troubleshooting, see the dedicated platform pages:
[iOS](/guide/ios) | [Android](/guide/android) | [React Native](/guide/react-native) | [Flutter](/guide/flutter)

---

## iOS (Swift)

### 1. Install

**CocoaPods** -- Add to your `Podfile`:

```ruby
pod 'SellwildSDK', '~> 1.0'
```

Then run `pod install` and open the `.xcworkspace` file.

### 2. Configure

```swift
import SellwildSDK

let config: SellwildConfig = {
    var c = SellwildConfig(
        partnerCode: "weatherbug",
        listingsUrl: "https://api.sellwild.com/widget/listings?partner=weatherbug"
    )
    c.appBundleId = Bundle.main.bundleIdentifier ?? "com.example.myapp"
    c.appStoreUrl = "https://apps.apple.com/app/id1234567890"
    c.prebidServer = PrebidServerConfig(
        accountId: "weatherbug-prod",
        endpoint: "https://prebid.sellwild.com/openrtb2/auction",
        bidders: ["appnexus", "rubicon", "ix", "openx"],
        timeout: 1500
    )
    return c
}()
```

### 3. Render (SwiftUI)

```swift
import SwiftUI
import SellwildSDK

struct ContentView: View {
    var body: some View {
        SellwildAdBanner(
            config: config,
            adSize: .mrec300x250,
            onImpression: {
                print("Ad impression recorded")
            },
            onError: { error in
                print("Ad error: \(error.localizedDescription)")
            }
        )
        .frame(width: 300, height: 250)
    }
}
```

### 3b. Render (UIKit)

```swift
let adView = SellwildAdView(config: config, adSize: .mrec300x250)
adView.delegate = self
view.addSubview(adView)
// Add constraints: 300pt wide, 250pt tall
adView.load()
```

That is it. The SDK handles the Prebid Server auction, creative rendering, impression tracking, and ad refresh.

**Next:** [Full iOS Guide](/guide/ios) -- ATT, GDPR, lifecycle management, native listing cards, troubleshooting.

---

## Android (Kotlin)

### 1. Install

Add the Sellwild Maven repository to `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.sellwild.com/releases") }
    }
}
```

Add the dependency to `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.sellwild:sdk:1.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

### 2. Add permissions

In `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 3. Render

```kotlin
import com.sellwild.sdk.*

class AdActivity : AppCompatActivity() {

    private lateinit var adView: SellwildAdView

    private val config = SellwildConfig(
        partnerCode = "weatherbug",
        listingsUrl = "https://api.sellwild.com/widget/listings?partner=weatherbug",
        appBundleId = "com.aws.android",
        appStoreUrl = "https://play.google.com/store/apps/details?id=com.aws.android",
        prebidServer = PrebidServerConfig(
            accountId = "sellwild",
            endpoint = "https://prebid.sellwild.com/openrtb2/auction",
            bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx"),
            timeout = 1500
        )
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        adView = SellwildAdView(this)
        adView.setup(config, AdSize.MREC_300x250)
        adView.listener = object : SellwildAdView.Listener {
            override fun onAdLoaded(adView: SellwildAdView) {
                Log.d("Sellwild", "Ad loaded")
            }
            override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                Log.d("Sellwild", "Impression: zone=$zoneId")
            }
            override fun onAdFailed(adView: SellwildAdView, message: String) {
                Log.e("Sellwild", "Ad failed: $message")
            }
        }

        setContentView(adView)
        adView.load()
    }

    override fun onPause() { super.onPause(); adView.pause() }
    override fun onResume() { super.onResume(); adView.resume() }
    override fun onDestroy() { adView.destroy(); super.onDestroy() }
}
```

**Next:** [Full Android Guide](/guide/android) -- Jetpack Compose, ProGuard rules, multi-process WebView, GDPR, listing cards.

---

## React Native

### 1. Install

```bash
npm install @sellwild/react-native-sdk react-native-webview
cd ios && pod install && cd ..
```

### 2. Render

```tsx
import React from 'react';
import { SafeAreaView } from 'react-native';
import { SellwildBanner, buildConfig } from '@sellwild/react-native-sdk';

const config = buildConfig({
  partnerCode: 'weatherbug',
  listingsUrl: 'https://api.sellwild.com/listings/weatherbug',
  appBundleId: 'com.aws.android',
  appStoreUrl: 'https://play.google.com/store/apps/details?id=com.aws.android',
  prebidServer: {
    accountId: 'weatherbug',
    endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
    bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
    timeout: 1500,
  },
});

export default function App() {
  return (
    <SafeAreaView style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <SellwildBanner
        config={config}
        size="300x250"
        zoneId="your-zone-id"
        onImpression={() => console.log('Ad impression')}
        onError={(err) => console.warn('Ad error:', err.message)}
      />
    </SafeAreaView>
  );
}
```

**Next:** [Full React Native Guide](/guide/react-native) -- listing cards, `useSellwildListings` hook, direct auction API, Metro config, GDPR.

---

## Flutter

### 1. Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  sellwild_sdk: ^1.1.0
```

Then run:

```bash
flutter pub get
```

### 2. Platform setup

**iOS:** Add to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoadsInWebContent</key>
  <true/>
</dict>
```

**Android:** Ensure `android/app/build.gradle` has `minSdkVersion 21`.

### 3. Render

```dart
import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

class AdScreen extends StatelessWidget {
  const AdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = SellwildConfig(
      partnerCode: 'weatherbug',
      listingsUrl: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
      appBundleId: 'com.aws.android',
      appStoreUrl: 'https://play.google.com/store/apps/details?id=com.aws.android',
      prebidServer: PrebidServerConfig(
        accountId: 'weatherbug',
        endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
        bidders: ['appnexus', 'pubmatic', 'ix', 'rubicon', 'openx'],
        timeout: 1500,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Ad Demo')),
      body: Center(
        child: SellwildBanner(
          config: config,
          adSize: SellwildAdSize.mrec300x250,
          onImpression: () => debugPrint('Ad impression'),
          onError: (error) => debugPrint('Ad error: $error'),
        ),
      ),
    );
  }
}
```

**Next:** [Full Flutter Guide](/guide/flutter) -- widget reference, `SellwildAPIClient`, listing cards, GDPR, troubleshooting.

---

## What Happens Next

After `load()` is called (or the SwiftUI/Compose view appears), the SDK:

1. Builds a lightweight WebView with Prebid.js configured in S2S mode.
2. Sends a single OpenRTB request to `prebid.sellwild.com/openrtb2/auction`.
3. Prebid Server fans out to all configured SSPs in parallel.
4. The winning bid's creative renders in the ad slot.
5. Impression and click events fire through the JS bridge to your native callbacks.

No client-side bidder SDKs. No waterfall. No cookies. Total auction time: under 200ms.

## Required Fields

Every integration must set these fields for proper in-app traffic classification:

| Field | Why |
|-------|-----|
| `partnerCode` | Identifies your account. |
| `listingsUrl` | API endpoint for marketplace listings. |
| `appBundleId` | Sent as `ortb2.app.bundle`. Without this, DSPs classify traffic as web and will not bid. |
| `appStoreUrl` | Sent as `ortb2.app.storeurl`. Required for app-ads.txt verification. |
| `prebidServer` | Enables server-side header bidding through Prebid Server. |

## Next Steps

- [Architecture](/guide/architecture) -- how the SDK works internally
- [Configuration Reference](/guide/configuration) -- every config field documented
- [Privacy & Consent](/guide/privacy) -- GDPR, CCPA, ATT, app-ads.txt
- [API Reference](/guide/api-reference) -- per-platform class and method reference
- [Validation Report](/guide/validation) -- known issues, platform-specific fixes, testing checklist
