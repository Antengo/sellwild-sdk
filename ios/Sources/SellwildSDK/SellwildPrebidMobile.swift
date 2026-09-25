// SellwildPrebidMobile.swift — Prebid Mobile SDK bridge (required, not optional).
//
// In 1.3.0+, PrebidMobile (3.x) and Google-Mobile-Ads-SDK (11.x) are required
// dependencies of SellwildSDK. SellwildAdView runs a native Prebid auction and
// renders into a GAMBannerView — there is no WebView in the banner ad path.
//
// This file is the single point of contact between the SDK and the Prebid
// Mobile SDK. It reads its parameters off `SellwildConfig.prebidServer` /
// `config.remoteValues["S2S_CONFIG"]` so partners do not have to wire Prebid
// by hand. The decisions live in `SellwildPrebidConfig` (pure); the calls that
// start the SDKs or reach the network go through `calls`, which tests swap.

import Foundation
import UIKit
import SellwildPrebidSDK
import GoogleMobileAds

/// Public surface for bootstrapping Prebid Mobile + GMA from a `SellwildConfig`.
public enum SellwildPrebidMobile {

    /// Set to `true` once `bootstrap(with:)` has successfully kicked off
    /// initialization for both PrebidMobile and the GMA SDK. Subsequent calls
    /// become no-ops.
    private static var didBootstrap = false
    // Recursive: `bootstrap()` holds the lock while calling `applyGlobalORTB()`
    // (which re-acquires it for a snapshot), and `initializeSDK`'s completion
    // handler may fire synchronously on the same thread and also needs to
    // re-enter. NSLock would deadlock in either path.
    private static let lock = NSRecursiveLock()

    /// `true` once Prebid's async `initializeSDK` completion has fired without
    /// error. Distinct from `didBootstrap` (which is set synchronously when init
    /// is *kicked off*). `SellwildAdView` polls this to avoid firing the first
    /// auction before Prebid is ready and silently downgrading it to GAM-only.
    private static var initialized = false

