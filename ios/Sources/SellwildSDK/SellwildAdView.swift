import UIKit
import AVFoundation
import GoogleMobileAds
import SellwildPrebidSDK

// Disambiguate types that exist in both SellwildPrebidSDK and GoogleMobileAds
public typealias PrebidBannerView = SellwildPrebidSDK.BannerView
public typealias PrebidBannerViewDelegate = SellwildPrebidSDK.BannerViewDelegate

/// Per-surface once-guard for the web-parity `firstAdViewed` event.
///
/// The web widget fires `firstAdViewed` once per page load (an in-memory closure
/// flag) so analytics can dedupe the per-render `adRenderSucceeded` down to a
/// single impression; a full navigation reloads the bundle and re-fires it.
/// Native mirrors that per ad *surface*: a standalone `SellwildAdView` owns its
/// own guard (surface = the view) and `SellwildFeedView` shares one across all
/// its ad rows (surface = the feed), so exactly one `firstAdViewed` fires per
/// surface mount — regardless of ad refreshes or slot count — and a fresh mount
/// (navigation) fires again. In-memory only; never persisted.
public final class SellwildFirstAdViewedGuard {
    private var fired = false
    public init() {}

    /// Runs `block` the first time only; subsequent calls are no-ops.
    public func fireOnce(_ block: () -> Void) {
        if fired { return }
        fired = true
        block()
    }
}

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
// Marketplace listings render natively too, via `SellwildFeedView` — the SDK
// ships no WebView-based surfaces.
//
// The decisions (refresh, cold start, resume, detach, GAM unit, house
// backdrop, placement, no-fill) live in `SellwildAdPolicy`. What the view
// calls outside itself goes through `SellwildAdView.environment`.
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

    /// Optional GPID override. When set it wins over the config-resolved base —
    /// `SellwildFeedView` injects `base#n` here so two ad slots that share a base
    /// on one screen stay unique. Standalone views leave this nil and auto-resolve
    /// the bare base from config. Internal on purpose: gpid is resolved from CMS
    /// config, not a public RN-facing property.
    var gpidOverride: String?

    public weak var delegate: SellwildAdViewDelegate?

    /// Per-surface guard for the web-parity `firstAdViewed` event. Standalone
    /// views keep their own; `SellwildFeedView` injects a shared one across its
    /// ad rows. See `SellwildFirstAdViewedGuard`.
    public var firstAdViewedGuard = SellwildFirstAdViewedGuard()

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

    /// The zone as an event label: "" when there is none.
    private var zoneLabel: String {
        zoneId ?? ""
    }

    /// The effective GPID for this placement: an explicit `gpidOverride` (the
    /// feed injects `base#n` for repeated bases) else the config-resolved base.
    /// nil ⇒ no gpid/pbadslot is sent.
    private var resolvedGpid: String? {
        if let gpidOverride { return gpidOverride }
        return SellwildGpid.resolveBase(remoteValues: config.remoteValues, zoneId: zoneId)
    }

    // MARK: Private

    private let environment: Environment

    // House-ad backdrop. Sits behind the paid creative and shows through only
    // when the slot is empty (no-fill, or the transient .prebidOnly refresh gap).
    private var houseView: SellwildHouseAdView?

    // GAM render path (.both / .gamOnly). Created lazily on first GAM load.
    private var gamBanner: AdManagerBannerView?
    // Prebid render path (.prebidOnly). Created lazily on first Prebid load.
    private var prebidBanner: PrebidBannerView?
    // Prebid native render path (.prebidOnly + NATIVE_ENABLED). Lazily created.
    private var nativeAdView: SellwildNativeAdView?

    private var refreshTimer: SellwildScheduled?
    private var refreshCount = 0
    // .prebidOnly renders (initial + auto-refreshes). Caps Prebid's internal
    // auto-refresh at effectiveRefreshMax, which it otherwise ignores.
    private var prebidRefreshCount = 0
    // True once the .prebidOnly BannerView has rendered a creative at least once.
    // Gates reattach behavior: with a rendered creative present, a reattach keeps
    // it (so its viewability tracker can fire the impression/burl) rather than
    // discarding it with a fresh auction.
    private var prebidHasRenderedCreative = false
    // True while a .prebidOnly click has an ad modal (in-app browser / store
    // sheet) open, so a leave-app from inside it isn't counted as a 2nd click.
    private var prebidClickModalOpen = false

    /// Effective mobile refresh cap: the mobile-specific `AD_REFRESH_MAX_MOBILE`
    /// when set, else the shared `AD_REFRESH_MAX` (matches Android + web). iOS
    /// previously honored only the mobile key, silently disabling refresh — and
    /// its refresh revenue — for partners who set only `AD_REFRESH_MAX`.
    private var effectiveRefreshMax: Int {
        SellwildAdPolicy.refreshMax(mobile: config.adRefreshMaxMobile, shared: config.adRefreshMax)
    }

    /// Whether another .prebidOnly auction fits the refresh cap. The budget is
    /// the first render + up to effectiveRefreshMax refreshes; prebidRefreshCount
    /// counts renders, so it's spent once the count exceeds the max (the same
    /// point the render delegate calls stopRefresh()).
    private var hasPrebidRefreshBudget: Bool {
        SellwildAdPolicy.hasPrebidRefreshBudget(renderCount: prebidRefreshCount, max: effectiveRefreshMax)
    }

    // Cold-start guard: Prebid init is async and can race the first load(). Wait
    // up to ~1.2s (8 × 0.15s) for readiness before running the first auction so
    // the first impression isn't silently downgraded to GAM-only. Mirrors the
    // Android `prebidWait` loop.
    private var prebidWaitTimer: SellwildScheduled?
    private var prebidWaitAttempts = 0

    // MARK: Init

    public init(config: SellwildConfig, adSize: AdSize, zoneId: String? = nil) {
        self.config = config
        self.adSize = adSize
        self.zoneId = zoneId
        let environment = Self.environment
        self.environment = environment
        // Honor the CMS analytics kill switch (EVENTS_ENABLED) before any emit.
        environment.events.eventsEnabled = SellwildEvents.isEnabled(remoteValues: config.remoteValues)
        // Partner attribution: stamp attributes.code so events attribute
        // correctly instead of landing as "Invalid". Failure reports carry it
        // too, also for an app that builds its config by hand and never calls
        // SellwildSDK.configure.
        environment.events.partnerCode = config.partnerCode
        SellwildFailures.setContext { $0.partnerCode = config.partnerCode }
        super.init(frame: CGRect(origin: .zero, size: adSize.cgSize))
        // Reserve the widest/tallest size the auction may return (primary + any
        // BANNER_SIZES fallbacks) so a wider/taller fallback creative doesn't
        // clip. Hosts using Auto Layout override this initial frame; frame-based
        // hosts get a box that fits every requested size. The didRenderWithSize
        // delegate still reports the actual rendered size for hosts that tighten.
        self.frame = CGRect(origin: .zero, size: SellwildAdSizes.boundingSize(resolvedAdSizes))
    }

    // sellwild-coverage:exclude-begin(crash-guard) init(coder:) traps by design (storyboards are not supported); the report it sends first is tested through reportUnsupportedInit().
    required init?(coder: NSCoder) {
        Self.reportUnsupportedInit()
        fatalError("Use init(config:adSize:zoneId:)")
    }
    // sellwild-coverage:exclude-end

    /// A storyboard made this view (`ad.view_init.unsupported`); init(coder:)
    /// traps right after.
    static func reportUnsupportedInit() {
        SellwildFailures.log(code: .adViewInitUnsupported, component: .banner, severity: .fatal,
                             message: "SellwildAdView was created from a storyboard (init(coder:)), which is not supported")
    }

    deinit {
        refreshTimer?.cancel()
        prebidWaitTimer?.cancel()
        prebidBanner?.stopRefresh()
    }

    // MARK: Public

    /// Run the appropriate ad path for the resolved stack and load an ad. Safe
    /// to call multiple times; each call triggers a fresh load.
    public func load() {
        // Idempotent — first call wins, the rest are cheap.
        environment.network.bootstrap(config)

        // Put the house-ad backdrop behind the slot before the paid creative
        // loads, so an empty slot (no-fill, or the .prebidOnly refresh teardown
        // gap) shows house inventory instead of a white flash. The paid creative
        // renders on top and covers it, so the slot auto-reverts when fill returns.
        installHouseBackdrop()

        // Resolve GrowthCode identity (once per launch, throttled). No-op unless
        // enabled with a partner id; injects/merges eids into the auction async.
        environment.resolveGrowthCode(config, zoneId)

        // Native reuses the slot on .prebidOnly only: Prebid fetches demand and
        // we render the assets. On .both/.gamOnly a native creative would need
        // GAM native line items + a GADNativeAd renderer (ad-ops), so we fall
        // through to the banner path there.
        let stack = resolvedAdStack
        if stack == .prebidOnly,
           SellwildNative.isEnabled(remoteValues: config.remoteValues, zoneId: zoneId) {
            loadPrebidNative()
            return
        }

        switch stack {
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
        refreshTimer?.cancel()
        refreshTimer = nil
        prebidWaitTimer?.cancel()
        prebidWaitTimer = nil
        prebidBanner?.stopRefresh()
    }

    /// Resume refresh after `pause()`. GAM restarts our refresh timer (the
    /// current creative stays); prebidOnly best-effort re-enables Prebid's
    /// internal auto-refresh. (Also closes the iOS↔Android lifecycle-API gap.)
    ///
    /// On .prebidOnly, setting refreshInterval alone doesn't re-arm: pause()'s
    /// stopRefresh() latched the banner (the fork clears that only on a new bid
    /// request). By default a fresh loadAd() un-latches it, but that discards the
    /// current creative before its viewability tracker fires, so burl (the
    /// viewable impression) almost never fires on a scrolling feed. With
    /// `MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH` on, the rendered creative stays
    /// and the cadence resumes on a DELAYED refresh instead. Either way only while
    /// the refresh cap has budget: once it is spent, a reattach starts no new
    /// auction and the last creative stays.
    public func resume() {
        let action = SellwildAdPolicy.resumeAction(
            needsReload: needsReloadOnResume,
            stack: resolvedAdStack,
            hasRefreshBudget: hasPrebidRefreshBudget,
            hasRenderedCreative: prebidHasRenderedCreative,
            keepCreative: keepsPrebidCreativeOnReattach
        )
        switch action {
        case .reload:
            needsReloadOnResume = false
            load() // the first auction never completed (paused mid cold-start)
        case .scheduleRefresh:
            scheduleRefresh()
        case .keepPrebidCreative:
            schedulePrebidRefresh()
        case .reloadPrebid:
            if let prebidBanner { environment.network.loadPrebid(prebidBanner) }
        case .none:
            break
        }
    }

    /// Whether a .prebidOnly reattach keeps the already-rendered creative (letting
    /// its viewability tracker fire the impression/burl) and resumes the refresh
    /// cadence on a delayed timer, instead of immediately re-auctioning (which
    /// discards the creative before it can be counted). Remote-config gated;
    /// defaults to `false` (today's behavior) so it ships dormant and can be
    /// validated per-partner from the CDN with no release. Set
    /// `MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH: true` to enable.
    private var keepsPrebidCreativeOnReattach: Bool {
        SellwildAdPolicy.flag(config.remoteValues?[SellwildAdPolicy.keepCreativeOnReattachKey], default: false)
    }

    /// Resume the .prebidOnly refresh cadence WITHOUT discarding the current
    /// creative: wait one refresh interval, then re-auction. During the wait the
    /// already-rendered creative stays on screen, so its viewability tracker can
    /// fire the impression/burl. Only re-auctions if still attached and under the
    /// refresh cap.
    private func schedulePrebidRefresh() {
        guard hasPrebidRefreshBudget else { return }
        refreshTimer?.cancel()
        refreshTimer = environment.scheduler.schedule(after: SellwildAdPolicy.refreshInterval(config.adRefreshInterval)) { [weak self] in
            self?.reloadPrebidIfAttached()
        }
    }

    private func reloadPrebidIfAttached() {
        guard window != nil, let prebidBanner else { return }
        environment.network.loadPrebid(prebidBanner)
    }

    // MARK: Detached-refresh pause (default ON — parity with Android)
    // Pause refresh while this view is fully detached from the window (pooled
    // cell) and resume on re-attach. Trims never-rendered detached-view refreshes
    // (the invalid-traffic edge + wasted auctions/CPU/battery) while keeping
    // off-screen-but-attached refreshes. ON by default; set
    // MOBILE_PAUSE_REFRESH_DETACHED = false to opt out.

    private var isPausedForDetach = false
    // Set when pause() interrupts an in-flight first auction (cold-start wait);
    // resume() then re-issues load() so the first impression isn't lost.
    private var needsReloadOnResume = false

    private var pausesRefreshWhenDetached: Bool {
        SellwildAdPolicy.flag(config.remoteValues?[SellwildAdPolicy.pauseRefreshWhenDetachedKey], default: true)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        let action = SellwildAdPolicy.detachAction(
            enabled: pausesRefreshWhenDetached, attached: window != nil, pausedForDetach: isPausedForDetach
        )
        switch action {
        case .pause:
            isPausedForDetach = true
            pause()
        case .resume:
            isPausedForDetach = false
            resume()
        case .none:
            break
        }
    }

    // MARK: GAM path (.both / .gamOnly)

    /// Emit the per-render `adRenderSucceeded` (every render/refresh, unchanged)
    /// plus — once per ad surface — the web-parity `firstAdViewed`. The latter
    /// carries the same `attributes.code` (stamped in `sendEvent`) but no label,
    /// matching the web widget, and is deduped by `firstAdViewedGuard`.
    private func emitAdRender() {
        let zone = zoneLabel
        environment.events.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: zone))
        firstAdViewedGuard.fireOnce {
            environment.events.sendEvent(SellwildEvent(event: "firstAdViewed"))
            SellwildLog.debug("[SellwildEvents] firstAdViewed fired once for this ad surface (zone \(zone))")
        }
    }

    private func loadGAM(runAuction: Bool) {
        let banner = ensureGAMBanner()
        // Re-resolve the GAM ad unit each load() in case `config` was swapped.
        banner.adUnitID = resolveGAMAdUnitID()
        banner.rootViewController = nearestViewController()

        // .gamOnly: a plain GAM request, no auction.
        guard runAuction else {
            environment.network.loadGAM(banner)
            return
        }
        // .both with no zone to bid against: still a plain GAM request, so GAM
        // line items serve, but the auction is skipped.
        guard let configId = zoneId, !configId.isEmpty else {
            reportZoneMissing(stack: .both, severity: .warn,
                              message: "the .both stack needs a zone id for the auction; a plain GAM request is sent")
            environment.network.loadGAM(banner)
            return
        }

        // Cold-start guard: Prebid init is async and races the first load(). Wait
        // briefly for readiness, then run the auction regardless — runBannerAuction
        // falls back to GAM on a Prebid miss, so the wait can only *add* Prebid
        // demand to the first impression, never drop fill.
        guard proceedAfterColdStart(retry: { $0.loadGAM(runAuction: true) }) else { return }

        // Bidder params are configured server-side in the stored imp. Don't send
        // CMS config inline — it includes non-bidder keys that PBS rejects. The
        // auction reports its own failures (SellwildPrebidMobile).
        environment.network.runBannerAuction(
            on: banner,
            configId: configId,
            adSizes: resolvedAdSizes,
            gpid: resolvedGpid,
            video: SellwildVideo.isEnabled(remoteValues: config.remoteValues, zoneId: zoneId)
        ) { result in
            SellwildLog.debug("[SellwildAdView] Prebid auction result: \(result.name())")
        }
    }

    /// The cold-start step the three load paths share. true: go on now (Prebid
    /// is ready, or the wait is spent: `ad.prebid_init.timeout`, once a
    /// launch). false: a retry of `retry` is scheduled.
    private func proceedAfterColdStart(retry: @escaping (SellwildAdView) -> Void) -> Bool {
        switch SellwildAdPolicy.coldStart(ready: environment.network.isPrebidReady(), attempts: prebidWaitAttempts) {
        case .wait:
            prebidWaitAttempts += 1
            prebidWaitTimer?.cancel()
            prebidWaitTimer = environment.scheduler.schedule(after: SellwildAdPolicy.prebidWaitInterval) { [weak self] in
                _ = self.map(retry)
            }
            return false
        case .timedOut:
            if SellwildReportOnce.first(.adPrebidInitTimeout) {
                SellwildFailures.log(code: .adPrebidInitTimeout, component: .banner, severity: .warn,
                                     message: "Prebid was not ready after the cold-start wait, so the ad loaded without waiting for it",
                                     zoneId: zoneId)
            }
            prebidWaitAttempts = 0
            return true
        case .ready:
            prebidWaitAttempts = 0
            return true
        }
    }

    /// A load path that needs a zone id has none (`ad.zone.missing`), once a
    /// launch per stack.
    private func reportZoneMissing(stack: String, severity: SellwildFailureSeverity, message: String) {
        guard SellwildReportOnce.first(.adZoneMissing, stack) else { return }
        SellwildFailures.log(code: .adZoneMissing, component: stack == "native" ? .native : .banner,
                             severity: severity, message: message)
    }

    private func reportZoneMissing(stack: SellwildAdStack, severity: SellwildFailureSeverity, message: String) {
        reportZoneMissing(stack: stack.rawValue, severity: severity, message: message)
    }

    private func ensureGAMBanner() -> AdManagerBannerView {
        // Tear down a Prebid-only banner if we previously rendered one (e.g.
        // the resolved stack changed between loads).
        if let pb = prebidBanner {
            pb.stopRefresh()
            pb.removeFromSuperview()
            prebidBanner = nil
            prebidHasRenderedCreative = false
            prebidClickModalOpen = false // didDismissModal may never arrive
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
            reportZoneMissing(stack: .prebidOnly, severity: .error,
                              message: "the .prebidOnly stack needs a zone id; no ad is loaded")
            delegate?.sellwildAdView?(self, didFailWithError: SellwildAdError.missingZoneIdForPrebidOnly)
            return
        }

        // Cold-start guard (mirrors the GAM path): Prebid init is async and races
        // the first load(). Unlike GAM we can't fall back to a GAM request, so a
        // premature loadAd() would no-fill and leave the slot blank. Wait briefly
        // for readiness, then load regardless once the wait budget is spent.
        guard proceedAfterColdStart(retry: { $0.loadPrebidOnly() }) else { return }

        let banner = ensurePrebidBanner(configId: configId)
        // Attach the GPID to the Prebid-rendered impression. This path makes its
        // own PBS bid request (no GAM), so it sets imp.ext directly on the
        // rendering banner — gpid + pbadslot only, no bidder params (those are
        // server-side stored config). Skipped entirely when no base resolves.
        if let ortbExt = SellwildGpid.impExtJSON(gpid: resolvedGpid) {
            banner.setImpORTBConfig(ortbExt)
        }
        // Prebid's rendering banner owns its own auto-refresh; mirror the GAM
        // cadence when configured — floored like the GAM timer so a mis-scaled
        // AD_REFRESH_INTERVAL can't drive a sub-second refresh storm. The refresh
        // COUNT is capped in the didReceiveAdWithAdSize delegate.
        // Cap 0 is no refresh (SellwildAdPolicy.prebidAutoRefreshInterval).
        banner.refreshInterval = SellwildAdPolicy.prebidAutoRefreshInterval(refreshMax: effectiveRefreshMax,
                                                                           configured: config.adRefreshInterval)
        prebidRefreshCount = 0
        prebidHasRenderedCreative = false
        environment.network.loadPrebid(banner)
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
        } else {
            // Defensive: this zone never requested video, but force the mute
            // config anyway in case a bidder/stored-imp still wins a video
            // creative on this banner-only imp. See forceDefaultMute's doc comment.
            SellwildVideo.forceDefaultMute(on: v)
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
            reportZoneMissing(stack: "native", severity: .error, message: "native needs a zone id; no ad is loaded")
            delegate?.sellwildAdView?(self, didFailWithError: SellwildAdError.missingZoneIdForPrebidOnly)
            return
        }
        // Cold-start guard (mirrors loadPrebidOnly): native fetchDemand can race
        // Prebid init, and native is one-shot (no auto-refresh/retry) — a premature
        // no-fill strands the slot on house/blank for its lifetime. Wait briefly
        // for readiness, then load regardless once the wait budget is spent.
        guard proceedAfterColdStart(retry: { $0.loadPrebidNative() }) else { return }
        ensureNativeAdView(configId: configId).load()
    }

    private func ensureNativeAdView(configId: String) -> SellwildNativeAdView {
        // Tear down banner render paths if we previously rendered one.
        if let gb = gamBanner { gb.removeFromSuperview(); gamBanner = nil }
        if let pb = prebidBanner {
            pb.stopRefresh()
            pb.removeFromSuperview()
            prebidBanner = nil
            prebidHasRenderedCreative = false
            prebidClickModalOpen = false // didDismissModal may never arrive
        }
        if let existing = nativeAdView { return existing }

        let cap = SellwildNative.maxHeight(
            remoteValues: config.remoteValues,
            zoneId: zoneId,
            fallback: adSize.cgSize.height
        )
        let v = SellwildNativeAdView(config: config, zoneId: configId, maxHeight: cap)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.onLoaded = { [weak self] in self?.nativeDidLoad(height: cap) }
        v.onClick = { [weak self] in self?.nativeWasClicked() }
        // Native no-fill is not a failure (FAILURES.md 4.3); the native view
        // reports a failed auction or a bid it could not create, so nothing
        // is logged again here (log once).
        v.onFailed = { [weak self] error in self?.nativeDidFail(error) }
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

    private func nativeDidLoad(height: CGFloat) {
        // Native filled — hide the house backdrop so it can't show through the
        // transparent native template (otherwise: two overlapping ads).
        houseView?.isHidden = true
        applyAudioGuard()
        delegate?.sellwildAdViewDidLoad?(self)
        // Native fills to the (capped) height; report it so the host slot
        // resizes to the template rather than clipping.
        delegate?.sellwildAdView?(self, didRenderWithSize: CGSize(width: adSize.cgSize.width, height: height))
        delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: zoneLabel)
        emitAdRender()
    }

    private func nativeWasClicked() {
        delegate?.sellwildAdViewDidRecordClick?(self)
        environment.events.sendEvent(SellwildEvent(event: "click", label: zoneLabel))
    }

    private func nativeDidFail(_ error: Error) {
        delegate?.sellwildAdView?(self, didFailWithError: error)
        environment.events.sendEvent(SellwildEvent(event: "adError", action: error.localizedDescription, label: zoneLabel))
        // Native no-fill — the house backdrop (installed in load()) is still
        // showing, so record it as a house impression, matching the banner
        // no-fill callbacks. No-op unless the house view is actually visible.
        recordHouseImpressionIfShowing()
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
        let content = SellwildAdPolicy.houseContent(
            enabled: SellwildHouseAd.isEnabled(remoteValues: config.remoteValues),
            image: SellwildHouseAd.resolve(remoteValues: config.remoteValues, zoneId: zoneId, size: adSize.cgSize),
            listing: houseFallbackListing,
            size: adSize.cgSize
        )
        switch content {
        case .none:
            houseView?.isHidden = true
        case .image(let creative):
            let view = ensureHouseView()
            view.onTap = { [weak self] in self?.openHouseURL(creative.clickURL) }
            view.showImage(creative)
        case .listing(let listing):
            let view = ensureHouseView()
            view.onTap = { [weak self] in self?.openHouseListing(listing) }
            view.showListing(listing, config: config)
        }
    }

    private func ensureHouseView() -> SellwildHouseAdView {
        if let houseView {
            houseView.isHidden = false
            return houseView
        }
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
    }

    /// Fire the house-impression callback when the backdrop is actually visible.
    private func recordHouseImpressionIfShowing() {
        guard let houseView, !houseView.isHidden else { return }
        delegate?.sellwildAdView?(self, didRecordHouseImpressionForZoneId: zoneLabel)
    }

    /// Best-effort, SDK-surface mute of auto-playing creative audio in this
    /// slot's WebView(s). No Prebid-fork dependency. See `SellwildAdAudioGuard`.
    private func applyAudioGuard() {
        SellwildAdAudioGuard.apply(to: self, remoteValues: config.remoteValues)
    }

    /// Defense-in-depth against outstream audio a request-side mute config
    /// doesn't guarantee is honored:
    ///  1. Placement validation — detect when the winning bid is actually
    ///     video/VAST despite this zone not requesting video (a bidder or
    ///     stored-imp ignoring the requested `imp.video` absence). Reports the
    ///     mismatch via analytics (and `ad.placement.invalid`) so we get real
    ///     visibility into how often it happens, rather than only muting silently.
    ///  2. Direct player enforcement — force-mute the actual rendered
    ///     `AVPlayer` (found by walking for an `AVPlayerLayer`-backed subview,
    ///     the same pattern `SellwildAdAudioGuard` uses for `WKWebView`), not
    ///     just the request-side `videoControlsConfig` — the same class of bug
    ///     already seen once (a config write not surviving to render).
    /// Runs on EVERY render, since a video creative can win regardless of
    /// whether this zone requested video.
    private func enforceVideoMuteAndValidatePlacement(on bannerView: PrebidBannerView) {
        let expectedVideo = SellwildVideo.isEnabled(remoteValues: config.remoteValues, zoneId: zoneId)
        guard let placement = SellwildAdPolicy.placement(
            bid: environment.network.winningBid(of: bannerView),
            expectedVideo: expectedVideo,
            soundEnabled: SellwildVideo.soundEnabled(remoteValues: config.remoteValues, zoneId: zoneId)
        ) else { return }

        if placement.mismatch {
            environment.events.sendEvent(SellwildEvent(event: "placementMismatch", label: zoneLabel))
            SellwildFailures.log(code: .adPlacementInvalid, component: .banner, severity: .warn,
                                 message: "a video creative won a banner-only zone", zoneId: zoneId)
        }
        for layer in playerLayers(in: bannerView) {
            layer.player?.isMuted = placement.muted
        }
    }

    /// Depth-first collect every `AVPlayerLayer`-backed view in the subtree
    /// rooted at `root` (mirrors `SellwildAdAudioGuard.webViews(in:)`).
    private func playerLayers(in root: UIView) -> [AVPlayerLayer] {
        var found: [AVPlayerLayer] = []
        if let layer = root.layer as? AVPlayerLayer { found.append(layer) }
        for sub in root.subviews { found.append(contentsOf: playerLayers(in: sub)) }
        return found
    }

    private func openHouseListing(_ listing: SellwildListing) {
        openHouseURL(listing.tapURL(partnerCode: config.partnerCode, bhTag: config.bhTag))
    }

    /// http/https only — the click URL is remote CMS config; never hand an
    /// arbitrary scheme (tel:/mailto:/deep link) to UIApplication.open. A house
    /// ad with no click URL is by design and not reported.
    private func openHouseURL(_ urlString: String?) {
        switch SellwildFeedLayout.openTarget(urlString) {
        case .success(let url):
            environment.openURL(url)
        case .failure(.notHTTP):
            SellwildFailures.log(code: .houseOpenUrlInvalid, component: .house, severity: .warn,
                                 message: "the house ad click URL is not http(s)", zoneId: zoneId)
        case .failure(.missing):
            break
        }
    }

    // MARK: Refresh (GAM path only — Prebid path self-refreshes)

    private func scheduleRefresh() {
        // Detached (paused for detach): a GAM load that lands after pause() must
        // not re-arm refresh on an off-window view — resume() restarts it.
        guard !isPausedForDetach else { return }
        guard SellwildAdPolicy.mayRefresh(count: refreshCount, max: effectiveRefreshMax) else { return }
        refreshTimer?.cancel() // never stack refresh timers (resume()/re-load)
        refreshTimer = environment.scheduler.schedule(after: SellwildAdPolicy.refreshInterval(config.adRefreshInterval)) { [weak self] in
            self?.refreshNow()
        }
    }

    private func refreshNow() {
        refreshCount += 1
        load()
    }

    /// The GAM ad unit (see `SellwildAdPolicy.gamAdUnit`). Google's test unit
    /// in place of a missing one is `ad.gam_unit.missing`, once a launch.
    private func resolveGAMAdUnitID() -> String {
        let unit = SellwildAdPolicy.gamAdUnit(gamTag: config.gamTag, remoteGAM: config.remoteValues?["GAM"],
                                              size: adSize.cgSize)
        if unit.isTestFallback, SellwildReportOnce.first(.adGamUnitMissing) {
            SellwildFailures.log(code: .adGamUnitMissing, component: .banner, severity: .fatal,
                                 message: "no GAM ad unit is configured (gamTag and GAM are empty), so Google's test ad unit is used",
                                 zoneId: zoneId)
        }
        return unit.id
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
    /// Runs the Prebid auction, then the GAM request.
    func runBannerAuction(on banner: AdManagerBannerView, configId: String, adSizes: [CGSize], gpid: String?,
                          video: Bool, completion: @escaping (ResultCode) -> Void)
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

    func runBannerAuction(on banner: AdManagerBannerView, configId: String, adSizes: [CGSize], gpid: String?,
                          video: Bool, completion: @escaping (ResultCode) -> Void) {
        SellwildPrebidMobile.runBannerAuction(on: banner, configId: configId, adSizes: adSizes, gpid: gpid,
                                              video: video, completion: completion)
    }

    func loadPrebid(_ banner: PrebidBannerView) {
        SellwildPrebidMobile.calls.loadPrebid(banner)
    }

    func winningBid(of banner: PrebidBannerView) -> SellwildAdPolicy.BidSummary? {
        guard let bid = banner.lastBidResponse?.winningBid else { return nil }
        return SellwildAdPolicy.BidSummary(isVideoFormat: bid.adFormat == .video,
                                           hasVideoConfig: bid.videoAdConfiguration != nil,
                                           adm: bid.adm)
    }

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

// MARK: - GAM BannerViewDelegate (.both / .gamOnly)

extension SellwildAdView: GoogleMobileAds.BannerViewDelegate {

    public func bannerViewDidReceiveAd(_ bannerView: GoogleMobileAds.BannerView) {
        // Paid creative rendered — hide the house backdrop so a transparent or
        // smaller-than-slot creative can't let it bleed through (re-shown on a
        // subsequent no-fill). Mirrors the native path; don't rely on the
        // creative being opaque and full-slot.
        houseView?.isHidden = true
        applyAudioGuard()
        delegate?.sellwildAdViewDidLoad?(self)
        // Report the actual rendered creative size so multi-size fallbacks (e.g.
        // a 320x50 win in a 300x250 request) resize the host slot.
        delegate?.sellwildAdView?(self, didRenderWithSize: bannerView.adSize.size)
        delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: zoneLabel)
        emitAdRender()
        scheduleRefresh()
    }

    public func bannerView(_ bannerView: GoogleMobileAds.BannerView,
                           didFailToReceiveAdWithError error: Error) {
        // No-fill — surface the house backdrop (re-shown in case a prior fill
        // hid it) so the slot isn't blank, then record the house impression.
        houseView?.isHidden = false
        delegate?.sellwildAdView?(self, didFailWithError: error)
        environment.events.sendEvent(SellwildEvent(event: "adError", action: error.localizedDescription, label: zoneLabel))
        // No-fill stays on adError (FAILURES.md 4.3); anything else is a failure.
        if !SellwildAdPolicy.isGAMNoFill(error) {
            SellwildFailures.log(code: .adGamLoadException, component: .banner, severity: .warn, error: error,
                                 message: "GAM failed to load an ad", zoneId: zoneId)
        }
        recordHouseImpressionIfShowing()
        scheduleRefresh()
    }

    public func bannerViewDidRecordClick(_ bannerView: GoogleMobileAds.BannerView) {
        delegate?.sellwildAdViewDidRecordClick?(self)
        environment.events.sendEvent(SellwildEvent(event: "click", label: zoneLabel))
    }
}

