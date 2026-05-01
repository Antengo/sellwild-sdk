# Sellwild SDK for iOS

Integration guide for the Sellwild native ad SDK. The SDK runs server-side header bidding through Prebid Server, delivering display ads and marketplace listing cards natively on iOS.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Info.plist Configuration](#infoplist-configuration)
4. [UIKit Integration](#uikit-integration)
5. [SwiftUI Integration](#swiftui-integration)
6. [Native Listing Cards](#native-listing-cards)
7. [App Tracking Transparency](#app-tracking-transparency)
8. [Remote Config](#remote-config)
9. [Prebid Server Configuration](#prebid-server-configuration)
10. [GDPR and Privacy](#gdpr-and-privacy)
11. [Ad Refresh](#ad-refresh)
12. [Lifecycle Management](#lifecycle-management)
13. [Troubleshooting](#troubleshooting)
14. [API Reference](#api-reference)

---

## Prerequisites

| Requirement | Minimum Version |
|-------------|-----------------|
| Xcode | 14.0 or later |
| iOS deployment target | 13.0 |
| Swift | 5.5 or later |
| macOS (build host) | 11.0 (Big Sur) |

The SDK is written in pure Swift and depends only on `UIKit` and `WebKit`, both of which ship with iOS. No third-party runtime dependencies are required.

---

## Installation

### CocoaPods (recommended)

Add the following to your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourApp' do
  use_frameworks!
  pod 'SellwildSDK', '~> 1.2'
end
```

Then run:

```bash
pod install
```

Open the generated `.xcworkspace` file to continue development.

### Swift Package Manager

1. In Xcode, select **File > Add Package Dependencies**.
2. Enter the repository URL:

```
https://github.com/Antengo/sellwild-sdk.git
```

3. Set the dependency rule to **Up to Next Major Version** starting at `1.2.0`.
4. Select the **SellwildSDK** library product and add it to your app target.

Alternatively, add the dependency directly in your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/Antengo/sellwild-sdk.git",
        from: "1.2.0"
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

---

## Info.plist Configuration

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

```swift
import UIKit
import SellwildSDK

final class AdViewController: UIViewController {

    // MARK: - Configuration

    private lazy var config: SellwildConfig = {
        var c = SellwildConfig(
            partnerCode: "weatherbug",
            listingsUrl: "https://api.sellwild.com/widget/listings?partner=weatherbug"
        )

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
- The `SellwildAdView` manages its own internal `WKWebView`; do not add subviews or modify its frame directly.

---

## SwiftUI Integration

The SDK provides `SellwildAdBanner` and `SellwildWidget` as native SwiftUI views. Both require iOS 14 or later.

```swift
import SwiftUI
import SellwildSDK

struct AdContentView: View {

    private let config: SellwildConfig = {
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

    private let config = SellwildConfig(
        partnerCode: "weatherbug",
        listingsUrl: "https://api.sellwild.com/widget/listings?partner=weatherbug"
    )

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

`SellwildSDK.configure(partnerCode:slug:)` is the recommended way to integrate the SDK. It fetches a JSON document from the Sellwild CDN at app launch and returns a fully-built `SellwildConfig` — listings URL, ad zones, refresh intervals, app identity, waterfall partners, compliance flags, and more — so you can change everything without an app update.

```swift
import SellwildSDK

Task {
    let config = await SellwildSDK.configure(
        partnerCode: "weatherbug",
        slug: "weatherbug-main"
    ) { c in
        // Optional: override CDN values with app-controlled ones.
        c.appBundleId = Bundle.main.bundleIdentifier
    }
    // Hand `config` to your SellwildAdView / SellwildAdBanner / SellwildWidget.
}
```

The CDN URL is `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`. Your Sellwild contact provisions the `slug` in the CMS.

**Failure handling.** On any network error, timeout, or 404 the call falls back to a `SellwildConfig(partnerCode:)` with deterministic defaults. The `listingsUrl` derives from `partnerCode`, so ads still render even with the CDN offline. Remote config is **additive, never blocking**.

See [Configuration → Remote Config](./configuration#remote-config) for the full CDN field reference.

---

## Prebid Server Configuration

The SDK routes header bidding through Prebid Server, eliminating the cookie and IDFA limitations of client-side Prebid.js in a WebView environment. All auction logic runs server-side.

```swift
var config = SellwildConfig(
    partnerCode: "weatherbug",
    listingsUrl: "https://api.sellwild.com/widget/listings?partner=weatherbug"
)

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

When `prebidServer` is set on `SellwildConfig`, the SDK automatically injects `s2sConfig` into the Prebid.js configuration within the ad WebView:

```javascript
pbjs.setConfig({
    ortb2: {
        app: {
            bundle: "com.example.myapp",
            storeurl: "https://apps.apple.com/app/id1234567890",
            publisher: { id: "weatherbug" }
        }
    },
    userSync: {
        filterSettings: {
            iframe: { bidders: "*", filter: "exclude" }
        },
        syncDelay: 5000
    },
    s2sConfig: {
        accountId: "weatherbug-prod",
        bidders: ["appnexus", "rubicon", "ix", "openx"],
        timeout: 1500,
        adapter: "prebidServer",
        endpoint: {
            p1Consent: "https://prebid.sellwild.com/openrtb2/auction",
            noP1Consent: "https://prebid.sellwild.com/openrtb2/auction"
        }
    }
});
```

Iframe-based user syncs are automatically disabled because `WKWebView` does not support third-party cookies.

---

## GDPR and Privacy

### TCF Consent String

If your app uses a Consent Management Platform (CMP) that implements the IAB TCF v2.x standard, the consent string is stored in `UserDefaults` under the key `IABTCF_TCString`. Prebid.js reads this value automatically when running inside the WebView.

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
| `adRefreshMax` | `Int` | `0` | Maximum refresh cycles for desktop/tablet layouts (used by the widget WebView). |
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
- Removes the `WKUserContentController` script message handler to break the retain cycle.

`SellwildWidgetView` does not require manual lifecycle management. The widget handles its own cleanup when deallocated.

### Memory Considerations

- Each `SellwildAdView` and `SellwildWidgetView` maintains its own `WKWebView` instance.
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

This enables Prebid.js debug output in the WebView console. To capture WebView console logs during development, attach Safari Web Inspector to your app:

1. On your iOS device or simulator, enable **Settings > Safari > Advanced > Web Inspector**.
2. In Safari on your Mac, select **Develop > [Device] > [Your App]**.
3. Console output from the Prebid.js auction will appear in the Safari Web Inspector console.

---

## API Reference

### SellwildConfig

Primary configuration object. All ad views and widgets read from this struct.

```swift
public struct SellwildConfig: Codable {
    public var partnerCode: String
    public var listingsUrl: String
    public var apiBaseUrl: String               // default: "https://api.sellwild.com"
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
    case .success(let response): // response.listings: [SellwildListing]
    case .failure(let error):    // handle error
    }
}

// Async/await (iOS 15+)
let response = try await SellwildAPIClient.shared.fetchListings(config: config)

// Cache management
SellwildAPIClient.shared.clearCache()
```
