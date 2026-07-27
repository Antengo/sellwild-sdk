import UIKit
import GoogleMobileAds
import SellwildPrebidSDK

// Disambiguate types that exist in both SellwildPrebidSDK and GoogleMobileAds
public typealias PrebidBannerView = SellwildPrebidSDK.BannerView
public typealias PrebidBannerViewDelegate = SellwildPrebidSDK.BannerViewDelegate

// MARK: - SellwildAdView
//
// Native banner ad view. As of 1.3.0 this view runs a Prebid Mobile auction
// and renders into a GAMBannerView. There is **no WKWebView** in the ad path.
//
// As of 1.4.0 the view can be segmented by ad stack (see `SellwildAdStack`),
// toggled remotely via `AD_STACK` / `AD_STACK_BY_ZONE`:
//   - .both       — Prebid auction → GAM renders (default; unchanged).
//   - .gamOnly    — plain GAM request, no Prebid auction.
//   - .prebidOnly — Prebid's own rendering BannerView, NO GAM request (and so
//                   no GAM request/serving fees).
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

    /// Optional code-level ad-stack override. When set, wins over the remote
    /// `AD_STACK` / `AD_STACK_BY_ZONE` config — intended for QA / testing.
    public var adStackOverride: SellwildAdStack?

    public weak var delegate: SellwildAdViewDelegate?

    /// The ad stack this view resolves to, given the current config + override.
    public var resolvedAdStack: SellwildAdStack {
        SellwildAdStack.resolve(
            remoteValues: config.remoteValues,
            zoneId: zoneId,
            override: adStackOverride
        )
    }

    // MARK: Private

    // GAM render path (.both / .gamOnly). Created lazily on first GAM load.
    private var gamBanner: AdManagerBannerView?
    // Prebid render path (.prebidOnly). Created lazily on first Prebid load.
    private var prebidBanner: PrebidBannerView?

    private var refreshTimer: Timer?
    private var refreshCount = 0

    // MARK: Init

    public init(config: SellwildConfig, adSize: AdSize, zoneId: String? = nil) {
        self.config = config
        self.adSize = adSize
        self.zoneId = zoneId
        super.init(frame: CGRect(origin: .zero, size: adSize.cgSize))
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(config:adSize:zoneId:)")
    }

    deinit {
        refreshTimer?.invalidate()
        prebidBanner?.stopRefresh()
    }

    // MARK: Public

    /// Run the appropriate ad path for the resolved stack and load an ad. Safe
    /// to call multiple times; each call triggers a fresh load.
    public func load() {
        // Idempotent — first call wins, the rest are cheap.
        SellwildPrebidMobile.bootstrap(with: config)

        switch resolvedAdStack {
        case .prebidOnly:
            loadPrebidOnly()
        case .gamOnly:
            loadGAM(runAuction: false)
        case .both:
            loadGAM(runAuction: true)
        }
    }

    /// Stop refresh. The currently displayed ad (if any) stays.
    public func pause() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        prebidBanner?.stopRefresh()
    }

    // MARK: GAM path (.both / .gamOnly)

    private func loadGAM(runAuction: Bool) {
        let banner = ensureGAMBanner()
        // Re-resolve the GAM ad unit each load() in case `config` was swapped.
        banner.adUnitID = resolveGAMAdUnitID()
        banner.rootViewController = nearestViewController()

        guard runAuction, let configId = zoneId, !configId.isEmpty else {
            // No auction (.gamOnly), or no zoneId to bid against. Either way,
            // a plain GAM request so GAM line items still serve.
            banner.load(AdManagerRequest())
            return
        }

        // Bidder params are configured server-side in the stored imp. Don't send
        // CMS config inline — it includes non-bidder keys that PBS rejects.
        SellwildPrebidMobile.runBannerAuction(
            on: banner,
            configId: configId,
            adSize: adSize.cgSize,
            bidderParams: [:],
            video: SellwildVideo.isEnabled(remoteValues: config.remoteValues, zoneId: zoneId)
        ) { [weak self] result in
            guard let self else { return }
            #if DEBUG
            print("[SellwildAdView] Prebid auction result: \(result)")
            #endif
        }
    }

    private func ensureGAMBanner() -> AdManagerBannerView {
        // Tear down a Prebid-only banner if we previously rendered one (e.g.
        // the resolved stack changed between loads).
        if let pb = prebidBanner {
            pb.stopRefresh()
            pb.removeFromSuperview()
            prebidBanner = nil
        }
        if let existing = gamBanner { return existing }

        let v = AdManagerBannerView(adSize: adSizeFor(cgSize: adSize.cgSize))
        v.translatesAutoresizingMaskIntoConstraints = false
        v.delegate = self
        v.adUnitID = resolveGAMAdUnitID()
        v.rootViewController = nearestViewController()
        gamBanner = v
        addPinned(v)
        return v
    }

    // MARK: Prebid-only path (.prebidOnly)

    private func loadPrebidOnly() {
        guard let configId = zoneId, !configId.isEmpty else {
            // Prebid rendering needs a configId (the stored-impression zone).
            // We deliberately do NOT fall back to a GAM request here — that
            // would incur the GAM request fees that .prebidOnly exists to avoid.
            #if DEBUG
            print("[SellwildAdView] .prebidOnly requires a zoneId. No ad loaded.")
            #endif
            delegate?.sellwildAdView?(self, didFailWithError: SellwildAdError.missingZoneIdForPrebidOnly)
            return
        }

        let banner = ensurePrebidBanner(configId: configId)
        // Prebid's rendering banner owns its own auto-refresh; mirror the GAM
        // refresh cadence when one is configured.
        if config.adRefreshMaxMobile > 0 {
            banner.refreshInterval = config.adRefreshInterval
        }
        banner.loadAd()
    }

    private func ensurePrebidBanner(configId: String) -> PrebidBannerView {
        // Tear down a GAM banner if we previously rendered one.
        if let gb = gamBanner {
            gb.removeFromSuperview()
            gamBanner = nil
        }
        if let existing = prebidBanner { return existing }

        // The (frame:configID:adSize:) convenience initializer uses Prebid's
        // standalone event handler — it makes a Prebid Server bid request and
        // renders the winning creative itself, with no ad-server (GAM) call.
        let v = PrebidBannerView(
            frame: CGRect(origin: .zero, size: adSize.cgSize),
            configID: configId,
            adSize: adSize.cgSize
        )
        // Prebid-rendered outstream video (no GAM). Verify `videoParameters`
        // exists on the rendering BannerView in the shaded fork.
        if SellwildVideo.isEnabled(remoteValues: config.remoteValues, zoneId: zoneId) {
            v.videoParameters = SellwildVideo.outstreamParameters()
        }
        v.translatesAutoresizingMaskIntoConstraints = false
        v.delegate = self
        prebidBanner = v
        addPinned(v)
        return v
    }

    // MARK: Layout

    private func addPinned(_ child: UIView) {
        addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor),
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: Refresh (GAM path only — Prebid path self-refreshes)

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

    // Google-provided test ad units. /6499/example/banner only fills 320x50;
    // mrec / leaderboard / etc. need their own test units or they no-fill.
    private static let gamTestAdUnitBanner   = "/6499/example/banner"
    private static let gamTestAdUnitAdaptive = "/21775744923/example/adaptive-banner"

    /// Resolve the GAM ad unit ID. Order of preference:
    /// 1. `config.gamTag` (the real GAM ad unit path provisioned by the CMS).
    /// 2. `config.remoteValues["GAM"]` raw passthrough, if set.
    /// 3. A size-appropriate Google test ad unit (320x50 → banner test unit,
    ///    everything else → adaptive-banner test unit which fills 300x250,
    ///    728x90, 300x600, 160x600). Mirrors Android's size-aware fallback so
    ///    demos render an ad even when the CMS hasn't provisioned `GAM`.
    private func resolveGAMAdUnitID() -> String {
        if let tag = config.gamTag, !tag.isEmpty {
            return tag
        }
        if let remoteGAM = config.remoteValues?["GAM"] as? String,
           !remoteGAM.isEmpty {
            return remoteGAM
        }
        let size = adSize.cgSize
        let testUnit = (size.width == 320 && size.height == 50)
            ? Self.gamTestAdUnitBanner
            : Self.gamTestAdUnitAdaptive
        #if DEBUG
        print("[SellwildAdView] No GAM ad unit configured. Falling back to "
            + "Google's test ad unit `\(testUnit)`. Set `GAM` in your CMS "
            + "config to enable production fill.")
        #endif
        return testUnit
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

// MARK: - Errors

public enum SellwildAdError: Error, LocalizedError {
    /// `.prebidOnly` was resolved for a placement with no `zoneId`, so no
    /// Prebid configId is available and no ad can be requested.
    case missingZoneIdForPrebidOnly

    public var errorDescription: String? {
        switch self {
        case .missingZoneIdForPrebidOnly:
            return "SellwildAdView resolved to .prebidOnly but has no zoneId; "
                + "Prebid rendering requires a configId."
        }
    }
}

// MARK: - GAM BannerViewDelegate (.both / .gamOnly)

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

// MARK: - Prebid BannerViewDelegate (.prebidOnly)

extension SellwildAdView: PrebidBannerViewDelegate {

    public func bannerViewPresentationController() -> UIViewController? {
        let vc = nearestViewController()
        #if DEBUG
        if vc == nil {
            print("[SellwildAdView][prebidOnly] ⚠️ no presentation view controller — "
                + "the view isn't in a VC hierarchy yet; Prebid rendering may fail. "
                + "Ensure the ad view is added to a live view controller before load().")
        }
        #endif
        return vc
    }

    public func bannerView(_ bannerView: PrebidBannerView,
                           didReceiveAdWithAdSize adSize: CGSize) {
        #if DEBUG
        print("[SellwildAdView][prebidOnly] ✅ rendered — size \(adSize), zone \(zoneId ?? "?")")
        #endif
        delegate?.sellwildAdViewDidLoad?(self)
        delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: zoneId ?? "")
    }

    public func bannerView(_ bannerView: PrebidBannerView,
                           didFailToReceiveAdWith error: Error) {
        // Loud on purpose: this is how we diagnose why .prebidOnly renders blank.
        #if DEBUG
        print("[SellwildAdView][prebidOnly] ❌ failed to render — zone \(zoneId ?? "?"): "
            + "\(error.localizedDescription)")
        #endif
        delegate?.sellwildAdView?(self, didFailWithError: error)
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
