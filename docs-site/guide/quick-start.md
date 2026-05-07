# Quick Start

Get a 300x250 MREC ad rendering with server-side header bidding in under 5 minutes. Choose your platform below.

For full integration guides with all ad formats, listing cards, GDPR, lifecycle management, and troubleshooting, see the dedicated platform pages:
[iOS](/guide/ios) | [Android](/guide/android) | [React Native](/guide/react-native) | [Flutter](/guide/flutter)

---

## iOS (Swift)

### 1. Install

**CocoaPods** -- Add to your `Podfile`:

```ruby
pod 'SellwildSDK', '~> 1.3'
```

Then run `pod install` and open the `.xcworkspace` file.

### 2. Configure

```swift
import SellwildSDK

// Partner code + slug. Everything else — listings URL, ad zones, app
// identity, refresh intervals, waterfall partners, compliance flags — is
// fetched from the Sellwild CDN at app launch. On any network/timeout/404
// failure the SDK falls back to deterministic defaults so ads still render.
let config = await SellwildSDK.configure(
    partnerCode: "weatherbug",
    slug: "weatherbug-main"
) { c in
    // Override CDN with app-controlled values.
    c.appBundleId = Bundle.main.bundleIdentifier ?? "com.example.myapp"
}
```

::: details Static config (no network at startup)
If you can't make a network call before rendering ads (e.g. an offline-first
app), build a `SellwildConfig` directly:

```swift
var config = SellwildConfig(partnerCode: "weatherbug")
config.appBundleId = Bundle.main.bundleIdentifier
// Set listingsUrl, prebidServer, ad zones, etc. by hand.
```
:::

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
    implementation("com.sellwild:sdk:1.3.0")
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
import kotlinx.coroutines.launch

class AdActivity : AppCompatActivity() {

    private lateinit var adView: SellwildAdView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        adView = SellwildAdView(this)
        setContentView(adView)

        // Partner code + slug. Everything else — listings URL, ad zones, app
        // identity, refresh intervals, waterfall partners, compliance flags —
        // is fetched from the Sellwild CDN at app launch. On any network or
        // 404 failure the SDK falls back to deterministic defaults so ads
        // still render.
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

        lifecycleScope.launch {
            val config = SellwildSDK.configure(
                partnerCode = "weatherbug",
                slug = "weatherbug-main",
            ) { c -> c.copy(appBundleId = packageName) }
            adView.setup(config, AdSize.MREC_300x250)
            adView.load()
        }
    }

    override fun onPause() { super.onPause(); adView.pause() }
    override fun onResume() { super.onResume(); adView.resume() }
    override fun onDestroy() { adView.destroy(); super.onDestroy() }
}
```

::: details Static config (no network at startup)
If you can't make a network call before rendering ads, build a `SellwildConfig`
directly:

```kotlin
val config = SellwildConfig(
    partnerCode = "weatherbug",
    listingsUrl = "https://api.sellwild.com/widget/listings?partner=weatherbug",
    appBundleId = packageName,
)
```
:::

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
import React, { useEffect, useState } from 'react';
import { SafeAreaView } from 'react-native';
import {
  SellwildBanner,
  configure,
  type SellwildConfig,
} from '@sellwild/react-native-sdk';

export default function App() {
  const [config, setConfig] = useState<SellwildConfig | null>(null);

  useEffect(() => {
    // Partner code + slug. Everything else — listings URL, ad zones, app
    // identity, refresh intervals, waterfall partners, compliance flags — is
    // fetched from the Sellwild CDN at app launch. On any network/timeout/
    // 404 failure the SDK falls back to deterministic defaults so ads still
    // render.
    configure('weatherbug', 'weatherbug-main').then(setConfig);
  }, []);

  if (!config) return null;

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

::: details Static config (no network at startup)
```tsx
import { buildConfig } from '@sellwild/react-native-sdk';
const config = buildConfig({
  partnerCode: 'weatherbug',
  listingsUrl: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
});
```
:::

**Next:** [Full React Native Guide](/guide/react-native) -- listing cards, `useSellwildListings` hook, direct auction API, Metro config, GDPR.

---

## Flutter

### 1. Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  sellwild_sdk: ^1.3.0
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

class AdScreen extends StatefulWidget {
  const AdScreen({super.key});
  @override
  State<AdScreen> createState() => _AdScreenState();
}

class _AdScreenState extends State<AdScreen> {
  SellwildConfig? config;

  @override
  void initState() {
    super.initState();
    // Partner code + slug. Everything else — listings URL, ad zones, app
    // identity, refresh intervals, waterfall partners, compliance flags — is
    // fetched from the Sellwild CDN at app launch.
    SellwildSDK.configure(
      partnerCode: 'weatherbug',
      slug: 'weatherbug-main',
    ).then((c) => setState(() => config = c));
  }

  @override
  Widget build(BuildContext context) {
    if (config == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Ad Demo')),
      body: Center(
        child: SellwildBanner(
          config: config!,
          adSize: SellwildAdSize.mrec300x250,
          onImpression: () => debugPrint('Ad impression'),
          onError: (error) => debugPrint('Ad error: $error'),
        ),
      ),
    );
  }
}
```

::: details Static config (no network at startup)
```dart
final config = SellwildConfig(
  partnerCode: 'weatherbug',
  listingsUrl: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
);
```
:::

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

## What `configure()` provides

In 1.2.0+, `configure(partnerCode, slug)` is the first-class integration path.
The SDK fetches a JSON document from the Sellwild CDN at
`https://widget.sellwild.com/app/{partnerCode}/{slug}.json` and populates every
runtime field — listings URL, ad zones, refresh intervals, waterfall partners,
compliance flags, app identity — without an app update.

| Field | Source |
|-------|--------|
| `partnerCode` | You provide it (CMS-provisioned). |
| `slug` | You provide it (CMS-provisioned). |
| `listingsUrl` | CDN. Falls back to `${apiBaseUrl}/widget/listings?partner=${partnerCode}` if absent. |
| `mobileZids`, ad zones, refresh intervals | CDN. |
| `appBundleId`, `appStoreUrl` | CDN, or override in your `configure()` callback. |
| `prebidServer` | CDN. Required for server-side header bidding. |

## Next Steps

- [Architecture](/guide/architecture) -- how the SDK works internally
- [Configuration Reference](/guide/configuration) -- every config field documented
- [Privacy & Consent](/guide/privacy) -- GDPR, CCPA, ATT, app-ads.txt
- [API Reference](/guide/api-reference) -- per-platform class and method reference
