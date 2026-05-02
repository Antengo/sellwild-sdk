import UIKit
import GoogleMobileAds
import PrebidMobile

// MARK: - SellwildAdView
//
// Native banner ad view. As of 1.3.0 this view runs a Prebid Mobile auction
// and renders into a GAMBannerView. There is **no WKWebView** in the ad path.
//
// The widget surface (SellwildWidget / SellwildWidgetView) still uses a
// WebView for marketplace listings — that surface is intentionally a WebView.
// Banners and other monetizing ad units render natively.
//
// USAGE
// ─────
// let config = await SellwildSDK.configure(partnerCode: "weatherbug",
//                                          slug: "weatherbug-weatherbug")
// let ad = SellwildAdView(config: config, adSize: .banner320x50, zoneId: "43")
// view.addSubview(ad)
// ad.load()

@objc
public final class SellwildAdView: UIView {

    // MARK: Public

    public var config: SellwildConfig
    public var adSize: AdSize
    /// The Sellwild-internal zone tag (e.g. `BANNER_ZID` from the CDN). Used
    /// as the Prebid Server `configId` for this placement. Server-side, the
    /// CMS maps this tag to a stored impression.
    public var zoneId: String?

    public weak var delegate: SellwildAdViewDelegate?

    // MARK: Private

    private lazy var bannerView: AdManagerBannerView = {
        let v = AdManagerBannerView(adSize: adSizeFor(cgSize: adSize.cgSize))
        v.translatesAutoresizingMaskIntoConstraints = false
        v.delegate = self
        v.adUnitID = resolveGAMAdUnitID()
        v.rootViewController = nearestViewController()
        return v
    }()

    private var refreshTimer: Timer?
    private var refreshCount = 0

    // MARK: Init