// MARK: - Prebid BannerViewDelegate (.prebidOnly)

extension SellwildAdView: PrebidBannerViewDelegate {

    public func bannerViewPresentationController() -> UIViewController? {
        let vc = nearestViewController()
        if vc == nil {
            SellwildFailures.log(code: .adPresenterMissing, component: .banner, severity: .warn,
                                 message: "no view controller to present the Prebid rendering banner; add the ad view to a live view controller before load()",
                                 zoneId: zoneId)
        }
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
            if SellwildAdPolicy.prebidRefreshSpent(count: prebidRefreshCount, max: effectiveRefreshMax) {
                bannerView.stopRefresh()
            }
        }
        prebidHasRenderedCreative = true
        // Paid creative rendered — hide the house backdrop so a transparent or
        // smaller-than-slot creative can't let it bleed through. NOTE: Prebid's
        // rendering banner self-refreshes with a teardown gap the backdrop used
        // to cover; that gap now shows the slot background briefly instead of
        // house inventory. Acceptable vs. the bleed-through it prevents, and only
        // affects .prebidOnly with refresh enabled.
        houseView?.isHidden = true
        applyAudioGuard()
        enforceVideoMuteAndValidatePlacement(on: bannerView)
        delegate?.sellwildAdViewDidLoad?(self)
        delegate?.sellwildAdView?(self, didRenderWithSize: adSize)
        delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: zoneLabel)
        emitAdRender()
    }

    public func bannerView(_ bannerView: PrebidBannerView,
                           didFailToReceiveAdWith error: Error) {
        // No-fill — surface the house backdrop (re-shown in case a prior fill
        // hid it) so the slot isn't blank, then record the house impression.
        houseView?.isHidden = false
        delegate?.sellwildAdView?(self, didFailWithError: error)
        environment.events.sendEvent(SellwildEvent(event: "adError", action: error.localizedDescription, label: zoneLabel))
        // No-bids stays on adError (FAILURES.md 4.3); anything else is a failure.
        if !SellwildAdPolicy.isPrebidNoFill(error) {
            SellwildFailures.log(code: .adPrebidRenderException, component: .banner, severity: .warn, error: error,
                                 message: "the Prebid rendering banner failed to load an ad", zoneId: zoneId)
        }
        recordHouseImpressionIfShowing()
    }

    // Prebid's rendering BannerView has no click callback — a click surfaces as
    // either an ad modal (in-app browser / App Store sheet) or leaving the app.
    // Report either as the same click the GAM path reports via
    // bannerViewDidRecordClick (delegate + "click" event).
    public func bannerViewWillPresentModal(_ bannerView: PrebidBannerView) {
        prebidClickModalOpen = true
        recordPrebidClick()
    }

    public func bannerViewDidDismissModal(_ bannerView: PrebidBannerView) {
        prebidClickModalOpen = false
    }

    public func bannerViewWillLeaveApplication(_ bannerView: PrebidBannerView) {
        // Leaving from inside a click-opened modal is the same click.
        guard !prebidClickModalOpen else { return }
        recordPrebidClick()
    }

    private func recordPrebidClick() {
        delegate?.sellwildAdViewDidRecordClick?(self)
        environment.events.sendEvent(SellwildEvent(event: "click", label: zoneLabel))
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
