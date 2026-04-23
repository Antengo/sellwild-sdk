// SellwildPrebidMobile.swift — Optional Prebid Mobile SDK integration
//
// This file is compiled only when the host app includes the PrebidMobile pod/SPM package.
// It provides a lightweight bridge between SellwildConfig and the Prebid Mobile SDK,
// enabling true native header bidding without a WebView.
//
// REQUIREMENTS
// ─────────────
// Podfile:   pod 'PrebidMobile', '~> 2.3'
//            pod 'PrebidMobileGAMEventHandlers', '~> 2.3'  // if using GAM
// SPM:       https://github.com/prebid/prebid-mobile-swift (version 2.3.x)
//
// USAGE
// ─────
// 1. In your AppDelegate / App init:
//    SellwildPrebidMobile.initialize(
//      serverHost: .appnexus,          // or .rubicon, or .custom(host:)
//      accountId:  "YOUR_ACCOUNT_ID"
//    )
//
// 2. Create a native banner ad unit:
//    let banner = SellwildPrebidMobile.makeBannerAdUnit(
//      configId: "YOUR_CONFIG_ID",
//      adSize:   CGSize(width: 320, height: 50)
//    )
//    banner?.fetchDemand(adObject: gamBannerView) { _ in
//      gamBannerView.load(DFPRequest())
//    }
//
// NOTE: When using the Prebid Mobile SDK, you typically replace or supplement the
// SellwildWidget WebView with a GAM/MoPub ad view managed by PrebidMobile.
// The two approaches (WebView widget + native Prebid Mobile) can coexist — use
// SellwildWidget for the listing carousel and native Prebid Mobile for standalone
// banner / interstitial placements.

#if canImport(PrebidMobile)
import Foundation
import PrebidMobile

/// Convenience wrapper for bootstrapping Prebid Mobile SDK from SellwildConfig.
public enum SellwildPrebidMobile {

    /// Initialize the Prebid Mobile SDK.
    /// Call once from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// - Parameters:
    ///   - serverHost: The Prebid Server host. Use `.appnexus`, `.rubicon`,
    ///                 or `.custom(host: "prebid-server.example.com")`.
    ///   - accountId:  Your Prebid Server account ID.
    ///   - timeoutMillis: Auction timeout. Default: 1000 ms.
    ///   - debug:      Enable Prebid SDK console logging.
    public static func initialize(
        serverHost: PrebidHost,
        accountId: String,
        timeoutMillis: Int = 1000,
        debug: Bool = false
    ) {
        Prebid.shared.prebidServerHost = serverHost
        Prebid.shared.prebidServerAccountId = accountId
        Prebid.shared.timeoutMillisDynamic = timeoutMillis as NSNumber
        Prebid.shared.debugLogFileEnabled = debug
        Prebid.initializeSDK { status, error in
            if let error {
                print("[SellwildPrebidMobile] Init error: \(error)")
            }
        }
    }

    /// Initialize using a custom Prebid Server host URL.
    ///
    /// - Parameters:
    ///   - serverUrl: Full host URL, e.g. "https://prebid-server.example.com".
    ///   - accountId: Your Prebid Server account ID.
    public static func initialize(
        serverUrl: String,
        accountId: String,
        timeoutMillis: Int = 1000,
        debug: Bool = false
    ) {
        try? Prebid.shared.setCustomPrebidServer(url: serverUrl)
        initialize(
            serverHost: .custom,
            accountId: accountId,
            timeoutMillis: timeoutMillis,
            debug: debug
        )
    }

    /// Create a Prebid Mobile banner ad unit.
    ///
    /// - Parameters:
    ///   - configId: The Prebid config ID for this placement (from your Prebid Server).
    ///   - adSize:   The ad size (e.g. CGSize(width: 320, height: 50)).
    /// - Returns: A configured `BannerAdUnit` ready for `fetchDemand(adObject:)`.
    public static func makeBannerAdUnit(
        configId: String,
        adSize: CGSize
    ) -> BannerAdUnit? {
        let unit = BannerAdUnit(
            configId: configId,
            size: adSize
        )
        unit.setAutoRefreshMillis(time: 30_000)
        return unit
    }

    /// Create a Prebid Mobile interstitial ad unit.
    ///
    /// - Parameters:
    ///   - configId: The Prebid config ID for this placement.
    ///   - formats:  Allowed formats. Default: [.banner, .video].
    public static func makeInterstitialAdUnit(
        configId: String,
        formats: Set<AdFormat> = [.banner, .video]
    ) -> InterstitialAdUnit {
        let unit = InterstitialAdUnit(configId: configId)
        unit.adFormats = formats
        return unit
    }
}
#endif
