# Quick Start

Get a native marketplace feed or banner ad rendering with server-side header bidding in under 5 minutes. Choose your platform below.

For full integration guides with all ad formats, GDPR, lifecycle management, and troubleshooting, see the dedicated platform pages:
[iOS](/guide/ios) | [Android](/guide/android) | [React Native](/guide/react-native) | [Flutter](/guide/flutter)

---

## iOS (Swift)

### 1. Install

**Swift Package Manager (recommended)** -- In Xcode, **File > Add Package Dependencies** and enter:

```
https://github.com/Antengo/sellwild-sdk.git
```

Pick the **SellwildSDK** library product, rule **Up to Next Major Version** from `1.4.0`. No credentials are required — the repository is public.

**CocoaPods** -- Add to your `Podfile`:

```ruby
target 'YourApp' do
  use_frameworks! :linkage => :static
  pod 'SellwildSDK', '~> 1.4'
end
```

Then run `pod install` and open the `.xcworkspace` file.

### 2. Marketplace Feed ⭐ Recommended

Drop in a full native marketplace feed with listings and interleaved ads — one component, native scrolling, higher CPMs:

**SwiftUI:**

```swift
import SwiftUI
import SellwildSDK

@main
struct MyApp: App {
    @State private var config: SellwildConfig?

    var body: some Scene {
        WindowGroup {
            if let config {
                SellwildFeed(
                    config: config,
                    onLoad: { print("Feed loaded") },
                    onListingTap: { listing in
                        print("Tapped: \(listing.title)")
                        return false // false = SDK opens in-app browser
                    },
                    onAdImpression: { zoneId in print("Ad impression: \(zoneId)") },
                    onError: { error in print("Error: \(error)") }
                )
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            config = await SellwildSDK.configure(
                partnerCode: "weatherbug",
                slug: "weatherbug-weatherbug"
            )
        }
    }
}
```

**UIKit:**

```swift
import UIKit
import SellwildSDK

class FeedViewController: UIViewController, SellwildFeedViewDelegate {
    private var feedView: SellwildFeedView?

    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            let config = await SellwildSDK.configure(
                partnerCode: "weatherbug",
                slug: "weatherbug-weatherbug"
            )
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
            self.feedView = feed
        }
    }

    func sellwildFeedDidLoad(_ feedView: SellwildFeedView) {
        print("Feed loaded")
    }

    func sellwildFeed(_ feedView: SellwildFeedView, didTapListing listing: SellwildListing) -> Bool {
        print("Tapped: \(listing.title)")
        return false // false = SDK opens in SFSafariViewController
    }
}
```

### 3. Banner Ads

For standalone banner placements (320×50, 300×250, etc.):

**SwiftUI:**

```swift
import SwiftUI
import SellwildSDK

struct BannerView: View {
    let config: SellwildConfig

    var body: some View {
        SellwildAdBanner(
            config: config,
            adSize: .mrec300x250,
            onImpression: { print("Ad impression") },
            onError: { error in print("Error: \(error)") }
        )
        .frame(width: 300, height: 250)
    }
}
```

**UIKit:**

```swift
import UIKit
import SellwildSDK

class BannerViewController: UIViewController {
    private var adView: SellwildAdView?

    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            let config = await SellwildSDK.configure(
                partnerCode: "weatherbug",
                slug: "weatherbug-weatherbug"
            )
            let ad = SellwildAdView(config: config, adSize: .mrec300x250)
            ad.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(ad)
            NSLayoutConstraint.activate([
                ad.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                ad.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                ad.widthAnchor.constraint(equalToConstant: 300),
                ad.heightAnchor.constraint(equalToConstant: 250),
            ])
            ad.load()
            self.adView = ad
        }
    }
}
```

**Next:** [Full iOS Guide](/guide/ios) -- ATT, GDPR, lifecycle management, troubleshooting.

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
    implementation("com.sellwild:sdk:1.4.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

### 2. Add permissions

In `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 3. Marketplace Feed ⭐ Recommended

Drop in a full native marketplace feed with listings and interleaved ads — one component, native scrolling, higher CPMs:

**Jetpack Compose:**

```kotlin
import androidx.compose.runtime.*
import androidx.lifecycle.lifecycleScope
import com.sellwild.sdk.*
import kotlinx.coroutines.launch

class FeedActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        lifecycleScope.launch {
            val config = SellwildSDK.configure(
                partnerCode = "weatherbug",
                slug = "weatherbug-weatherbug"
            )
            setContent {
                SellwildFeed(
                    config = config,
                    onLoad = { Log.d("Sellwild", "Feed loaded") },
                    onListingTap = { listing ->
                        Log.d("Sellwild", "Tapped: ${listing.title}")
                        false // false = SDK opens in Custom Tabs
                    },
                    onAdImpression = { zoneId -> Log.d("Sellwild", "Ad impression: $zoneId") },
                    onError = { error -> Log.e("Sellwild", "Error: $error") }
                )
            }
        }
    }
}
```

**XML Views:**

```kotlin
import com.sellwild.sdk.*

