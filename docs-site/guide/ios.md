# Sellwild SDK for iOS

Integration guide for the Sellwild native ad SDK. The SDK runs server-side header bidding through Prebid Server, delivering display ads and marketplace listing cards natively on iOS.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Native banner path (1.3.0+)](#native-banner-path-1-3-0)
4. [Native Marketplace Feed (1.3.5+)](#native-marketplace-feed-1-3-5)
5. [Info.plist Configuration](#infoplist-configuration)
6. [UIKit Integration](#uikit-integration)
7. [SwiftUI Integration](#swiftui-integration)
8. [Native Listing Cards](#native-listing-cards)
9. [App Tracking Transparency](#app-tracking-transparency)
10. [Remote Config](#remote-config)
11. [Prebid Server Configuration](#prebid-server-configuration)
12. [GDPR and Privacy](#gdpr-and-privacy)
13. [Ad Refresh](#ad-refresh)
14. [Lifecycle Management](#lifecycle-management)
15. [Troubleshooting](#troubleshooting)
16. [API Reference](#api-reference)

---

## Prerequisites

| Requirement | Minimum Version |
|-------------|-----------------|
| Xcode | 16.0 or later (required for PrebidMobile 3.x) |
| iOS deployment target | 13.0 |
| Swift | 5.5 or later |
| macOS (build host) | 14.0 (Sonoma) |

As of 1.3.2 the SDK supports `PrebidMobile` `>= 3.0.1, < 4.0` and `Google-Mobile-Ads-SDK` `>= 12.0, < 14.0` for native banner rendering. Both are pulled in transitively by CocoaPods / SPM; no additional declaration is required. If your app already pins to a specific version of GMA (12.x or 13.x) or Prebid Mobile (3.x), the SDK will resolve against it. The marketplace `SellwildWidget` continues to use `WebKit`, which ships with iOS.

::: tip Upgrading from GMA 11.x
SellwildSDK requires `Google-Mobile-Ads-SDK` 12.0 or newer. If your project is still on GMA 11.x, see Google's [11.x → 12.x migration guide](https://developers.google.com/admob/ios/migration). You do not need to jump to GMA 13.x — 12.x is fully supported.
:::

---

## Installation

The SDK is available through both Swift Package Manager and CocoaPods. SPM is the recommended path for new integrations. Pick one — don't mix them in the same project.

### Swift Package Manager (recommended)

1. In Xcode, select **File > Add Package Dependencies**.
2. Enter the repository URL:

```
https://github.com/Antengo/sellwild-sdk.git
```

3. Set the dependency rule to **Up to Next Major Version** starting at `1.4.0`.
4. Select the **SellwildSDK** library product and add it to your app target.

No credentials are required — the repository is public. Xcode will resolve `SellwildSDK`, `PrebidMobile`, `GoogleMobileAds`, and `GoogleUserMessagingPlatform` automatically.

If you prefer to declare the dependency in a `Package.swift` manifest:

```swift
dependencies: [
    .package(
        url: "https://github.com/Antengo/sellwild-sdk.git",
        from: "1.4.0"
    )
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SellwildSDK", package: "sellwild-sdk")
        ]
    )
]
```

### CocoaPods

Add the following to your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourApp' do
  use_frameworks! :linkage => :static

  pod 'SellwildSDK', '~> 1.4.2'
end
```

`:linkage => :static` is required because `Google-Mobile-Ads-SDK` and `GoogleUserMessagingPlatform` are distributed as static binaries.

::: tip Coexisting with your own Prebid integration
Starting in 1.4.2, SellwildSDK uses a namespace-shaded fork of Prebid Mobile (`SellwildPrebid`) so Sellwild ads can coexist with your own `PrebidMobile` pod without singleton conflicts. `SellwildPrebid` and `SellwildPrebidGAMEventHandlers` are pulled in automatically from the CocoaPods trunk.
:::

Then run:

```bash
pod install
```

Open the generated `.xcworkspace` file to continue development.

---

## Native banner path (1.3.0+)

As of 1.3.0, `SellwildAdView` no longer renders banner creatives in a WebView. It hosts a native `AdManagerBannerView` (Google Mobile Ads SDK) and runs a Prebid Mobile auction in-process before loading the GAM view.

- **First-use bootstrap.** The first time a `SellwildAdView` is created, `SellwildPrebidMobile.bootstrap()` initializes Prebid Mobile (host, account ID, timeouts) using values from `SellwildConfig.prebidServer`. Subsequent ad views reuse the initialized stack.
- **Auction flow.** `SellwildAdView.load()` builds an OpenRTB request with PrebidMobile, sends it to `prebid.sellwild.com`, applies the winning bid's keywords as targeting on a `GAMRequest`, then calls `AdManagerBannerView.load(_:)`. The GAM SDK selects between the Prebid line item and any direct-sold demand and renders natively.
- **Required Info.plist key.** GMA will not initialize without `GADApplicationIdentifier`. See [Info.plist Configuration](#infoplist-configuration) below.
- **Marketplace listings.** `SellwildWidgetView` (the marketplace listings surface) is a separate component and is not part of the ad path. If your integration only requires banner ads, you do not need to use it.

If you want to bypass the native ad path entirely and consume bids yourself, see [Direct Prebid Server Auction](#prebid-server-configuration).

---

## Native Marketplace Feed (1.3.5+)

`SellwildFeedView` renders a full-screen native marketplace feed with listings and interleaved Prebid + GAM ads. It uses `UITableView` internally — no WebView in the rendering path.

The feed layout is driven by your CDN config's `COL1` schedule (e.g., `"LLGLLGLLG"` = listing, listing, GAM ad, repeat). Listings are fetched from your configured listings endpoint; ads run the same Prebid → GAM auction as `SellwildAdView`.

### SwiftUI

```swift
import SwiftUI
import SellwildSDK

struct MarketplaceView: View {
    let config: SellwildConfig

    var body: some View {
        SellwildFeed(
            config: config,
            onLoad: { print("Feed loaded") },
            onListingTap: { listing in
                print("Tapped: \(listing.title)")
                return false // false = SDK opens in SFSafariViewController
            },
            onAdImpression: { zoneId in print("Ad impression: \(zoneId)") },
            onAdClicked: { zoneId in print("Ad clicked: \(zoneId)") },
            onError: { error in print("Feed error: \(error)") }
        )
    }
}
```

### UIKit

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

    // MARK: - SellwildFeedViewDelegate

    func sellwildFeedDidLoad(_ feedView: SellwildFeedView) {
        print("Feed loaded with \(feedView.listingCount) listings")
    }

    func sellwildFeed(_ feedView: SellwildFeedView, didTapListing listing: SellwildListing) -> Bool {
        print("Tapped: \(listing.title) - \(listing.formattedPrice)")
        return false // false = SDK opens in SFSafariViewController
    }

    func sellwildFeed(_ feedView: SellwildFeedView, didRecordAdImpressionForZoneId zoneId: String) {
        print("Ad impression: \(zoneId)")
    }

    func sellwildFeed(_ feedView: SellwildFeedView, didRecordAdClickForZoneId zoneId: String) {
        print("Ad clicked: \(zoneId)")
    }

    func sellwildFeed(_ feedView: SellwildFeedView, didFailWithError error: Error) {
        print("Feed error: \(error.localizedDescription)")
    }
}
```

### Listing Tap Handling

The `didTapListing` delegate method returns a `Bool`:

- **Return `false`** (recommended): The SDK opens the listing URL in `SFSafariViewController`. This matches the WebView widget behavior.
- **Return `true`**: You handle navigation yourself. The SDK does nothing.

### Feed Configuration

The feed respects these CDN config keys:

| Key | Description |
|-----|-------------|
| `COL1` | Row schedule string (e.g., `"LLGLLGLLG"` — L=listing, G=GAM ad) |
| `LISTINGS` | URL to fetch listing JSON |
| `TITLE` | Header title (default: "Marketplace") |
| `BG_COLOR` | Background color (hex, e.g., `"#F5F5F5"`) |
| `MOBILE_ZIDS` | Array of zone IDs for interleaved ads |

---

## Info.plist Configuration

### Google Mobile Ads Application Identifier (required, 1.3.0+)

The Google Mobile Ads SDK refuses to initialize without `GADApplicationIdentifier`. Add your AdMob/Ad Manager app ID to `Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
```

Use **your own** AdMob / Ad Manager app ID — the one you already use for your iOS app. Google Mobile Ads is initialized once per process, so the SDK reuses your host app's `GADApplicationIdentifier`; Sellwild does not issue or override it. Ad unit / zone IDs come from your Sellwild CDN config (`widget.sellwild.com/app/{partnerCode}/{slug}.json`) and map to GAM ad units on our side.

- **Self-managed inventory (most common):** Register your app at [admanager.google.com](https://admanager.google.com) or [apps.admob.com](https://apps.admob.com); Google issues a `ca-app-pub-...~...` ID.
- **Managed inventory:** If Sellwild operates your GAM network, your account manager will provision the app ID for you.
- **Development only:** Google's sample ID `ca-app-pub-3940256099942544~1458002511` works for local builds but **must not** ship to the App Store.

Apps submitted without this key will crash on first ad load.

### App Transport Security

The SDK loads ad creatives from several domains over HTTPS. If your app enforces strict ATS, add domain exceptions for the required hosts. The recommended approach uses per-domain exceptions rather than a blanket allow.

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>sellwild.com</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
        <key>doubleclick.net</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
        <key>googlesyndication.com</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

If your app already disables ATS globally, no additional configuration is needed:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

> **Note:** Apple requires justification for `NSAllowsArbitraryLoads` during App Store review. Per-domain exceptions are preferred for production submissions.

### App Tracking Transparency Usage Description

If you intend to collect the IDFA for ad targeting (see [App Tracking Transparency](#app-tracking-transparency)), add a usage description:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier is used to deliver personalized ads and measure ad performance.</string>
```

---

## UIKit Integration

The following example demonstrates a complete `UIViewController` that displays a 300x250 MREC ad and a 320x50 banner ad using server-side header bidding through Prebid Server.

### Quick Start (copy-paste this)

```swift
import UIKit
import SellwildSDK

class AdViewController: UIViewController {
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

### Full Example (static config, for reference)

The example below shows every configurable field. Most integrations don't need this — just use `configure()` above.

```swift
import UIKit
import SellwildSDK

final class AdViewController: UIViewController {

    // MARK: - Configuration

    // Static example. In production prefer:
    //   let config = await SellwildSDK.configure(
    //       partnerCode: "weatherbug",
    //       slug: "weatherbug-weatherbug"
    //   )
    private lazy var config: SellwildConfig = {
        var c = SellwildConfig(partnerCode: "weatherbug")

        // App identity for OpenRTB ortb2.app signals
        c.appBundleId = Bundle.main.bundleIdentifier ?? "com.example.myapp"
        c.appStoreUrl = "https://apps.apple.com/app/id1234567890"

        // Prebid Server S2S configuration
        c.prebidServer = PrebidServerConfig(
            accountId: "weatherbug-prod",
            endpoint: "https://prebid.sellwild.com/openrtb2/auction",
            bidders: ["appnexus", "rubicon", "ix", "openx"],
            timeout: 1500
        )

        // Ad refresh
        c.adRefreshMaxMobile = 10
        c.adRefreshInterval = 30.0

        return c
    }()

    // MARK: - Ad Views

    private lazy var mrecAdView: SellwildAdView = {
        let view = SellwildAdView(config: config, adSize: .mrec300x250)
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var bannerAdView: SellwildAdView = {
        let view = SellwildAdView(config: config, adSize: .banner320x50)
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        layoutAdViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        mrecAdView.load()
        bannerAdView.load()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        mrecAdView.pause()
        bannerAdView.pause()
    }

    // MARK: - Layout

    private func layoutAdViews() {
        view.addSubview(mrecAdView)
        view.addSubview(bannerAdView)

        NSLayoutConstraint.activate([
            // 300x250 MREC — centered horizontally, pinned to top safe area
            mrecAdView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16
            ),
            mrecAdView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mrecAdView.widthAnchor.constraint(equalToConstant: 300),
            mrecAdView.heightAnchor.constraint(equalToConstant: 250),

            // 320x50 banner — centered horizontally, pinned to bottom safe area
            bannerAdView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8
            ),
            bannerAdView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerAdView.widthAnchor.constraint(equalToConstant: 320),
            bannerAdView.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
}

// MARK: - SellwildAdViewDelegate

extension AdViewController: SellwildAdViewDelegate {

    func sellwildAdViewDidLoad(_ adView: SellwildAdView) {
        let label = adView === mrecAdView ? "MREC" : "Banner"
        print("[Sellwild] \(label) ad loaded")
    }

    func sellwildAdView(
        _ adView: SellwildAdView,
        didReceiveImpressionForZoneId zoneId: String
    ) {
        print("[Sellwild] Impression recorded for zone: \(zoneId)")
    }

    func sellwildAdViewDidRecordClick(_ adView: SellwildAdView) {
        print("[Sellwild] Ad clicked")
    }

    func sellwildAdView(_ adView: SellwildAdView, didFailWithError error: Error) {
        print("[Sellwild] Ad error: \(error.localizedDescription)")
    }
}
```

### Key Points

- Call `load()` after the view has been added to the view hierarchy (in `viewDidAppear` or later).
- Call `pause()` in `viewDidDisappear` to stop refresh timers and conserve resources.
- `SellwildAdView` manages its own underlying `AdManagerBannerView`; do not add subviews or modify its frame directly.

---

## SwiftUI Integration

The SDK provides `SellwildAdBanner` and `SellwildWidget` as native SwiftUI views. Both require iOS 14 or later.

### Quick Start (copy-paste this)

```swift
import SwiftUI
import SellwildSDK

@main
struct MyApp: App {
    @State private var config: SellwildConfig?

    var body: some Scene {
        WindowGroup {
            if let config {
                AdContentView(config: config)
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

struct AdContentView: View {
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

### Full Example (static config, for reference)

The example below shows every configurable field. Most integrations don't need this — just use `configure()` above.

```swift
import SwiftUI
import SellwildSDK

struct AdContentView: View {

    private let config: SellwildConfig = {
        var c = SellwildConfig(partnerCode: "weatherbug")
        c.appBundleId = Bundle.main.bundleIdentifier ?? "com.example.myapp"
        c.appStoreUrl = "https://apps.apple.com/app/id1234567890"
        c.prebidServer = PrebidServerConfig(
            accountId: "weatherbug-prod",
            endpoint: "https://prebid.sellwild.com/openrtb2/auction",
            bidders: ["appnexus", "rubicon", "ix", "openx"],
            timeout: 1500
        )
        c.adRefreshMaxMobile = 10
        c.adRefreshInterval = 30.0
        return c
    }()

    var body: some View {
        VStack(spacing: 0) {
            // 300x250 MREC
            SellwildAdBanner(
                config: config,
                adSize: .mrec300x250,
                onImpression: {
                    print("[Sellwild] MREC impression")
                },
                onError: { error in
                    print("[Sellwild] MREC error: \(error.localizedDescription)")
                }
            )
            .frame(width: 300, height: 250)

            Spacer()

            // Listing widget
            SellwildWidget(
                config: config,
                onListingTap: { listing in
                    if let url = listing.url, let link = URL(string: url) {
                        UIApplication.shared.open(link)
                    }
                },
                onLoad: {
                    print("[Sellwild] Widget loaded")
                },
                onError: { error in
                    print("[Sellwild] Widget error: \(error.localizedDescription)")
                }
            )
            .frame(height: 400)

            // 320x50 banner at the bottom
            SellwildAdBanner(
                config: config,
                adSize: .banner320x50,
                onImpression: {
                    print("[Sellwild] Banner impression")
                },
                onError: { error in
                    print("[Sellwild] Banner error: \(error.localizedDescription)")
                }
            )
            .frame(width: 320, height: 50)
        }
    }
}
```

> **Note:** `SellwildAdBanner` is a `UIViewRepresentable` wrapper around `SellwildAdView`. It calls `load()` automatically when the view appears. Refresh timers are managed internally.

---

## Native Listing Cards

Use `SellwildAPIClient` to fetch marketplace listings and render them with your own UI. This approach gives full control over layout, styling, and interaction.

```swift
import UIKit
import SellwildSDK

final class ListingsViewController: UIViewController {

    private let config = SellwildConfig(partnerCode: "weatherbug")

    private var listings: [SellwildListing] = []
    private let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Marketplace"
        configureTableView()
        fetchListings()
    }

    private func configureTableView() {
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ListingCell")
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
    }

    private func fetchListings() {
        SellwildAPIClient.shared.fetchListings(config: config) { [weak self] result in
            switch result {
            case .success(let response):
                self?.listings = response.listings
                self?.tableView.reloadData()
            case .failure(let error):
                print("[Sellwild] Failed to fetch listings: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension ListingsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        listings.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ListingCell", for: indexPath)
        let listing = listings[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = listing.title
        content.secondaryText = listing.displayPrice.map { "$\($0)" }
        cell.contentConfiguration = content

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let listing = listings[indexPath.row]
        if let urlString = listing.url, let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
```

### Async/Await (iOS 15+)

```swift
func fetchListings() async {
    do {
        let response = try await SellwildAPIClient.shared.fetchListings(config: config)
        self.listings = response.listings
        tableView.reloadData()
    } catch {
        print("[Sellwild] Fetch error: \(error.localizedDescription)")
    }
}
```

### Listing Data Model

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique listing identifier |
| `title` | `String` | Listing title |
| `price` | `String?` | Raw price string |
| `displayPrice` | `String?` | Formatted price (computed, excludes zero values) |
| `photos` | `[SellwildPhoto]?` | Array of photo objects with `url` and `thumbUrl` |
| `primaryPhoto` | `SellwildPhoto?` | First photo (computed convenience accessor) |
| `url` | `String?` | Deep link to the listing detail page |
| `user` | `SellwildUser?` | Seller information |
| `distance` | `Double?` | Distance from the user, if available |
| `createdDate` | `String?` | ISO 8601 creation timestamp |

---

## App Tracking Transparency

On iOS 14.5 and later, you must request ATT authorization before accessing the IDFA. The IDFA improves ad targeting and fill rates when passed through Prebid Server.

```swift
import AppTrackingTransparency
import AdSupport

func requestTrackingAuthorization() {
    guard #available(iOS 14.5, *) else { return }

    ATTrackingManager.requestTrackingAuthorization { status in
        DispatchQueue.main.async {
            switch status {
            case .authorized:
                let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                print("[Sellwild] IDFA: \(idfa)")
                // Pass IDFA to your Prebid Server via ortb2.user.eids
                // or configure via PrebidMobile if using Mode C.

            case .denied, .restricted:
                print("[Sellwild] Tracking denied. Ads will serve without IDFA.")

            case .notDetermined:
                print("[Sellwild] Tracking not yet determined.")

            @unknown default:
                break
            }
        }
    }
}
```

### Recommended Timing

Call `requestTrackingAuthorization()` after your app has loaded its initial UI. Presenting the ATT prompt on first launch before any context is shown may result in lower opt-in rates. A common pattern is to request authorization in `viewDidAppear` of your first content screen, or after a brief onboarding flow.

> **Important:** The ATT prompt can only be presented once per install. Subsequent calls return the cached status without showing the dialog. Always check `ATTrackingManager.trackingAuthorizationStatus` before presenting ad UI that depends on the IDFA.

---

## Remote Config (the first-class path)

`SellwildSDK.configure(partnerCode:slug:)` is the recommended way to integrate the SDK. It fetches a JSON document from the Sellwild CDN at app launch and returns a fully-built `SellwildConfig` — ad zones, refresh intervals, app identity, waterfall partners, compliance flags, and more — so you can change everything without an app update.

```swift
import SellwildSDK

Task {
    let config = await SellwildSDK.configure(
        partnerCode: "weatherbug",
        slug: "weatherbug-weatherbug"
    ) { c in
        // Optional: override CDN values with app-controlled ones.
        c.appBundleId = Bundle.main.bundleIdentifier
    }
    // Hand `config` to your SellwildAdView / SellwildAdBanner / SellwildWidget.
}
```

The CDN URL is `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`. Your Sellwild contact provisions the `slug` in the CMS.

**Failure handling.** On any network error, timeout, or 404 the call falls back to a `SellwildConfig(partnerCode:)` with deterministic defaults, so ads still render even with the CDN offline. Remote config is **additive, never blocking**.

See [Configuration → Remote Config](./configuration#remote-config) for the full CDN field reference.

---

## Prebid Server Configuration

The SDK routes header bidding through Prebid Server. The auction is initiated in-process by Prebid Mobile and resolved server-side, which eliminates the cookie and IDFA limitations of running header bidding inside a WebView.

```swift
var config = SellwildConfig(partnerCode: "weatherbug")

config.prebidServer = PrebidServerConfig(
    accountId: "weatherbug-prod",
    endpoint: "https://prebid.sellwild.com/openrtb2/auction",
    bidders: ["appnexus", "rubicon", "ix", "openx"],
    timeout: 1500,
    syncEndpoint: nil // Derived from endpoint if omitted
)
```

### PrebidServerConfig Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `accountId` | `String` | Yes | -- | Your Prebid Server account identifier |
| `endpoint` | `String` | Yes | -- | Full URL to the OpenRTB2 auction endpoint |
| `bidders` | `[String]` | Yes | -- | Bidder adapter codes to route server-side |
| `timeout` | `Int` | No | `1500` | Auction timeout in milliseconds |
| `syncEndpoint` | `String?` | No | `nil` | Cookie sync endpoint URL; derived from `endpoint` if omitted |

### How It Works

When `prebidServer` is set on `SellwildConfig`, the first `SellwildAdView.load()` call bootstraps Prebid Mobile with the configured host, account ID, and timeout. Each subsequent `load()`:

1. Builds an OpenRTB 2.6 banner ad unit with Prebid Mobile, including any passthrough bidder parameters from `SellwildConfig.remote`.
2. Posts the request to `prebid.sellwild.com/openrtb2/auction`. Prebid Server fans out to all configured bidders in parallel, server-side.
3. Attaches the winning bid's keywords to a `GAMRequest` as targeting.
4. Calls `AdManagerBannerView.load(_:)`. Google Ad Manager picks between the Prebid line item and any direct-sold demand and renders the creative through the native GMA view.

Because the auction runs natively, the SDK can supply real device signals (IDFV, App Tracking Transparency status, SKAdNetwork attribution) to Prebid Server -- a level of demand fidelity that is not possible from a WebView.

---

## GDPR and Privacy

### TCF Consent String

If your app uses a Consent Management Platform (CMP) that implements the IAB TCF v2.x standard, the consent string is stored in `UserDefaults` under the key `IABTCF_TCString`. Prebid Mobile reads this value automatically and forwards it on the auction request, and the Google Mobile Ads SDK reads it for its own EU User Consent enforcement.

To manually pass GDPR signals into the Prebid Server request, configure your CMP to write the following `UserDefaults` keys:

| UserDefaults Key | Type | Description |
|------------------|------|-------------|
| `IABTCF_gdprApplies` | `Int` | `1` if GDPR applies, `0` otherwise |
| `IABTCF_TCString` | `String` | Base64-encoded TCF consent string |

```swift
// Example: reading consent state from UserDefaults
let gdprApplies = UserDefaults.standard.integer(forKey: "IABTCF_gdprApplies")
let tcString = UserDefaults.standard.string(forKey: "IABTCF_TCString")

if gdprApplies == 1 {
    print("[Sellwild] GDPR applies. TC string: \(tcString ?? "none")")
}
```

### GPP Support

The SDK supports the IAB Global Privacy Platform. Enable it in your configuration:

```swift
config.gppEnabled = true
```

### Best Practices

- Initialize your CMP before loading any ad views. The SDK reads consent state at ad request time.
- If `IABTCF_gdprApplies` is `1` and no valid `IABTCF_TCString` is present, Prebid Server will suppress bidding for GDPR-regulated bidders.
- Do not cache or modify the TCF string manually. Let your CMP manage its lifecycle.
- Test with the IAB TCF Consent String Decoder to verify your CMP writes valid strings.

---

## Ad Refresh

The SDK supports automatic ad refresh for both `SellwildAdView` (UIKit) and `SellwildAdBanner` (SwiftUI). Refresh is disabled by default.

```swift
// Maximum number of refreshes per ad view instance on mobile
config.adRefreshMaxMobile = 10

// Interval between refreshes in seconds (minimum recommended: 30)
config.adRefreshInterval = 30.0
```

### Configuration Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `adRefreshMaxMobile` | `Int` | `0` (disabled) | Maximum refresh cycles per ad view. Set to `0` to disable. |
| `adRefreshInterval` | `TimeInterval` | `30.0` | Seconds between refresh cycles. IAB guidelines recommend a minimum of 30 seconds. |
| `adRefreshMax` | `Int` | `0` | Maximum refresh cycles, applied when `adRefreshMaxMobile` is `0`. |
| `maxFailedAuctions` | `Int` | `3` | Number of consecutive failed auctions before the SDK stops retrying. |

### Behavior

- The refresh timer starts after a successful impression callback.
- Calling `pause()` on the ad view stops the timer. It does not resume automatically.
- Navigating away from the screen should trigger `pause()` to prevent background refreshes (see [Lifecycle Management](#lifecycle-management)).
- Each call to `load()` resets the internal refresh counter.

---

## Lifecycle Management

Proper cleanup prevents unnecessary network requests and CPU usage when ad views are not visible.

### UIKit

```swift
override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // Pause all ad refresh timers when the view is not visible
    mrecAdView.pause()
    bannerAdView.pause()
}

override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Reload ads when the view becomes visible again
    mrecAdView.load()
    bannerAdView.load()
}
```

### Deallocation

`SellwildAdView` automatically cleans up in its `deinit`:

- Invalidates the refresh timer.
- Detaches its delegate from the underlying `AdManagerBannerView` to break the retain cycle.

### Memory Considerations

- Each `SellwildAdView` maintains its own `AdManagerBannerView` instance.
- Avoid creating ad views in tight loops or reusable cells without proper reuse logic.
- For table or collection views, create ad views outside of `cellForRowAt` and embed them in dedicated cells.

---

## Troubleshooting

### Common Issues

#### No ads are loading

| Symptom | Cause | Solution |
|---------|-------|----------|
| Blank ad view, no delegate callbacks | ATS blocking network requests | Add the domain exceptions listed in [Info.plist Configuration](#infoplist-configuration) |
| `sellwildAdViewDidLoad` fires but no creative appears | No fill from bidders | Verify your `partnerCode` and `accountId` are correct. Check that the `endpoint` URL is reachable. |
| Ads load in simulator but not on device | Network configuration difference | Ensure the device has internet access and is not on a restricted network that blocks ad domains. |

#### GDPR blocking ads

| Symptom | Cause | Solution |
|---------|-------|----------|
| Ads stop loading after CMP appears | `IABTCF_gdprApplies` is `1` with no valid consent string | Ensure your CMP writes `IABTCF_TCString` to `UserDefaults` before any ad views call `load()`. |
| Only some bidders return bids | Bidders without GDPR consent are suppressed | This is expected behavior. Bidders that require consent and do not receive it will not bid. |

#### Prebid Server errors

| Symptom | Cause | Solution |
|---------|-------|----------|
| `didFailWithError` with network error | Incorrect `endpoint` URL | Verify the URL is `https://prebid.sellwild.com/openrtb2/auction` |
| Timeout errors | `timeout` too low | Increase `PrebidServerConfig.timeout` (default: 1500 ms). For slow networks, consider 2500 ms. |
| No bids returned | Bidder misconfiguration | Confirm the bidder codes in `bidders` match your Prebid Server account configuration. |

#### Ad refresh not working

| Symptom | Cause | Solution |
|---------|-------|----------|
| Ads never refresh | `adRefreshMaxMobile` is `0` | Set `adRefreshMaxMobile` to a value greater than `0`. |
| Refresh stops early | Maximum refresh count reached | Increase `adRefreshMaxMobile` or accept the cap. |
| Refresh continues in background | `pause()` not called | Call `pause()` in `viewDidDisappear`. |

### Debug Mode

Enable verbose logging to diagnose integration issues:

```swift
config.debug = true
```

This enables verbose Prebid Mobile and Google Mobile Ads logging on the Xcode console. Filter by the following subsystems while running on a simulator or attached device:

- `Sellwild` -- SDK lifecycle and bridge events.
- `PrebidMobile` -- the OpenRTB request and bid response.
- `Google` -- GMA load, render, and impression events.

---

## API Reference

### SellwildConfig

Primary configuration object. All ad views and widgets read from this struct.

```swift
public struct SellwildConfig: Codable {
    public var partnerCode: String
    public var appBundleId: String?
    public var appStoreUrl: String?
    public var prebidServer: PrebidServerConfig?
    public var adRefreshMaxMobile: Int           // default: 0 (disabled)
    public var adRefreshInterval: TimeInterval   // default: 30.0
    public var debug: Bool                       // default: false
    // ... additional display and ad network properties
}
```

### AdSize

Predefined ad unit dimensions.

| Case | Dimensions | Usage |
|------|-----------|-------|
| `.banner320x50` | 320 x 50 | Standard mobile banner |
| `.mrec300x250` | 300 x 250 | Medium rectangle (MREC) |
| `.leaderboard728x90` | 728 x 90 | Tablet leaderboard |
| `.halfPage300x600` | 300 x 600 | Half-page unit |
| `.wideSkyscraper160x600` | 160 x 600 | Wide skyscraper |

### SellwildAdView (UIKit)

```swift
// Initialization
let adView = SellwildAdView(config: config, adSize: .mrec300x250, zoneId: nil)
adView.delegate = self

// Methods
adView.load()    // Load or reload the ad
adView.pause()   // Stop the refresh timer
```

### SellwildAdViewDelegate

```swift
@objc public protocol SellwildAdViewDelegate: AnyObject {
    @objc optional func sellwildAdViewDidLoad(_ adView: SellwildAdView)
    @objc optional func sellwildAdView(_ adView: SellwildAdView,
                                       didReceiveImpressionForZoneId zoneId: String)
    @objc optional func sellwildAdViewDidRecordClick(_ adView: SellwildAdView)
    @objc optional func sellwildAdView(_ adView: SellwildAdView,
                                       didFailWithError error: Error)
}
```

### SellwildAdBanner (SwiftUI)

```swift
SellwildAdBanner(
    config: config,
    adSize: .banner320x50,
    zoneId: nil,
    onImpression: { /* ... */ },
    onError: { error in /* ... */ }
)
.frame(width: 320, height: 50)
```

### SellwildWidget (SwiftUI)

```swift
SellwildWidget(
    config: config,
    onListingTap: { listing in /* ... */ },
    onLoad: { /* ... */ },
    onError: { error in /* ... */ }
)
.frame(height: 400)
```

### SellwildAPIClient

```swift
// Singleton
SellwildAPIClient.shared

// Callback-based
SellwildAPIClient.shared.fetchListings(config: config) { result in
    switch result {
    case .success(let response):
        // response.listings: [SellwildListing]
        print("Loaded \(response.listings.count) listings")
    case .failure(let error):
        print("Listings error: \(error.localizedDescription)")
    }
}

// Async/await (iOS 15+)
let response = try await SellwildAPIClient.shared.fetchListings(config: config)

// Cache management
SellwildAPIClient.shared.clearCache()
```
