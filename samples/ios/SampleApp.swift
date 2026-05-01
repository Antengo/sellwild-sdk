/**
 * Sellwild iOS SDK — Runnable Sample App
 *
 * How to run:
 *   1. Create a new iOS app in Xcode (SwiftUI or UIKit, targeting iOS 14+).
 *   2. Add the SellwildSDK package:
 *        File → Add Package Dependencies →
 *        https://github.com/sellwild/sdk-ios.git  (version 1.0.0)
 *        — OR —
 *        Add to your Podfile: pod 'SellwildSDK', '~> 1.0'  then pod install
 *   3. Copy the relevant section below into your app.
 *   4. Replace 'YOUR_PARTNER_CODE' with your real partner code.
 *
 * This file shows three usage patterns:
 *   A. UIKit  — full widget in a UIViewController
 *   B. SwiftUI — full widget + banner ad
 *   C. Native listings — fetch listings via SellwildAPIClient, display in SwiftUI List
 */

import Foundation
import UIKit
import SwiftUI
import SellwildSDK

// ─── Shared Config ────────────────────────────────────────────────────────────

// ─── Shared Config ────────────────────────────────────────────────────────────
//
// TWO PREBID MODES are available:
//
//  Mode A (default) — Prebid.js client-side in the WebView.
//    Set appBundleId so Prebid.js declares in-app (ortb2.app) inventory.
//
//  Mode B — Prebid Server S2S.
//    Routes all bids server-side through a Prebid Server instance.
//    Solves cookie/IDFA limitations. Uncomment prebidServer below.
//    See sdk/PREBID.md for full setup instructions.
//
//  Mode C — Prebid Mobile SDK (native, no WebView for bidding).
//    Uses true native bidding via PrebidMobile pod/SPM package.
//    See SellwildPrebidMobile.swift and sdk/PREBID.md for setup.

extension SellwildConfig {
  /// Static config — the minimum required fields.
  /// Bidders, refresh limits, geo-blocking, and ad controls come from the remote
  /// app config on the CDN, managed via the Sellwild CMS.
  static var demo: SellwildConfig {
    var c = SellwildConfig(
      partnerCode: "YOUR_PARTNER_CODE",
      listingsUrl: "https://api.sellwild.com/widget/listings?partner=YOUR_PARTNER_CODE&count=20"
    )
    c.appBundleId = Bundle.main.bundleIdentifier ?? "com.mycompany.myapp"
    c.appStoreUrl = "https://apps.apple.com/app/idXXXXXXXXX"
    c.adRefreshMaxMobile = 5
    c.adRefreshInterval = 30.0
    c.debug = true
    return c
  }

  /// Load config with remote overrides from the CDN.
  /// The CMS publishes JSON at: https://widget.sellwild.com/app/{code}/{slug}.json
  /// Toggle bidders, adjust refresh limits, enable interstitials — no app update needed.
  ///
  /// Usage:
  ///   let config = await SellwildConfig.withRemoteOverrides(slug: "your-partner-slug")
  static func withRemoteOverrides(slug: String) async -> SellwildConfig {
    let base = Self.demo
    let url = URL(string: "https://widget.sellwild.com/app/\(base.partnerCode)/\(slug).json")!
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      let remote = try JSONDecoder().decode(SellwildConfig.self, from: data)
      // Merge: remote overrides win, but keep identity fields from static config
      var merged = remote
      merged.partnerCode = base.partnerCode
      merged.listingsUrl = base.listingsUrl
      merged.appBundleId = base.appBundleId
      merged.appStoreUrl = base.appStoreUrl
      merged.debug = base.debug
      return merged
    } catch {
      print("[Sellwild] Remote config fetch failed, using static config: \(error)")
      return base
    }
  }
}

// ─── Mode C: Prebid Mobile SDK initialization (optional) ─────────────────────
// Uncomment and add PrebidMobile pod/SPM package to use true native bidding.
// Call from AppDelegate.application(_:didFinishLaunchingWithOptions:).
//
// func initPrebidMobileSDK() {
//   SellwildPrebidMobile.initialize(
//     serverHost: .appnexus,            // or .rubicon / .custom
//     accountId:  "YOUR_ACCOUNT_ID",
//     debug: true
//   )
// }
//
// Then create ad units in your view controllers:
//   let banner = SellwildPrebidMobile.makeBannerAdUnit(
//     configId: "YOUR_CONFIG_ID",
//     adSize:   CGSize(width: 320, height: 50)
//   )
//   banner?.fetchDemand(adObject: gamBannerView) { _ in
//     gamBannerView.load(GAMRequest())
//   }

// ─── A. UIKit — Full Widget ───────────────────────────────────────────────────

final class WidgetViewController: UIViewController {

  private lazy var widgetView = SellwildWidgetView(config: .demo)

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Sellwild"
    view.backgroundColor = .systemBackground

    widgetView.delegate = self
    widgetView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(widgetView)

