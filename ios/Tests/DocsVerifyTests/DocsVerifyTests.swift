// DocsVerifyTests.swift
// Compiles every Swift code block from docs-site/guide/ios.md and
// docs-site/guide/quick-start.md verbatim (wrapped in the minimum context
// the docs imply: ViewController body, SwiftUI View body, function body,
// etc.). The point is to catch doc snippets that don't compile against
// the real SDK — not to exercise behaviour.

import XCTest
import UIKit
import SwiftUI
import SellwildSDK

final class DocsVerifyTests: XCTestCase {
    func testCompilesOK() { XCTAssertTrue(true) }
}

// ─────────────────────────────────────────────────────────────────────────
// quick-start.md, block 3 (L36)
// ─────────────────────────────────────────────────────────────────────────
@available(iOS 15.0, *)
enum DocsQuickStart_b03_L36 {
    static func run() async {
        // VERBATIM BEGIN ──────────────────────────────────────────────────
        // (Original block has `import SellwildSDK` at top; hoisted to file.)

        // Partner code + slug. Everything else — listings URL, ad zones, app
        // identity, refresh intervals, waterfall partners, compliance flags — is
        // fetched from the Sellwild CDN at app launch. On any network/timeout/404
        // failure the SDK falls back to deterministic defaults so ads still render.
        let config = await SellwildSDK.configure(
            partnerCode: "weatherbug",
            slug: "weatherbug-weatherbug"
        ) { c in
            // Override CDN with app-controlled values.
            c.appBundleId = Bundle.main.bundleIdentifier ?? "com.example.myapp"
        }
        // VERBATIM END ────────────────────────────────────────────────────
        _ = config
    }
}

// ─────────────────────────────────────────────────────────────────────────
// quick-start.md, block 4 (L59) — static-config alternative
// ─────────────────────────────────────────────────────────────────────────
enum DocsQuickStart_b04_L59 {
    static func run() {
        // VERBATIM BEGIN ──────────────────────────────────────────────────
        var config = SellwildConfig(partnerCode: "weatherbug")
        config.appBundleId = Bundle.main.bundleIdentifier
        config.listingsUrl = "https://your-cms-or-cache.example.com/listings.json"
        // Set prebidServer, mobileZids, etc. from the same CDN doc.
        // VERBATIM END ────────────────────────────────────────────────────
        _ = config
    }
}

// ─────────────────────────────────────────────────────────────────────────
// quick-start.md, block 5 (L69) — SwiftUI banner
// (Uses a free `config` symbol. We provide one at file scope so the snippet
// can compile as a full SwiftUI View definition.)
// ─────────────────────────────────────────────────────────────────────────
fileprivate var _DocsQuickStart_b05_L69_config = SellwildConfig(
    partnerCode: "weatherbug",
    listingsUrl: "https://example.com/listings.json"
)

@available(iOS 14.0, *)
struct DocsQuickStart_b05_L69_ContentView: View {
    var body: some View {
        // VERBATIM BEGIN ──────────────────────────────────────────────────
        SellwildAdBanner(
            config: _DocsQuickStart_b05_L69_config,
            adSize: .mrec300x250,
            onImpression: {
                print("Ad impression recorded")
            },
            onError: { error in
                print("Ad error: \(error.localizedDescription)")
            }
        )
        .frame(width: 300, height: 250)
        // VERBATIM END ────────────────────────────────────────────────────
    }
}