    public init(config: SellwildConfig, adSize: AdSize, zoneId: String? = nil) {
        self.config = config
        self.adSize = adSize
        self.zoneId = zoneId
        super.init(frame: CGRect(origin: .zero, size: adSize.cgSize))
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(config:adSize:zoneId:)")
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: Public

    /// Run the Prebid auction and load the winning ad. Safe to call multiple
    /// times; each call triggers a fresh auction + GAM request.
    public func load() {
        // Idempotent — first call wins, the rest are cheap.
        SellwildPrebidMobile.bootstrap(with: config)

        // Re-resolve the GAM ad unit each load() in case `config` was swapped.
        bannerView.adUnitID = resolveGAMAdUnitID()
        bannerView.rootViewController = nearestViewController()

        guard let configId = zoneId, !configId.isEmpty else {
            // No zoneId means we cannot run a Prebid auction. Fall through to
            // a plain GAM request so the GAM line items still serve.
            bannerView.load(AdManagerRequest())
            return
        }

        SellwildPrebidMobile.runBannerAuction(
            on: bannerView,
            configId: configId,
            adSize: adSize.cgSize,
            bidderParams: bidderParamsFromRemote()
        ) { [weak self] result in
            guard let self else { return }
            #if DEBUG
            print("[SellwildAdView] Prebid auction result: \(result)")
            #endif
        }
    }

    /// Stop the refresh timer. The currently displayed ad (if any) stays.
    public func pause() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: Private

    private func setup() {
        addSubview(bannerView)
        NSLayoutConstraint.activate([
            bannerView.topAnchor.constraint(equalTo: topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bannerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func scheduleRefresh() {
        guard config.adRefreshMaxMobile > 0 else { return }
        guard refreshCount < config.adRefreshMaxMobile else { return }
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: config.adRefreshInterval,
            repeats: false
        ) { [weak self] _ in
            self?.refreshCount += 1
            self?.load()
        }
    }

    /// Resolve the GAM ad unit ID. Order of preference:
    /// 1. `config.gamTag` (the real GAM ad unit path provisioned by the CMS).
    /// 2. `config.remoteValues["GAM"]` raw passthrough, if set.
    /// 3. GMA test ad unit (`/6499/example/banner`) — surfaces a clear log so
    ///    partners notice their CMS is missing a `GAM` field in production.
    private func resolveGAMAdUnitID() -> String {
        if let tag = config.gamTag, !tag.isEmpty {
            return tag
        }
        if let remoteGAM = config.remoteValues?["GAM"] as? String,
           !remoteGAM.isEmpty {
            return remoteGAM
        }
        #if DEBUG
        print("[SellwildAdView] No GAM ad unit configured. Falling back to "
            + "Google's test ad unit `/6499/example/banner`. Set `GAM` in your "
            + "CMS config to enable production fill.")
        #endif
        return "/6499/example/banner"
    }

    /// Forward bidder configs from the raw CDN payload as ext data on the
    /// Prebid auction. The CMS adds new bidders → partners use them
    /// immediately, no SDK release.
    private func bidderParamsFromRemote() -> [String: Any] {
        guard let raw = config.remoteValues else { return [:] }
        // Skip first-class fields that are not bidder params. The widget's
        // skip list is exhaustive; here we keep it lean and forward everything
        // that *looks* like a bidder block (CONSTANT_CASE name, dict value).
        var params: [String: Any] = [:]
        for (key, value) in raw {
            guard key == key.uppercased() else { continue }
            guard !nonBidderRemoteKeys.contains(key) else { continue }
            params[key] = value
        }
        return params
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}

// MARK: - BannerViewDelegate

extension SellwildAdView: GoogleMobileAds.BannerViewDelegate {

    public func bannerViewDidReceiveAd(_ bannerView: GoogleMobileAds.BannerView) {
        delegate?.sellwildAdViewDidLoad?(self)
        delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: zoneId ?? "")
        scheduleRefresh()
    }

    public func bannerView(_ bannerView: GoogleMobileAds.BannerView,
                           didFailToReceiveAdWithError error: Error) {
        delegate?.sellwildAdView?(self, didFailWithError: error)
        scheduleRefresh()
    }

    public func bannerViewDidRecordClick(_ bannerView: GoogleMobileAds.BannerView) {
        delegate?.sellwildAdViewDidRecordClick?(self)
    }
}

// MARK: - Delegate Protocol

@objc
public protocol SellwildAdViewDelegate: AnyObject {
    @objc optional func sellwildAdViewDidLoad(_ adView: SellwildAdView)
    @objc optional func sellwildAdView(_ adView: SellwildAdView,
                                       didReceiveImpressionForZoneId zoneId: String)
    @objc optional func sellwildAdViewDidRecordClick(_ adView: SellwildAdView)
    @objc optional func sellwildAdView(_ adView: SellwildAdView,
                                       didFailWithError error: Error)
}

// MARK: - Static config

/// CDN keys that are first-class typed config (handled elsewhere) and should
/// not be forwarded as Prebid bidder ext data.
private let nonBidderRemoteKeys: Set<String> = [
    "CODE", "LISTINGS", "SLUG", "NAME", "TITLE", "COLORS", "LINK_TEXT",
    "BUY_NOW_TEXT", "FONT_FAMILY", "FONT_URL", "FONT_COLOR", "PRICE_COLOR",
    "PRICE_FONT_COLOR", "MARGIN_BOTTOM", "CARD_WIDTH", "OVERLAY_TITLE", "CSS",
    "WATERMARK", "WATERMARK_TITLE", "BANNER_ZID", "BOTTOM_BANNER_ZID",
    "MOBILE_BANNER_ZID", "MOBILE_ZID", "DISPLAY_ZID", "HIDE_BANNER_TOP",
    "HIDE_BANNER_BOTTOM", "GAM", "DISABLE_GPT", "AD_UNITS", "SAFE_FRAME",
    "AD_DISABLE_DISPLAY", "AD_REFRESH_MAX", "AD_REFRESH_MAX_MOBILE",
    "AD_REFRESH_INTERVAL", "MAX_FAILED_AUCTIONS", "PREBID_DEFER", "PREBID_SRC",
    "AD_GEO_BLOCK", "AD_GEO_BLOCK_REFRESH", "GPP_ENABLED", "TCF_VERSION",
    "CONSENT_MANAGEMENT", "SCHAIN_SID", "S2S_CONFIG", "IAB_CATS",
    "APP_BUNDLE_ID", "APP_STORE_URL", "ENABLE_INTERSTITIAL",
    "ENABLE_FULLSCREEN_VIDEO", "INTERSTITIALS_PER_SESSION",
    "VIDEO_TAKEOVERS_PER_SESSION", "DEBUG", "MEMBERSHIP_TYPE",
]