    NSLayoutConstraint.activate([
      widgetView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      widgetView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      widgetView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      widgetView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    widgetView.load()
  }
}

extension WidgetViewController: SellwildWidgetViewDelegate {
  func sellwildWidgetViewDidLoad(_ widgetView: SellwildWidgetView) {
    print("[Sellwild] Widget loaded")
  }

  func sellwildWidgetView(_ widgetView: SellwildWidgetView, didTapListing listing: SellwildListing) {
    // listing.url is set for WebView-sourced taps (from window.open interception)
    if let urlStr = listing.url, let url = URL(string: urlStr) {
      UIApplication.shared.open(url)
    }
  }

  func sellwildWidgetView(_ widgetView: SellwildWidgetView, didReceiveAdImpressionForZoneId zoneId: String) {
    print("[Sellwild] Ad impression, zoneId:", zoneId)
  }

  func sellwildWidgetView(_ widgetView: SellwildWidgetView, didFailWithError error: Error) {
    print("[Sellwild] Widget error:", error.localizedDescription)
  }
}

// ─── B. SwiftUI — Full Widget + Banner ───────────────────────────────────────

@available(iOS 14, *)
struct SellwildDemoView: View {

  let config: SellwildConfig = .demo

  var body: some View {
    TabView {
      // Tab 1: Full WebView widget
      SellwildWidget(
        config: config,
        onListingTap: { listing in
          if let urlStr = listing.url, let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
          }
        },
        onLoad: {
          print("[Sellwild] Widget ready")
        },
        onError: { error in
          print("[Sellwild] Widget error:", error.localizedDescription)
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .tabItem { Label("Widget", systemImage: "house") }

      // Tab 2: Standalone MREC banner
      VStack(spacing: 16) {
        Text("Banner Ad Demo")
          .font(.headline)

        SellwildAdBanner(
          config: config,
          adSize: .mrec300x250,
          zoneId: config.bannerZid,
          onImpression: {
            print("[Sellwild] MREC impression")
          },
          onError: { error in
            print("[Sellwild] Banner error:", error.localizedDescription)
          }
        )
        .frame(width: 300, height: 250)

        SellwildAdBanner(
          config: config,
          adSize: .banner320x50,
          zoneId: config.bannerZid,
          onImpression: {
            print("[Sellwild] 320x50 impression")
          }
        )
        .frame(width: 320, height: 50)

        Spacer()
      }
      .padding()
      .tabItem { Label("Banners", systemImage: "rectangle.3.group") }

      // Tab 3: Native listings
      NativeListingsView(config: config)
        .tabItem { Label("Listings", systemImage: "list.bullet") }
    }
  }
}

// ─── C. SwiftUI — Native Listings via SellwildAPIClient ──────────────────────

@available(iOS 15, *)
@MainActor
final class ListingsViewModel: ObservableObject {
  @Published var listings: [SellwildListing] = []
  @Published var isLoading = false
  @Published var errorMessage: String?

  func load(config: SellwildConfig) async {
    isLoading = true
    errorMessage = nil
    do {
      let response = try await SellwildAPIClient.shared.fetchListings(config: config)
      listings = response.listings
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }
}

@available(iOS 15, *)
struct NativeListingsView: View {
  let config: SellwildConfig
  @StateObject private var vm = ListingsViewModel()

  var body: some View {
    NavigationView {
      Group {
        if vm.isLoading {
          ProgressView("Loading listings…")
        } else if let err = vm.errorMessage {
          VStack(spacing: 12) {
            Text("Error").font(.headline).foregroundColor(.red)
            Text(err).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load(config: config) } }
              .buttonStyle(.borderedProminent)
          }
          .padding()
        } else {
          List(vm.listings) { listing in
            ListingRow(listing: listing, config: config)
          }
          .refreshable {
            SellwildAPIClient.shared.clearCache()
            await vm.load(config: config)
          }
        }
      }
      .navigationTitle("Sellwild Listings")
      .task { await vm.load(config: config) }
    }
  }
}

@available(iOS 15, *)
struct ListingRow: View {
  let listing: SellwildListing
  let config: SellwildConfig

  var body: some View {
    HStack(spacing: 12) {
      AsyncImage(url: URL(string: listing.primaryPhoto?.url ?? "")) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color.gray.opacity(0.2)
      }
      .frame(width: 72, height: 72)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 4) {
        Text(listing.title)
          .font(.subheadline)
          .lineLimit(2)
        if let price = listing.displayPrice {
          Text("$\(price)")
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
        }
        if let user = listing.user {
          Text("by \(user.username)")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
    .onTapGesture {
      if let urlStr = listing.url, let url = URL(string: urlStr) {
        UIApplication.shared.open(url)
      }
    }
  }
}

// ─── App Entry Point ──────────────────────────────────────────────────────────

@available(iOS 14, *)
@main
struct SellwildSampleApp: App {
  var body: some Scene {
    WindowGroup {
      SellwildDemoView()
    }
  }
}