    /// Whether Prebid Mobile has finished initializing and can run an auction.
    public static func isReady() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return initialized
    }

    // MARK: - Third-party calls

    /// The calls into GMA and Prebid that start their SDKs or reach the
    /// network. Partners always get `live`; tests swap `calls` for fakes.
    struct Calls {
        /// Starts GMA, then Prebid Mobile against `serverURL`. Reports the
        /// outcome through `initCompleted(error:)` / `initThrew(_:)`.
        var startSDKs: (_ serverURL: String) -> Void
        /// Runs the Prebid auction (a Prebid Server request).
        var fetchBannerDemand: (BannerAdUnit, AdManagerRequest, @escaping (ResultCode) -> Void) -> Void
        /// Sends the GAM ad request.
        var loadGAM: (AdManagerBannerView, AdManagerRequest) -> Void
        /// Sends the Prebid rendering request.
        var loadPrebid: (PrebidBannerView) -> Void

        static let live = Calls(startSDKs: liveStartSDKs, fetchBannerDemand: liveFetchBannerDemand,
                                loadGAM: SellwildLiveAdNetwork.sendGAMRequest,
                                loadPrebid: SellwildLiveAdNetwork.sendPrebidRequest)
    }

    static var calls = Calls.live

    // sellwild-coverage:exclude-begin(third-party-init) MobileAds.start and SellwildPrebid.initializeSDK need the app's GMA application id and the network; the outcome handlers below are tested.
    private static let liveStartSDKs: (String) -> Void = { serverURL in
        // GMA first — Prebid hands off to GAM, GAM must be live before any
        // ad request runs.
        MobileAds.shared.start(completionHandler: nil)
        do {
            // Prebid 3.x signature: serverURL is required, GMA version is
            // checked for compatibility.
            let v = MobileAds.shared.versionNumber
            let gmaVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            try SellwildPrebid.initializeSDK(serverURL: serverURL, gadMobileAdsVersion: gmaVersion) { status, error in
                initCompleted(status: "\(status)", error: error)
            }
        } catch {
            initThrew(error)
        }
    }
    // sellwild-coverage:exclude-end

    // sellwild-coverage:exclude-begin(fetch-demand) BannerAdUnit.fetchDemand sends the Prebid Server request.
    private static let liveFetchBannerDemand: (BannerAdUnit, AdManagerRequest, @escaping (ResultCode) -> Void) -> Void = {
        unit, request, completion in
        unit.fetchDemand(adObject: request, completion: completion)
    }
    // sellwild-coverage:exclude-end

    /// Prebid init finished. Ready means it completed without an error; the
    /// status is not matched against the fork's enum names, which are brittle.
    static func initCompleted(status: String, error: Error?) {
        if let error {
            SellwildFailures.log(code: .adPrebidInitException, component: .banner, severity: .fatal, error: error,
                                 message: "Prebid Mobile init completed with an error")
            return
        }
        SellwildLog.debug("[SellwildPrebidMobile] SellwildPrebid SDK init status: \(status)")
        lock.lock(); initialized = true; lock.unlock()
    }

    /// Prebid init threw before it started.
    static func initThrew(_ error: Error) {
        SellwildFailures.log(code: .adPrebidInitException, component: .banner, severity: .fatal, error: error,
                             message: "Prebid Mobile init threw")
    }

    // MARK: - Bootstrap

    /// Initialize PrebidMobile + GMA SDK from a `SellwildConfig`.
    ///
    /// Idempotent: safe to call from every `SellwildSDK.configure(...)` result
    /// and from every `SellwildAdView.load()` — only the first call performs
    /// SDK initialization. Subsequent calls return immediately.
    @discardableResult
    public static func bootstrap(with config: SellwildConfig) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didBootstrap { return true }
        let server = apply(config)
        calls.startSDKs(server.url)
        didBootstrap = true
        return true
    }

    /// Everything bootstrap sets before the SDKs start: the Prebid settings,
    /// the app identity and the global ORTB config. Local; no network.
    @discardableResult
    static func apply(_ config: SellwildConfig) -> SellwildPrebidConfig.Server {
        // Typed config wins; then the raw CDN passthrough; then Sellwild's
        // hosted Prebid Server, so the SDK still does something on partial
        // CMS config.
        let server = SellwildPrebidConfig.server(typed: config.prebidServer, remoteValues: config.remoteValues,
                                                 partnerCode: config.partnerCode)
        SellwildPrebid.shared.prebidServerAccountId = server.accountId
        SellwildPrebid.shared.timeoutMillis = config.prebidServer?.timeout ?? 1500
        SellwildPrebid.shared.shareGeoLocation = true
        if config.debug {
            SellwildPrebid.shared.logLevel = .debug
        }
        // Server-side auction debug — adds ext.prebid.debug=1 + returnallbidstatus
        // so the PBS response carries the full debug block. Separate from log level.
        SellwildPrebid.shared.pbsDebug = config.pbsDebug

        // OpenRTB app identity. Targeting.itunesID maps to app.bundle, which on
        // iOS must be the NUMERIC App Store id (buyers key on it; reverse-DNS
        // breaks matching). It comes from the store URL's `/idNNN` segment;
        // without one, app.bundle keeps Prebid's reverse-DNS default and the
        // edge Lambda backstops it. `sourceapp` (app.name) is left to Prebid.
        if let numericId = appStoreId(from: config.appStoreUrl) {
            Targeting.shared.itunesID = numericId
        } else if let store = config.appStoreUrl, !store.isEmpty {
            SellwildFailures.log(code: .configAppStoreUrlInvalid, component: .configure, severity: .warn,
                                 message: "APP_STORE_URL has no /id<number> segment, so app.bundle keeps the reverse-DNS default")
        }
        // storeURL is independent of the bundle id — set it whenever configured
        // so a valid appStoreUrl is never dropped just because appBundleId is nil.
        if let store = config.appStoreUrl {
            Targeting.shared.storeURL = store
        }

        // app.publisher.id must equal the sellers.json seller id (== schain
        // sid); IAB_CATS become app.cat. Both, with device.geo and
        // device.devicetype, go out as ONE global ORTB config (last write
        // wins); a later setGeo(_:) re-emits it with the new geo.
        lock.lock()
        resolvedPublisherId = SellwildPrebidConfig.publisherId(remoteValues: config.remoteValues)
        resolvedCats = config.iabCats.isEmpty ? nil : config.iabCats
        lock.unlock()
        if SellwildGeoStore.current == nil { SellwildGeoStore.current = config.geo }
        applyGlobalORTB()
        return server
    }

    // MARK: - Banner auction

    /// Run a Prebid auction for `adSize` keyed by `configId`, then load a
    /// `GAMBannerView` with the winning Prebid keywords applied.
    ///
    /// If Prebid wins, GAM serves the cached creative. If Prebid loses or the
    /// auction errors, GAM still gets the request and serves its own demand.
    /// Either way, ad fill is attempted.
    ///
    /// - Parameters:
    ///   - bannerView: An already-constructed `AdManagerBannerView` (sized + adUnitID
    ///     set + rootViewController set + delegate set by the caller).
    ///   - configId: Prebid Server stored impression id.
    ///   - adSizes: Banner sizes to auction, primary first. Additional sizes let
    ///     demand fall back to a smaller creative when the primary doesn't fill.
    ///   - bidderParams: Optional bidder params forwarded to Prebid Server as
    ///     impression-level ORTB ext data via `setImpORTBConfig`.
    ///   - gpid: Optional client-side GPID (Global Placement ID). When set, it's
    ///     written to both `imp.ext.gpid` and `imp.ext.data.pbadslot`. nil ⇒ no
    ///     gpid/pbadslot is sent.
    public static func runBannerAuction(
        on bannerView: AdManagerBannerView,
        configId: String,
        adSizes: [CGSize],
        bidderParams: [String: Any] = [:],
        gpid: String? = nil,
        video: Bool = false,
        completion: @escaping (ResultCode) -> Void
    ) {
        let primary = adSizes.first ?? CGSize(width: 300, height: 250)
        let unit = BannerAdUnit(configId: configId, size: primary)
        // Additional banner sizes for the Prebid bid (primary set above).
        SellwildAdSizes.applyPrebid(adSizes, to: unit)

        // Declare MRAID + Open Measurement (OMID) so buyers can serve rich-media
        // and measure viewability — mirrors the Android banner path.
        let bannerParams = BannerParameters()
        bannerParams.api = [Signals.Api.MRAID_3, Signals.Api.OMID_1]
        unit.bannerParameters = bannerParams

        // Multiformat: also request outstream video when enabled for this
        // placement. GAM renders the winning creative (video fill needs a GAM
        // outstream line item / renderer).
        if video {
            unit.adFormats = [.banner, .video]
            unit.videoParameters = SellwildVideo.outstreamParameters()
        }

        // Forward raw CDN bidder params + the GPID as ORTB imp.ext config. Prebid
        // Server resolves stored requests against this on its side. Emit whenever
        // there are bidder params OR a gpid to send (gpid alone still needs an
        // imp.ext, which the old bidder-params-only guard would have dropped).
        if !bidderParams.isEmpty || gpid != nil,
           let ortbExt = SellwildGpid.impExtJSON(gpid: gpid, bidderParams: bidderParams) {
            unit.setImpORTBConfig(ortbExt)
        }

        let request = AdManagerRequest()
        let current = calls
        current.fetchBannerDemand(unit, request) { result in
            // No-bids is not a failure (FAILURES.md 4.3); another error result is.
            if SellwildAdPolicy.isAuctionFailure(result.rawValue) {
                SellwildFailures.log(code: .adPrebidAuctionInvalid, component: .banner, severity: .warn,
                                     message: "the Prebid auction failed: \(result.name())", zoneId: configId)
            }
            // Whether or not Prebid won, we always load the GAM request so
            // GAM's own demand can fill on no-bid.
            current.loadGAM(bannerView, request)
            completion(result)
        }
    }

    // MARK: - Helpers

    /// Extract the numeric Apple App Store ID from a store URL, e.g.
    /// `https://apps.apple.com/us/app/weatherbug/id281940292` -> `"281940292"`.
    /// Anchored on `/id` at the start and on a URL boundary at the end
    /// (`/`, `?`, `#`, or end-of-string) so slugs like `/id281940292abc` or
    /// `/idea-app/…` can't false-match. Returns nil when the URL has no
    /// `/idNNNNN` segment.
    static func appStoreId(from storeURL: String?) -> String? {
        guard let storeURL,
              let range = storeURL.range(
                of: #"/id(\d+)(?=[/?#]|$)"#,
                options: .regularExpression
              )
        else { return nil }
        return String(storeURL[range].dropFirst(3))  // drop "/id"
    }

    /// Publisher id resolved at bootstrap, retained so `applyGlobalORTB()` can
    /// re-emit it alongside geo without re-reading config. Protected by `lock`.
    private static var resolvedPublisherId: String?
    private static var resolvedCats: [String]?

    /// Map a `UIUserInterfaceIdiom` to the IAB OpenRTB `device.devicetype`
    /// enum: phone → 4 (PHONE), pad → 5 (TABLET); anything else → 1
    /// (MOBILE/TABLET) as a safe generic-mobile fallback for unknown / tv /
    /// carPlay / vision idioms. `internal` (not `private`) so unit tests can
    /// exercise the mapping without a live device.
    static func deviceType(for idiom: UIUserInterfaceIdiom) -> Int {
        switch idiom {
        case .phone: return 4  // PHONE
        case .pad:   return 5  // TABLET
        default:     return 1  // MOBILE/TABLET
        }
    }

    /// Emit one combined global ORTB config (see `SellwildPrebidConfig.globalORTB`).
    ///
    /// Thread-safe: takes a snapshot of `resolvedPublisherId` and the current
    /// geo under `lock`, then serializes and hands the string to Prebid outside
    /// the lock. Callers may invoke this from any thread; `bootstrap()` and
    /// `setGeo()` are already the only writers.
    static func applyGlobalORTB(serialize: (Any) throws -> Data = SellwildPrebidConfig.serializeJSON) {
        lock.lock()
        let pid = resolvedPublisherId
        let cats = resolvedCats
        let geoDict = SellwildGeoStore.current?.ortbGeoDict
        lock.unlock()

        let root = SellwildPrebidConfig.globalORTB(publisherId: pid, cats: cats, geo: geoDict,
                                                   deviceType: deviceType(for: UIDevice.current.userInterfaceIdiom))
        switch SellwildPrebidConfig.json(root, serialize: serialize) {
        case .success(let json):
            Targeting.shared.setGlobalORTBConfig(json)
        case .failure(.notJSON):
            SellwildFailures.log(code: .adOrtbConfigException, component: .banner, severity: .warn,
                                 message: "the global ORTB config holds a value JSON cannot carry, so app.publisher, device.geo and devicetype are not sent")
        case .failure(.serialization(let error)):
            SellwildFailures.log(code: .adOrtbConfigException, component: .banner, severity: .warn, error: error,
                                 message: "the global ORTB config could not be serialized, so app.publisher, device.geo and devicetype are not sent")
        }
    }

    /// Set or update partner-supplied geo at runtime, emitted as OpenRTB
    /// `device.geo` on subsequent native Prebid auctions. Use when location is
    /// resolved or changes after `bootstrap(with:)`. Re-emits the combined ORTB
    /// config so `app.publisher.id` is preserved. Pass `nil` to clear geo.
    ///
    /// The value is also stored in `SellwildGeoStore.current` (itself
    /// thread-safe), so other SDK surfaces (e.g. the listings feed) and
    /// host-app code can read the current geo — it is not confined to the
    /// Prebid auction path.
    public static func setGeo(_ geo: SellwildGeo?) {
        SellwildGeoStore.current = geo
        applyGlobalORTB()
    }

    /// Back to before the first bootstrap, with the live calls. Tests only.
    static func resetForTesting() {
        lock.lock()
        didBootstrap = false
        initialized = false
        resolvedPublisherId = nil
        resolvedCats = nil
        calls = .live
        lock.unlock()
    }
}