class FeedActivity : AppCompatActivity() {
    private lateinit var feedView: SellwildFeedView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        feedView = SellwildFeedView(this)
        setContentView(feedView)

        feedView.listener = object : SellwildFeedView.Listener {
            override fun onLoad() { Log.d("Sellwild", "Feed loaded") }
            override fun onListingTap(listing: SellwildListing): Boolean {
                Log.d("Sellwild", "Tapped: ${listing.title}")
                return false // false = SDK opens in Custom Tabs
            }
            override fun onAdImpression(zoneId: String) {
                Log.d("Sellwild", "Ad impression: $zoneId")
            }
            override fun onError(message: String) {
                Log.e("Sellwild", "Error: $message")
            }
        }

        lifecycleScope.launch {
            val config = SellwildSDK.configure(
                partnerCode = "weatherbug",
                slug = "weatherbug-weatherbug"
            )
            feedView.setup(config)
            feedView.load()
        }
    }
}
```

### 4. Banner Ads

For standalone banner placements (320×50, 300×250, etc.):

```kotlin
import com.sellwild.sdk.*
import kotlinx.coroutines.launch

class BannerActivity : AppCompatActivity() {

    private lateinit var adView: SellwildAdView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        adView = SellwildAdView(this)
        setContentView(adView)

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
                slug = "weatherbug-weatherbug",
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

**Next:** [Full Android Guide](/guide/android) -- Jetpack Compose, ProGuard, GDPR, troubleshooting.

---

## React Native

### 1. Install

```bash
npm install @sellwild/react-native-sdk
cd ios && pod install && cd ..
```

### 2. Marketplace Feed ⭐ Recommended

Drop in a full native marketplace feed — no WebView, native scrolling on both platforms:

```tsx
import React, { useEffect, useState } from 'react';
import { SafeAreaView } from 'react-native';
import {
  SellwildFeed,
  configure,
  type SellwildConfig,
  type SellwildListing,
} from '@sellwild/react-native-sdk';

export default function App() {
  const [config, setConfig] = useState<SellwildConfig | null>(null);

  useEffect(() => {
    configure('weatherbug', 'weatherbug-weatherbug').then(setConfig);
  }, []);

  if (!config) return null;

  return (
    <SafeAreaView style={{ flex: 1 }}>
      <SellwildFeed
        config={config}
        onLoad={() => console.log('Feed loaded')}
        onListingTap={(listing: SellwildListing) => {
          console.log('Tapped:', listing.title);
          return false; // false = SDK opens in in-app browser
        }}
        onAdImpression={(zoneId) => console.log('Ad impression:', zoneId)}
        onError={(err) => console.warn('Feed error:', err.message)}
      />
    </SafeAreaView>
  );
}
```

### 3. Banner Ads

For standalone banner placements:

```tsx
import { SellwildBanner } from '@sellwild/react-native-sdk';

<SellwildBanner
  config={config}
  size="300x250"
  onImpression={() => console.log('Ad impression')}
  onError={(err) => console.warn('Ad error:', err.message)}
/>
```

**Next:** [Full React Native Guide](/guide/react-native) -- TypeScript, Metro config, GDPR, troubleshooting.

---

## Flutter

### 1. Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  sellwild_sdk: ^1.4.0
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

**Android:** Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 3. Render

```dart
import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  SellwildConfig? _config;

  @override
  void initState() {
    super.initState();
    _initSellwild();
  }

  Future<void> _initSellwild() async {
    final config = await SellwildSDK.configure(
      partnerCode: 'weatherbug',
      slug: 'weatherbug-weatherbug',
    );
    setState(() => _config = config);
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SellwildBanner(
      config: _config!,
      size: AdSize.mrec300x250,
      onImpression: () => print('Ad impression'),
      onError: (error) => print('Error: $error'),
    );
  }
}
```

**Next:** [Full Flutter Guide](/guide/flutter) -- Platform setup, GDPR, troubleshooting.

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
runtime field — ad zones, refresh intervals, waterfall partners,
compliance flags, app identity — without an app update.

| Field | Source |
|-------|--------|
| `partnerCode` | You provide it (CMS-provisioned). |
| `slug` | You provide it (CMS-provisioned). |
| `mobileZids`, ad zones, refresh intervals | CDN. |
| `appBundleId`, `appStoreUrl` | CDN, or override in your `configure()` callback. |
| `prebidServer` | Native SDKs (iOS/Android) default to `https://prebid.sellwild.com/openrtb2/auction`. In the TS core / RN, set it explicitly on `SellwildConfig` if you need server-side header bidding from a non-default Prebid Server. |

## Next Steps

- [Architecture](/guide/architecture) -- how the SDK works internally
- [Configuration Reference](/guide/configuration) -- every config field documented
- [Privacy & Consent](/guide/privacy) -- GDPR, CCPA, ATT, app-ads.txt
- [API Reference](/guide/api-reference) -- per-platform class and method reference
