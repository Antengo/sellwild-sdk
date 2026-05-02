/**
 * Sellwild iOS SDK — Runnable Sample App
 *
 * How to run:
 *   1. Create a new iOS app in Xcode (SwiftUI or UIKit, targeting iOS 14+).
 *   2. Add the SellwildSDK package:
 *        File → Add Package Dependencies →
 *        https://github.com/Antengo/sellwild-sdk.git  (version 1.3.0)
 *        — OR —
 *        Add to your Podfile: pod 'SellwildSDK', '~> 1.3'  then pod install
 *
 *      As of 1.3.0 the SDK pulls in PrebidMobile + Google Mobile Ads.
 *      SPM requires Xcode 16+. CocoaPods works with Xcode 15+.
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
//
// Ad path (1.3.0+):
//   `SellwildAdView` / `SellwildAdBanner` runs a NATIVE Prebid Mobile auction
//   and renders the winner into a NATIVE GAM `AdManagerBannerView`. There is
//   no WebView in the banner ad path. The marketplace `SellwildWidget` still
//   uses a WebView; that surface is intentional.
//
// Prebid Mobile + GMA bootstrap automatically on the first ad view — partners
// don't need to call `MobileAds.shared.start()` themselves. Server URL +
// account id are resolved from typed config (`config.prebidServer`) or fall
// back to raw passthrough (`config.remote["S2S_CONFIG"]`).

extension SellwildConfig {
  /// Remote config (the first-class path, 1.2.0+).
  ///
  /// `SellwildSDK.configure(partnerCode:slug:)` fetches a JSON document from
  /// the Sellwild CDN at app launch and returns a fully-built `SellwildConfig`.
  /// Two strings — partner code and slug — and the SDK is ready. On any
  /// network/timeout/404 failure the call falls back to a `SellwildConfig`
  /// with deterministic defaults so ads still render.
  ///
  /// Usage:
  ///   let config = await SellwildConfig.demo()
  static func demo() async -> SellwildConfig {
    let config = await SellwildSDK.configure(
      partnerCode: "weatherbug",
      slug: "weatherbug-weatherbug"
    ) { c in
      // App-controlled overrides win over CDN values.
      c.appBundleId = Bundle.main.bundleIdentifier ?? "com.mycompany.myapp"
      c.debug = true
    }

    // Passthrough verification: log every CDN key that flowed through to the
    // widget. Confirms unmapped bidders (MEDIANET, AMX, SOVRN, etc.) survive.
    if let remote = config.remote {
      let keys = remote.keys.sorted()
      print("[Sellwild] configure() resolved. remote passthrough keys:", keys)
    } else {
      print("[Sellwild] configure() resolved. no remote payload (offline fallback?)")
    }
    return config
  }

  /// Static config (fallback when you can't make a network call before
  /// rendering ads). 1.2.0+ makes `listingsUrl` optional — if you leave it
  /// unset, the SDK derives a default from `partnerCode`.
  static var staticDemo: SellwildConfig {
    var c = SellwildConfig(partnerCode: "weatherbug")
    c.bannerZid = "43"
    c.mobileZids = ["280"]
    c.appBundleId = Bundle.main.bundleIdentifier ?? "com.mycompany.myapp"
    c.appStoreUrl = "https://apps.apple.com/us/app/weatherbug-weather-forecast/id281940292"
    c.adRefreshMaxMobile = 3
    c.adRefreshInterval = 30.0
    c.debug = true
    return c
  }
}

// ─── A. UIKit — Full Widget ───────────────────────────────────────────────────

final class WidgetViewController: UIViewController {

  private lazy var widgetView = SellwildWidgetView(config: .staticDemo)

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

  let config: SellwildConfig = .staticDemo

  var body: some View {
    TabView {
      // Tab 1 (primary): Native banner ads — Prebid Mobile auction + GAM render
      VStack(spacing: 16) {
        Text("Native Banner Ads")
          .font(.headline)
        Text("Prebid Mobile auction → GAM render. No WebView in the ad path.")
          .font(.caption)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)

        SellwildAdBanner(
          config: config,
          adSize: .mrec300x250,
          zoneId: config.bannerZid,
          onImpression: {
            print("[Sellwild] MREC impression (native render)")
          },
          onError: { error in
            print("[Sellwild] Banner error:", error.localizedDescription)
          }
        )
        .frame(width: 300, height: 250)

        SellwildAdBanner(
          config: config,
          adSize: .banner320x50,
          zoneId: config.mobileZids.first ?? config.bannerZid,
          onImpression: {
            print("[Sellwild] 320x50 impression (native render)")
          }
        )
        .frame(width: 320, height: 50)

        Spacer()
      }
      .padding()
      .tabItem { Label("Banners", systemImage: "rectangle.3.group") }

      // Tab 2: Marketplace widget (still WebView — that's the right surface
      // for marketplace listings, not for ad rendering).
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

      // Tab 3: Native listings via SellwildAPIClient
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