// ─────────────────────────────────────────────────────────────────────────
// quick-start.md, block 6 (L92) — UIKit ad view in a UIViewController
// ─────────────────────────────────────────────────────────────────────────
final class DocsQuickStart_b06_L92_VC: UIViewController, SellwildAdViewDelegate {
    var config = SellwildConfig(
        partnerCode: "weatherbug",
        listingsUrl: "https://example.com/listings.json"
    )
    override func viewDidLoad() {
        super.viewDidLoad()
        // VERBATIM BEGIN ──────────────────────────────────────────────────
        let adView = SellwildAdView(config: config, adSize: .mrec300x250)
        adView.delegate = self
        view.addSubview(adView)
        // Add constraints: 300pt wide, 250pt tall
        adView.load()
        // VERBATIM END ────────────────────────────────────────────────────
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 2 (L65) — Package.swift fragment (DOC SNIPPET, NOT SWIFT)
// Skipped: this is a snippet of *Package.swift* manifest syntax, not code
// that gets compiled into an app.
// ─────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 9 (L208) — full UIKit ViewController; standalone file.
// ─────────────────────────────────────────────────────────────────────────
final class DocsIos_b09_L208_AdViewController: UIViewController {
    private let config = SellwildConfig(
        partnerCode: "weatherbug",
        listingsUrl: "https://your-cms-or-cache.example.com/listings.json"
    )
    private lazy var mrecAdView = SellwildAdView(config: config, adSize: .mrec300x250)
    private lazy var bannerAdView = SellwildAdView(config: config, adSize: .banner320x50)

    override func viewDidLoad() {
        super.viewDidLoad()
        mrecAdView.delegate = self
        bannerAdView.delegate = self
        mrecAdView.translatesAutoresizingMaskIntoConstraints = false
        bannerAdView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mrecAdView)
        view.addSubview(bannerAdView)

        NSLayoutConstraint.activate([
            mrecAdView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16
            ),
            mrecAdView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mrecAdView.widthAnchor.constraint(equalToConstant: 300),
            mrecAdView.heightAnchor.constraint(equalToConstant: 250),

            bannerAdView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8
            ),
            bannerAdView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerAdView.widthAnchor.constraint(equalToConstant: 320),
            bannerAdView.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
}

extension DocsIos_b09_L208_AdViewController: SellwildAdViewDelegate {
    func sellwildAdViewDidLoad(_ adView: SellwildAdView) {
        let label = adView === mrecAdView ? "MREC" : "Banner"
        print("[Sellwild] \(label) ad loaded")
    }
    func sellwildAdView(_ adView: SellwildAdView,
                        didReceiveImpressionForZoneId zoneId: String) {
        print("[Sellwild] Impression recorded for zone: \(zoneId)")
    }
    func sellwildAdViewDidRecordClick(_ adView: SellwildAdView) {
        print("[Sellwild] Ad clicked")
    }
    func sellwildAdView(_ adView: SellwildAdView, didFailWithError error: Error) {
        print("[Sellwild] Ad error: \(error.localizedDescription)")
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 10 (L346) — full SwiftUI view; standalone.
// ─────────────────────────────────────────────────────────────────────────
@available(iOS 14.0, *)
struct DocsIos_b10_L346_AdContentView: View {
    private let config: SellwildConfig = {
        var c = SellwildConfig(
            partnerCode: "weatherbug",
            listingsUrl: "https://your-cms-or-cache.example.com/listings.json"
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
            SellwildAdBanner(
                config: config,
                adSize: .mrec300x250,
                onImpression: { print("[Sellwild] MREC impression") },
                onError: { error in print("[Sellwild] MREC error: \(error.localizedDescription)") }
            )
            .frame(width: 300, height: 250)
            Spacer()
            SellwildWidget(
                config: config,
                onListingTap: { listing in
                    if let url = listing.url, let link = URL(string: url) {
                        UIApplication.shared.open(link)
                    }
                },
                onLoad: { print("[Sellwild] Widget loaded") },
                onError: { error in print("[Sellwild] Widget error: \(error.localizedDescription)") }
            )
            .frame(height: 400)
            SellwildAdBanner(
                config: config,
                adSize: .banner320x50,
                onImpression: { print("[Sellwild] Banner impression") },
                onError: { error in print("[Sellwild] Banner error: \(error.localizedDescription)") }
            )
            .frame(width: 320, height: 50)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 11 (L429) — full UIKit listings VC with table.
// ─────────────────────────────────────────────────────────────────────────
@available(iOS 14.0, *)
@available(iOS 14.0, *)
final class DocsIos_b11_L429_ListingsViewController: UIViewController {
    private let config = SellwildConfig(
        partnerCode: "weatherbug",
        listingsUrl: "https://your-cms-or-cache.example.com/listings.json"
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

@available(iOS 14.0, *)
@available(iOS 14.0, *)
extension DocsIos_b11_L429_ListingsViewController: UITableViewDataSource, UITableViewDelegate {
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

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 12 (L504) — async/await method body.
// Wrapped in a stub class with `listings` + `tableView` props.
// ─────────────────────────────────────────────────────────────────────────
@available(iOS 15.0, *)
final class DocsIos_b12_L504_VC: UIViewController {
    var config = SellwildConfig(partnerCode: "weatherbug", listingsUrl: "https://example.com/listings.json")
    var listings: [SellwildListing] = []
    let tableView = UITableView()

    // VERBATIM BEGIN ──────────────────────────────────────────────────
    func fetchListings() async {
        do {
            let response = try await SellwildAPIClient.shared.fetchListings(config: config)
            self.listings = response.listings
            tableView.reloadData()
        } catch {
            print("[Sellwild] Fetch error: \(error.localizedDescription)")
        }
    }
    // VERBATIM END ────────────────────────────────────────────────────
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 13 (L537) — ATT free function. Standalone.
// ─────────────────────────────────────────────────────────────────────────
import AppTrackingTransparency
import AdSupport

func DocsIos_b13_L537_requestTrackingAuthorization() {
    guard #available(iOS 14.5, *) else { return }

    ATTrackingManager.requestTrackingAuthorization { status in
        DispatchQueue.main.async {
            switch status {
            case .authorized:
                let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                print("[Sellwild] IDFA: \(idfa)")
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

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 14 (L579) — top-level Task{} using configure().
// ─────────────────────────────────────────────────────────────────────────
@available(iOS 15.0, *)
enum DocsIos_b14_L579 {
    static func run() {
        Task {
            let config = await SellwildSDK.configure(
                partnerCode: "weatherbug",
                slug: "weatherbug-weatherbug"
            ) { c in
                c.appBundleId = Bundle.main.bundleIdentifier
            }
            _ = config
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 15 (L606) — config builder with PrebidServerConfig.
// ─────────────────────────────────────────────────────────────────────────
enum DocsIos_b15_L606 {
    static func run() {
        var config = SellwildConfig(
            partnerCode: "weatherbug",
            listingsUrl: "https://your-cms-or-cache.example.com/listings.json"
        )

        config.prebidServer = PrebidServerConfig(
            accountId: "weatherbug-prod",
            endpoint: "https://prebid.sellwild.com/openrtb2/auction",
            bidders: ["appnexus", "rubicon", "ix", "openx"],
            timeout: 1500,
            syncEndpoint: nil
        )
        _ = config
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 16 (L657) — reading TCF consent.
// ─────────────────────────────────────────────────────────────────────────
enum DocsIos_b16_L657 {
    static func run() {
        let gdprApplies = UserDefaults.standard.integer(forKey: "IABTCF_gdprApplies")
        let tcString = UserDefaults.standard.string(forKey: "IABTCF_TCString")
        if gdprApplies == 1 {
            print("[Sellwild] GDPR applies. TC string: \(tcString ?? "none")")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 17 (L671) — single statement on `config`.
// ─────────────────────────────────────────────────────────────────────────
enum DocsIos_b17_L671 {
    static func run(config: inout SellwildConfig) {
        config.gppEnabled = true
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 18 (L688) — ad refresh settings.
// ─────────────────────────────────────────────────────────────────────────
enum DocsIos_b18_L688 {
    static func run(config: inout SellwildConfig) {
        config.adRefreshMaxMobile = 10
        config.adRefreshInterval = 30.0
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 19 (L720) — UIViewController lifecycle overrides.
// ─────────────────────────────────────────────────────────────────────────
final class DocsIos_b19_L720_VC: UIViewController {
    var config = SellwildConfig(partnerCode: "weatherbug", listingsUrl: "https://example.com/listings.json")
    lazy var mrecAdView = SellwildAdView(config: config, adSize: .mrec300x250)
    lazy var bannerAdView = SellwildAdView(config: config, adSize: .banner320x50)

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        mrecAdView.pause()
        bannerAdView.pause()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        mrecAdView.load()
        bannerAdView.load()
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 20 (L790) — `config.debug = true`.
// ─────────────────────────────────────────────────────────────────────────
enum DocsIos_b20_L790 {
    static func run(config: inout SellwildConfig) {
        config.debug = true
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 21 (L808) — REFERENCE doc of SellwildConfig (would shadow
// the SDK's type). Skipped from compile-check: it's a documentation
// rendering of the SDK type, not user code.
// ─────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 22 (L837) — SellwildAdView usage statements.
// ─────────────────────────────────────────────────────────────────────────
final class DocsIos_b22_L837_VC: UIViewController, SellwildAdViewDelegate {
    var config = SellwildConfig(partnerCode: "weatherbug", listingsUrl: "https://example.com/listings.json")

    func setup() {
        let adView = SellwildAdView(config: config, adSize: .mrec300x250, zoneId: nil)
        adView.delegate = self
        adView.load()
        adView.pause()
        _ = adView
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 23 (L849) — REFERENCE doc of SellwildAdViewDelegate. Skipped.
// ─────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 24 (L862) — SellwildAdBanner SwiftUI expression.
// ─────────────────────────────────────────────────────────────────────────
@available(iOS 14.0, *)
struct DocsIos_b24_L862_View: View {
    let config: SellwildConfig
    var body: some View {
        SellwildAdBanner(
            config: config,
            adSize: .banner320x50,
            zoneId: nil,
            onImpression: { /* ... */ },
            onError: { error in
                _ = error
                /* ... */
            }
        )
        .frame(width: 320, height: 50)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 25 (L875) — SellwildWidget SwiftUI expression.
// ─────────────────────────────────────────────────────────────────────────
@available(iOS 14.0, *)
struct DocsIos_b25_L875_View: View {
    let config: SellwildConfig
    var body: some View {
        SellwildWidget(
            config: config,
            onListingTap: { listing in
                _ = listing
                /* ... */
            },
            onLoad: { /* ... */ },
            onError: { error in
                _ = error
                /* ... */
            }
        )
        .frame(height: 400)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ios.md, block 26 (L887) — SellwildAPIClient usage. Original snippet has
// empty switch cases which won't compile; wrap with placeholder statements
// (this is a known doc smell — flag in report).
// ─────────────────────────────────────────────────────────────────────────
@available(iOS 15.0, *)
enum DocsIos_b26_L887 {
    static func run(config: SellwildConfig) async {
        _ = SellwildAPIClient.shared

        SellwildAPIClient.shared.fetchListings(config: config) { result in
            switch result {
            case .success(let response):
                // response.listings: [SellwildListing]
                print("Loaded \(response.listings.count) listings")
            case .failure(let error):
                print("Listings error: \(error.localizedDescription)")
            }
        }

        let response = try? await SellwildAPIClient.shared.fetchListings(config: config)
        _ = response

        SellwildAPIClient.shared.clearCache()
    }
}
