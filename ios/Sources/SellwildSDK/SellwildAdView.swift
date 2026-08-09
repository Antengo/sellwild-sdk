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

    /// A listing the feed supplies as house-ad backfill when no CMS house image
    /// (`HOUSE_AD_IMAGE`) is configured. Rendered only in the MREC slot — a
    /// 320x50 banner is too small for a card. See `SellwildHouseAd`.
    public var houseFallbackListing: SellwildListing?

    /// The ad stack this view resolves to, given the current config + override.
    public var resolvedAdStack: SellwildAdStack {
        SellwildAdStack.resolve(
            remoteValues: config.remoteValues,
            zoneId: zoneId,
            override: adStackOverride
        )
    }

    /// The banner size set for this placement — the `adSize` primary plus any
    /// remote `BANNER_SIZES` / `BANNER_SIZES_BY_ZONE` fallbacks (primary first).
    private var resolvedAdSizes: [CGSize] {
        SellwildAdSizes.resolve(
            remoteValues: config.remoteValues,
            zoneId: zoneId,
            primary: adSize.cgSize
        )
    }

    // MARK: Private

    // House-ad backdrop. Sits behind the paid creative and shows through only
    // when the slot is empty (no-fill, or the transient .prebidOnly refresh gap).
    private var houseView: SellwildHouseAdView?

    // GAM render path (.both / .gamOnly). Created lazily on first GAM load.
    private var gamBanner: AdManagerBannerView?
    // Prebid render path (.prebidOnly). Created lazily on first Prebid load.
    private var prebidBanner: PrebidBannerView?
    // Prebid native render path (.prebidOnly + NATIVE_ENABLED). Lazily created.
    private var nativeAdView: SellwildNativeAdView?

    private var refreshTimer: Timer?
    private var refreshCount = 0
    // .prebidOnly renders (initial + auto-refreshes). Caps Prebid's internal
    // auto-refresh at effectiveRefreshMax, which it otherwise ignores.
    private var prebidRefreshCount = 0

    /// Effective mobile refresh cap: the mobile-specific `AD_REFRESH_MAX_MOBILE`
    /// when set, else the shared `AD_REFRESH_MAX` (matches Android + web). iOS
    /// previously honored only the mobile key, silently disabling refresh — and
    /// its refresh revenue — for partners who set only `AD_REFRESH_MAX`.
    private var effectiveRefreshMax: Int {
        config.adRefreshMaxMobile > 0 ? config.adRefreshMaxMobile : config.adRefreshMax
    }

    // Cold-start guard: Prebid init is async and can race the first load(). Wait
    // up to ~1.2s (8 × 0.15s) for readiness before running the first auction so
    // the first impression isn't silently downgraded to GAM-only. Mirrors the
    // Android `prebidWait` loop.
    private var prebidWaitTimer: Timer?
    private var prebidWaitAttempts = 0
    private let maxPrebidWaitAttempts = 8
    private let prebidWaitIntervalSec: TimeInterval = 0.15

    // MARK: Init

    public init(config: SellwildConfig, adSize: AdSize, zoneId: String? = nil) {
        self.config = config
        self.adSize = adSize
        self.zoneId = zoneId
        // Honor the CMS analytics kill switch (EVENTS_ENABLED) before any emit.
        SellwildAPIClient.shared.eventsEnabled = SellwildEvents.isEnabled(remoteValues: config.remoteValues)
        super.init(frame: CGRect(origin: .zero, size: adSize.cgSize))
        // Reserve the widest/tallest size the auction may return (primary + any
        // BANNER_SIZES fallbacks) so a wider/taller fallback creative doesn't
        // clip. Hosts using Auto Layout override this initial frame; frame-based
        // hosts get a box that fits every requested size. The didRenderWithSize
        // delegate still reports the actual rendered size for hosts that tighten.
        self.frame = CGRect(origin: .zero, size: SellwildAdSizes.boundingSize(resolvedAdSizes))
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(config:adSize:zoneId:)")
    }

    deinit {
        refreshTimer?.invalidate()
        prebidWaitTimer?.invalidate()
        prebidBanner?.stopRefresh()
    }

    // MARK: Public

    /// Run the appropriate ad path for the resolved stack and load an ad. Safe
    /// to call multiple times; each call triggers a fresh load.
    public func load() {
        // Idempotent — first call wins, the rest are cheap.
        SellwildPrebidMobile.bootstrap(with: config)

        // Put the house-ad backdrop behind the slot before the paid creative
        // loads, so an empty slot (no-fill, or the .prebidOnly refresh teardown
        // gap) shows house inventory instead of a white flash. The paid creative
        // renders on top and covers it, so the slot auto-reverts when fill returns.
        installHouseBackdrop()

        // Resolve GrowthCode identity (once per launch, throttled). No-op unless
        // enabled with a partner id; injects/merges eids into the auction async.
        SellwildGrowthCode.resolveIfNeeded(config: config, zoneId: zoneId)

        // Native reuses the slot on .prebidOnly only: Prebid fetches demand and
        // we render the assets. On .both/.gamOnly a native creative would need
        // GAM native line items + a GADNativeAd renderer (ad-ops), so we fall
        // through to the banner path there.
        if resolvedAdStack == .prebidOnly,
           SellwildNative.isEnabled(remoteValues: config.remoteValues, zoneId: zoneId) {
            loadPrebidNative()
            return
        }

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
        // Paused mid cold-start wait → the pending first auction is cancelled;
        // flag it so resume() re-issues load() instead of only restarting refresh.
        if prebidWaitAttempts > 0 { needsReloadOnResume = true }
        prebidWaitAttempts = 0
        refreshTimer?.invalidate()
        refreshTimer = nil
        prebidWaitTimer?.invalidate()
        prebidWaitTimer = nil
        prebidBanner?.stopRefresh()
    }

    /// Resume refresh after `pause()`. GAM restarts our refresh timer (the
    /// current creative stays); prebidOnly best-effort re-enables Prebid's
    /// internal auto-refresh. (Also closes the iOS↔Android lifecycle-API gap.)
    public func resume() {
        if needsReloadOnResume {
            needsReloadOnResume = false
            load() // the first auction never completed (paused mid cold-start)
            return
        }
        switch resolvedAdStack {
        case .both, .gamOnly:
            scheduleRefresh()
        case .prebidOnly:
            // Setting refreshInterval alone doesn't re-arm: pause()'s stopRefresh()
            // latched the banner (the fork clears that only on a new bid request),
            // so re-issue the load to actually resume the auto-refresh cadence.
            if effectiveRefreshMax > 0 { prebidBanner?.loadAd() }
        }
    }

    // MARK: Detached-refresh pause (prototype, default OFF)
    // MOBILE_PAUSE_REFRESH_DETACHED truthy → pause refresh while this view is
    // fully detached from the window (pooled cell) and resume on re-attach. Trims
    // never-rendered detached-view refreshes (the invalid-traffic edge) while
    // keeping off-screen-but-attached refreshes. Off = today's behavior.

    private var isPausedForDetach = false
    // Set when pause() interrupts an in-flight first auction (cold-start wait);
    // resume() then re-issues load() so the first impression isn't lost.
    private var needsReloadOnResume = false

    private var pausesRefreshWhenDetached: Bool {
        switch config.remoteValues?["MOBILE_PAUSE_REFRESH_DETACHED"] {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "yes", "on"].contains(s.lowercased())
        default: return false
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard pausesRefreshWhenDetached else { return }
        if window == nil {
            if !isPausedForDetach { isPausedForDetach = true; pause() }
        } else if isPausedForDetach {
            isPausedForDetach = false
            resume()
        }
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

        // Cold-start guard: Prebid init is async and races the first load(). Wait
        // briefly for readiness, then run the auction regardless — runBannerAuction
        // falls back to GAM on a Prebid miss, so the wait can only *add* Prebid
        // demand to the first impression, never drop fill.
        if !SellwildPrebidMobile.isReady(), prebidWaitAttempts < maxPrebidWaitAttempts {
            prebidWaitAttempts += 1
            prebidWaitTimer?.invalidate()
            // .common mode so the cold-start retry still fires while scrolling.
            let waitTimer = Timer(timeInterval: prebidWaitIntervalSec, repeats: false) { [weak self] _ in
                self?.loadGAM(runAuction: runAuction)
            }
            RunLoop.main.add(waitTimer, forMode: .common)
            prebidWaitTimer = waitTimer
            return
        }
        prebidWaitAttempts = 0

        // Bidder params are configured server-side in the stored imp. Don't send
        // CMS config inline — it includes non-bidder keys that PBS rejects.
        SellwildPrebidMobile.runBannerAuction(
            on: banner,
            configId: configId,
            adSizes: resolvedAdSizes,
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
        if let na = nativeAdView { na.removeFromSuperview(); nativeAdView = nil }
        if let existing = gamBanner { return existing }

        let v = AdManagerBannerView(adSize: adSizeFor(cgSize: adSize.cgSize))
        // Multi-size: primary + any BANNER_SIZES fallbacks (validAdSizes).
        SellwildAdSizes.applyGAM(resolvedAdSizes, to: v)
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

        // Cold-start guard (mirrors the GAM path): Prebid init is async and races
        // the first load(). Unlike GAM we can't fall back to a GAM request, so a
        // premature loadAd() would no-fill and leave the slot blank. Wait briefly
        // for readiness, then load regardless once the wait budget is spent.
        if !SellwildPrebidMobile.isReady(), prebidWaitAttempts < maxPrebidWaitAttempts {
            prebidWaitAttempts += 1
            prebidWaitTimer?.invalidate()
            let waitTimer = Timer(timeInterval: prebidWaitIntervalSec, repeats: false) { [weak self] _ in
                self?.loadPrebidOnly()
            }
            RunLoop.main.add(waitTimer, forMode: .common)
            prebidWaitTimer = waitTimer
            return
        }
        prebidWaitAttempts = 0

        let banner = ensurePrebidBanner(configId: configId)
        // Prebid's rendering banner owns its own auto-refresh; mirror the GAM
        // cadence when configured — floored like the GAM timer so a mis-scaled
        // AD_REFRESH_INTERVAL can't drive a sub-second refresh storm. The refresh
        // COUNT is capped in the didReceiveAdWithAdSize delegate.
        if effectiveRefreshMax > 0 {
            banner.refreshInterval = max(config.adRefreshInterval, Self.minRefreshIntervalSec)
        }
        prebidRefreshCount = 0
        banner.loadAd()
    }

    private func ensurePrebidBanner(configId: String) -> PrebidBannerView {
        // Tear down a GAM banner if we previously rendered one.
        if let gb = gamBanner {
            gb.removeFromSuperview()
            gamBanner = nil
        }
        if let na = nativeAdView { na.removeFromSuperview(); nativeAdView = nil }
        if let existing = prebidBanner { return existing }

        // The (frame:configID:adSize:) convenience initializer uses Prebid's
        // standalone event handler — it makes a Prebid Server bid request and
        // renders the winning creative itself, with no ad-server (GAM) call.
        let v = PrebidBannerView(
            frame: CGRect(origin: .zero, size: adSize.cgSize),
            configID: configId,
            adSize: adSize.cgSize
        )
        // Prebid-rendered outstream (in-banner) video, no GAM: request banner +
        // video in one imp so the rendering BannerView renders whichever wins,
        // muted by default (VIDEO_SOUND_ENABLED opts a zone into sound).
        // SellwildVideo writes the fork's stored config directly (adFormats /
        // videoParameters / videoControlsConfig) — the path its own mediation
        // adapters use. Android's public rendering BannerView can't hold both
        // formats (banner-only there for now; see SellwildAdView.kt).
        if SellwildVideo.isEnabled(remoteValues: config.remoteValues, zoneId: zoneId) {
            SellwildVideo.enableOutstream(on: v, remoteValues: config.remoteValues, zoneId: zoneId)
        }
        // Multi-size fallback for the Prebid-rendered banner (primary set above).
        SellwildAdSizes.applyRendering(resolvedAdSizes, to: v)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.delegate = self
        prebidBanner = v
        addPinned(v)
        return v
    }

    // MARK: Prebid native path (.prebidOnly + NATIVE_ENABLED)

    private func loadPrebidNative() {
        guard let configId = zoneId, !configId.isEmpty else {
            #if DEBUG
            print("[SellwildAdView] native requires a zoneId. No ad loaded.")
            #endif
            delegate?.sellwildAdView?(self, didFailWithError: SellwildAdError.missingZoneIdForPrebidOnly)
            return
        }
        // Cold-start guard (mirrors loadPrebidOnly): native fetchDemand can race
        // Prebid init, and native is one-shot (no auto-refresh/retry) — a premature
        // no-fill strands the slot on house/blank for its lifetime. Wait briefly
        // for readiness, then load regardless once the wait budget is spent.
        if !SellwildPrebidMobile.isReady(), prebidWaitAttempts < maxPrebidWaitAttempts {
            prebidWaitAttempts += 1
            prebidWaitTimer?.invalidate()
            let waitTimer = Timer(timeInterval: prebidWaitIntervalSec, repeats: false) { [weak self] _ in
                self?.loadPrebidNative()
            }
            RunLoop.main.add(waitTimer, forMode: .common)
            prebidWaitTimer = waitTimer
            return
        }
        prebidWaitAttempts = 0
        ensureNativeAdView(configId: configId).load()
    }

    private func ensureNativeAdView(configId: String) -> SellwildNativeAdView {
        // Tear down banner render paths if we previously rendered one.
        if let gb = gamBanner { gb.removeFromSuperview(); gamBanner = nil }
        if let pb = prebidBanner { pb.stopRefresh(); pb.removeFromSuperview(); prebidBanner = nil }
        if let existing = nativeAdView { return existing }

        let cap = SellwildNative.maxHeight(
            remoteValues: config.remoteValues,
            zoneId: zoneId,
            fallback: adSize.cgSize.height
        )
        let v = SellwildNativeAdView(config: config, zoneId: configId, maxHeight: cap)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.onLoaded = { [weak self] in
            guard let self else { return }
            // Native filled — hide the house backdrop so it can't show through the
            // transparent native template (otherwise: two overlapping ads).
            self.houseView?.isHidden = true
            self.delegate?.sellwildAdViewDidLoad?(self)
            // Native fills to the (capped) height; report it so the host slot
            // resizes to the template rather than clipping.
            self.delegate?.sellwildAdView?(self, didRenderWithSize: CGSize(width: self.adSize.cgSize.width, height: cap))
            self.delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: self.zoneId ?? "")
            SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: self.zoneId ?? ""))
        }
        v.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.sellwildAdViewDidRecordClick?(self)
            SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "click", label: self.zoneId ?? ""))
        }
        v.onFailed = { [weak self] error in
            guard let self else { return }
            self.delegate?.sellwildAdView?(self, didFailWithError: error)
            SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "adError", action: error.localizedDescription, label: self.zoneId ?? ""))
        }
        nativeAdView = v
        // Pin top/leading/trailing, but bottom is `<=` so the native view can
        // render shorter than the slot (under its own height cap) without
        // fighting the cap constraint.
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor),
            v.leadingAnchor.constraint(equalTo: leadingAnchor),
            v.trailingAnchor.constraint(equalTo: trailingAnchor),
            v.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
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

    // MARK: House ad backdrop

    /// Create (once) and populate the house-ad backdrop for this slot. Content
    /// precedence: CMS house image → feed-supplied listing (MREC only) → nothing.
    /// Called on every `load()`; content is refreshed but the view is reused.
    private func installHouseBackdrop() {
        let creative = SellwildHouseAd.resolve(
            remoteValues: config.remoteValues, zoneId: zoneId, size: adSize.cgSize
        )
        let listing = houseFallbackListing
        let isMREC = adSize.cgSize.width >= 300 && adSize.cgSize.height >= 250
        guard SellwildHouseAd.isEnabled(remoteValues: config.remoteValues),
              creative != nil || (listing != nil && isMREC) else {
            houseView?.isHidden = true
            return
        }

        let view = houseView ?? {
            let v = SellwildHouseAdView(frame: bounds)
            v.translatesAutoresizingMaskIntoConstraints = false
            insertSubview(v, at: 0) // behind any paid creative
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: topAnchor),
                v.bottomAnchor.constraint(equalTo: bottomAnchor),
                v.leadingAnchor.constraint(equalTo: leadingAnchor),
                v.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            houseView = v
            return v
        }()
        view.isHidden = false

        if let creative {
            view.onTap = { [weak self] in self?.openHouseURL(creative.clickURL) }
            view.showImage(creative)
        } else if let listing {
            view.onTap = { [weak self] in
                guard let self else { return }
                self.openHouseURL(listing.tapURL(partnerCode: self.config.partnerCode, bhTag: self.config.bhTag))
            }
            view.showListing(listing, config: config)
        }
    }

    /// Fire the house-impression callback when the backdrop is actually visible.
    private func recordHouseImpressionIfShowing() {
        guard let houseView, !houseView.isHidden else { return }
        delegate?.sellwildAdView?(self, didRecordHouseImpressionForZoneId: zoneId ?? "")
    }

    private func openHouseURL(_ urlString: String?) {
        // http/https only — the click URL is remote CMS config; never hand an
        // arbitrary scheme (tel:/mailto:/deep link) to UIApplication.open.
        guard let url = SellwildSafeURL.external(urlString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Refresh (GAM path only — Prebid path self-refreshes)

    /// Floor for the GAM manual-refresh timer so a mis-scaled `AD_REFRESH_INTERVAL`
    /// (e.g. a seconds value misread as ms) can't fire a sub-second refresh storm.
    private static let minRefreshIntervalSec: TimeInterval = 10

    private func scheduleRefresh() {
        guard effectiveRefreshMax > 0 else { return }
        guard refreshCount < effectiveRefreshMax else { return }
        refreshTimer?.invalidate() // never stack refresh timers (resume()/re-load)
        let interval = max(config.adRefreshInterval, Self.minRefreshIntervalSec)
        // .common mode so a due refresh still fires while the table view is being
        // scrolled (default-mode timers are paused during scroll tracking).
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.refreshCount += 1
            self?.load()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
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

// MARK: - GAM BannerViewDelegate (.both / .gamOnly)

extension SellwildAdView: GoogleMobileAds.BannerViewDelegate {

    public func bannerViewDidReceiveAd(_ bannerView: GoogleMobileAds.BannerView) {
        delegate?.sellwildAdViewDidLoad?(self)
        // Report the actual rendered creative size so multi-size fallbacks (e.g.
        // a 320x50 win in a 300x250 request) resize the host slot.
        delegate?.sellwildAdView?(self, didRenderWithSize: bannerView.adSize.size)
        delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: zoneId ?? "")
        SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: zoneId ?? ""))
        scheduleRefresh()
    }

    public func bannerView(_ bannerView: GoogleMobileAds.BannerView,
                           didFailToReceiveAdWithError error: Error) {
        delegate?.sellwildAdView?(self, didFailWithError: error)
        SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "adError", action: error.localizedDescription, label: zoneId ?? ""))
        recordHouseImpressionIfShowing()
        scheduleRefresh()
    }

    public func bannerViewDidRecordClick(_ bannerView: GoogleMobileAds.BannerView) {
        delegate?.sellwildAdViewDidRecordClick?(self)
        SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "click", label: zoneId ?? ""))
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
        // Cap .prebidOnly auto-refresh at effectiveRefreshMax. Prebid's internal
        // auto-refresh is otherwise unbounded (unlike the counted GAM path). This
        // fires on the initial render plus each refresh, so stop once the refresh
        // budget is spent. Fails safe: if the fork ever stopped firing this on
        // refresh, behavior is just today's (uncapped) — never a regression.
        if effectiveRefreshMax > 0 {
            prebidRefreshCount += 1
            if prebidRefreshCount > effectiveRefreshMax { bannerView.stopRefresh() }
        }
        #if DEBUG
        print("[SellwildAdView][prebidOnly] ✅ rendered — size \(adSize), zone \(zoneId ?? "?")")
        #endif
        delegate?.sellwildAdViewDidLoad?(self)
        delegate?.sellwildAdView?(self, didRenderWithSize: adSize)
        delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: zoneId ?? "")
        SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: zoneId ?? ""))
    }

    public func bannerView(_ bannerView: PrebidBannerView,
                           didFailToReceiveAdWith error: Error) {
        // Loud on purpose: this is how we diagnose why .prebidOnly renders blank.
        #if DEBUG
        print("[SellwildAdView][prebidOnly] ❌ failed to render — zone \(zoneId ?? "?"): "
            + "\(error.localizedDescription)")
        #endif
        delegate?.sellwildAdView?(self, didFailWithError: error)
        SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "adError", action: error.localizedDescription, label: zoneId ?? ""))
        recordHouseImpressionIfShowing()
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
    /// The ad rendered at `size` (points). Fires on every render so a host can
    /// resize its slot to the actual creative — the winning multi-size banner,
    /// an outstream video, or the capped native template. Enables dynamic
    /// sizing where the slot isn't a fixed banner (React Native especially).
    @objc optional func sellwildAdView(_ adView: SellwildAdView,
                                       didRenderWithSize size: CGSize)
    /// A house ad backfilled an empty slot (no-fill). NOT a paid impression —
    /// report it separately. Fires only when the house backdrop is actually
    /// visible. See `SellwildHouseAd`.
    @objc optional func sellwildAdView(_ adView: SellwildAdView,
                                       didRecordHouseImpressionForZoneId zoneId: String)
}
