import UIKit
import SafariServices
import GoogleMobileAds
import SellwildPrebidSDK

// MARK: - Environment

/// GMA and Prebid, as `SellwildAdView` uses them. The live one goes through
/// `SellwildPrebidMobile`, whose `calls` hold every third-party call that
/// starts an SDK or reaches the network; tests pass a fake.
protocol SellwildAdNetwork: AnyObject {
    /// Starts GMA and Prebid once.
    func bootstrap(_ config: SellwildConfig)
    func isPrebidReady() -> Bool
    /// Sends a plain GAM request.
    func loadGAM(_ banner: AdManagerBannerView)
    /// Runs the Prebid auction, then the GAM request (Prebid's own parameters).
    func runBannerAuction( // swiftlint:disable:this function_parameter_count
        on banner: AdManagerBannerView, configId: String, adSizes: [CGSize], gpid: String?,
        video: Bool, completion: @escaping (ResultCode) -> Void
    )
    /// Sends the Prebid rendering request.
    func loadPrebid(_ banner: PrebidBannerView)
    /// The winning bid of the last Prebid rendering request.
    func winningBid(of banner: PrebidBannerView) -> SellwildAdPolicy.BidSummary?
}

/// The real GMA and Prebid.
final class SellwildLiveAdNetwork: SellwildAdNetwork {
    func bootstrap(_ config: SellwildConfig) {
        SellwildPrebidMobile.bootstrap(with: config)
    }

    func isPrebidReady() -> Bool {
        SellwildPrebidMobile.isReady()
    }

    func loadGAM(_ banner: AdManagerBannerView) {
        SellwildPrebidMobile.calls.loadGAM(banner, AdManagerRequest())
    }

    // swiftlint:disable:next function_parameter_count
    func runBannerAuction(on banner: AdManagerBannerView, configId: String, adSizes: [CGSize], gpid: String?,
                          video: Bool, completion: @escaping (ResultCode) -> Void) {
        SellwildPrebidMobile.runBannerAuction(on: banner, configId: configId, adSizes: adSizes, gpid: gpid,
                                              video: video, completion: completion)
    }

    func loadPrebid(_ banner: PrebidBannerView) {
        SellwildPrebidMobile.calls.loadPrebid(banner)
    }

    func winningBid(of banner: PrebidBannerView) -> SellwildAdPolicy.BidSummary? {
        banner.lastBidResponse?.winningBid.map(Self.summary(of:))
    }

    // sellwild-coverage:exclude-begin(third-party-object) only Prebid's auction creates a winning bid.
    static func summary(of bid: Bid) -> SellwildAdPolicy.BidSummary {
        SellwildAdPolicy.BidSummary(isVideoFormat: bid.adFormat == .video,
                                    hasVideoConfig: bid.videoAdConfiguration != nil, adm: bid.adm)
    }
    // sellwild-coverage:exclude-end

    // sellwild-coverage:exclude-begin(network-call) GAM, Prebid Server, Safari; tests replace the environment.
    /// Sends a GAM ad request: the GMA network, which needs the app's GMA
    /// application id. Never runs in tests.
    static let sendGAMRequest: (AdManagerBannerView, AdManagerRequest) -> Void = { banner, request in
        banner.load(request)
    }

    /// Sends a Prebid rendering request: the Prebid Server network. Never runs
    /// in tests.
    static let sendPrebidRequest: (PrebidBannerView) -> Void = { banner in
        banner.loadAd()
    }

    /// Opens a URL outside the app (Safari). Never runs in tests.
    static let openOutside: (URL) -> Void = { url in
        UIApplication.shared.open(url)
    }
    // sellwild-coverage:exclude-end
}

extension SellwildAdView {
    /// What `SellwildAdView` calls outside itself. Partners always get
    /// `live`; tests set `SellwildAdView.environment` before they make views.
    struct Environment {
        /// The events queue.
        var events: SellwildAPIClient
        var network: SellwildAdNetwork
        /// The refresh and cold-start timers.
        var scheduler: SellwildScheduler
        /// GrowthCode identity for the auction (once a launch, throttled).
        var resolveGrowthCode: (SellwildConfig, String?) -> Void
        /// Opens a house-ad click URL outside the app.
        var openURL: (URL) -> Void

        static let live = Environment(
            events: .shared,
            network: SellwildLiveAdNetwork(),
            scheduler: SellwildRunLoopScheduler(),
            resolveGrowthCode: SellwildGrowthCode.resolveIfNeeded,
            openURL: SellwildLiveAdNetwork.openOutside
        )
    }

    /// The environment each new view takes.
    static var environment = Environment.live
}

// MARK: - Errors

public enum SellwildAdError: Error, LocalizedError {
    /// `.prebidOnly` was resolved for a placement with no `zoneId`, so no
    /// Prebid configId is available and no ad can be requested.
    case missingZoneIdForPrebidOnly

    /// A native demand request returned no fill for the placement.
    case nativeNoFill

    public var errorDescription: String? {
        switch self {
        case .missingZoneIdForPrebidOnly:
            return "SellwildAdView resolved to .prebidOnly but has no zoneId; "
                + "Prebid rendering requires a configId."
        case .nativeNoFill:
            return "Native demand request returned no fill."
        }
    }
}
