// SellwildPrebidMobile.swift — Prebid Mobile SDK bridge (required, not optional).
//
// In 1.3.0+, PrebidMobile (3.x) and Google-Mobile-Ads-SDK (11.x) are required
// dependencies of SellwildSDK. SellwildAdView runs a native Prebid auction and
// renders into a GAMBannerView — there is no WebView in the banner ad path.
//
// This file is the single point of contact between the SDK and the Prebid
// Mobile SDK. It reads its parameters off `SellwildConfig.prebidServer` /
// `config.remoteValues["S2S_CONFIG"]` so partners do not have to wire Prebid
// by hand.

import Foundation
import SellwildPrebidSDK
import GoogleMobileAds

/// Public surface for bootstrapping Prebid Mobile + GMA from a `SellwildConfig`.
public enum SellwildPrebidMobile {

    /// Set to `true` once `bootstrap(with:)` has successfully kicked off
    /// initialization for both PrebidMobile and the GMA SDK. Subsequent calls
    /// become no-ops.
    private static var didBootstrap = false
    private static let lock = NSLock()

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

        // GMA first — Prebid hands off to GAM, GAM must be live before any
        // ad request runs.
        MobileAds.shared.start(completionHandler: nil)

        // Resolve Prebid Server URL + account id. Typed config wins; fall back
        // to raw CDN passthrough; final fallback is Sellwild's hosted Prebid
        // Server so the SDK still does *something* on partial CMS config.
        let resolved = resolvePrebidServer(from: config)
        SellwildPrebid.shared.prebidServerAccountId = resolved.accountId
        SellwildPrebid.shared.timeoutMillis = config.prebidServer?.timeout ?? 1500
        SellwildPrebid.shared.shareGeoLocation = true
        if config.debug {
            SellwildPrebid.shared.logLevel = .debug
        }
        // Server-side auction debug — adds ext.prebid.debug=1 + returnallbidstatus
        // so the PBS response carries the full debug block. Separate from log level.
        SellwildPrebid.shared.pbsDebug = config.pbsDebug

        // Populate ortb2.app so DSPs see in-app traffic, not web traffic.
        // OpenRTB app identity. In Prebid Mobile, Targeting.itunesID maps to
        // app.bundle; Targeting.sourceapp maps to app.NAME (not the bundle).
        // On iOS app.bundle must be the NUMERIC App Store ID — buyers key on it
        // (app-ads.txt / DSP allow-lists); reverse-DNS breaks matching. Derive
        // the numeric id from the store URL's `/idNNNNN` segment and set it via
        // itunesID. If we can't parse one, leave app.bundle to Prebid's default
        // (reverse-DNS Bundle id) and let the edge Lambda backstop it.
        //
        // NOTE: we deliberately no longer assign the bundle id to `sourceapp` —
        // that was polluting app.name with the reverse-DNS bundle. app.name is
        // left to Prebid's auto-detected display name.
        if let numericId = appStoreId(from: config.appStoreUrl) {
            Targeting.shared.itunesID = numericId
        }
        // storeURL is independent of the bundle id — set it whenever configured
        // so a valid appStoreUrl is never dropped just because appBundleId is nil.
        if let store = config.appStoreUrl {
            Targeting.shared.storeURL = store
        }

        // app.publisher.id must equal the sellers.json seller id (== schain sid)
        // for supply-chain coherence. No Targeting property maps to
        // app.publisher.id, so inject it via the global ORTB config. Sourced
        // from the CDN S2S_CONFIG blob (publisherId / sellerId).
        // Capture the resolved publisher id + any declared geo, then emit ONE
        // combined global ORTB config (app.publisher.id + device.geo).
        // setGlobalORTBConfig is last-write-wins, so both must live in a single
        // object; a later setGeo(_:) re-emits it with updated geo.
        resolvedPublisherId = resolvePublisherId(from: config)
        if SellwildGeoStore.current == nil { SellwildGeoStore.current = config.geo }
        applyGlobalORTB()

        do {
            // Prebid 3.x signature: serverURL is required, GMA version is
            // checked for compatibility.
            let v = MobileAds.shared.versionNumber
            let gmaVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            try SellwildPrebid.initializeSDK(
                serverURL: resolved.url,
                gadMobileAdsVersion: gmaVersion
            ) { status, error in
                if let error {
                    log("SellwildPrebid SDK init error: \(error.localizedDescription)")
                } else {
                    log("SellwildPrebid SDK init status: \(status)")
                }
            }
        } catch {
            log("SellwildPrebid SDK init threw: \(error.localizedDescription)")
        }

        didBootstrap = true
        return true
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
    ///   - adSize: Banner size to auction.
    ///   - bidderParams: Optional bidder params forwarded to Prebid Server as
    ///     impression-level ORTB ext data via `setImpORTBConfig`.
    public static func runBannerAuction(
        on bannerView: AdManagerBannerView,
        configId: String,
        adSize: CGSize,
        bidderParams: [String: Any] = [:],
        video: Bool = false,
        completion: @escaping (ResultCode) -> Void
    ) {
        let unit = BannerAdUnit(configId: configId, size: adSize)

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

        // Forward raw CDN bidder params as ORTB imp.ext config. Prebid Server
        // resolves stored requests against this on its side.
        if !bidderParams.isEmpty,
           let ortbExt = ortbExtJSON(for: bidderParams) {
            unit.setImpORTBConfig(ortbExt)
        }

        let request = AdManagerRequest()
        unit.fetchDemand(adObject: request) { result in
            // Whether or not Prebid won, we always load the GAM request so
            // GAM's own demand can fill on no-bid.
            bannerView.load(request)
            completion(result)
        }
    }

    // MARK: - Helpers

    private struct PrebidServerResolution {
        let url: String
        let accountId: String
    }

    private static func resolvePrebidServer(
        from config: SellwildConfig
    ) -> PrebidServerResolution {
        // 1. Typed config (set by SDK code or partner override).
        if let p = config.prebidServer {
            return PrebidServerResolution(url: p.endpoint, accountId: p.accountId)
        }
        // 2. Raw CDN passthrough.
        if let s2s = config.remoteValues?["S2S_CONFIG"] as? [String: Any] {
            let url = (s2s["endpoint"] as? String)
                ?? (s2s["url"] as? String)
                ?? defaultPrebidEndpoint
            let acct = (s2s["accountId"] as? String)
                ?? (s2s["account"] as? String)
                ?? config.partnerCode
            return PrebidServerResolution(url: url, accountId: acct)
        }
        // 3. Sellwild-hosted default.
        return PrebidServerResolution(
            url: defaultPrebidEndpoint,
            accountId: config.partnerCode
        )
    }

    private static let defaultPrebidEndpoint =
        "https://prebid.sellwild.com/openrtb2/auction"

    /// Wrap CDN bidder params as `imp.ext` JSON. Prebid Server merges this
    /// with its own stored impression configuration.
    private static func ortbExtJSON(for params: [String: Any]) -> String? {
        // imp.ext expects bidder names lowercased; CDN ships CONSTANT_CASE.
        var bidders: [String: Any] = [:]
        for (k, v) in params {
            bidders[k.lowercased()] = v
        }
        let imp: [String: Any] = ["ext": ["prebid": ["bidder": bidders]]]
        guard JSONSerialization.isValidJSONObject(imp),
              let data = try? JSONSerialization.data(withJSONObject: imp),
              let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    /// Extract the numeric Apple App Store ID from a store URL, e.g.
    /// `https://apps.apple.com/us/app/weatherbug/id281940292` -> `"281940292"`.
    /// Anchored on `/id` so a slug that merely contains "id" can't false-match.
    /// Returns nil when the URL has no `/idNNNNN` segment.
    static func appStoreId(from storeURL: String?) -> String? {
        guard let storeURL,
              let range = storeURL.range(of: #"/id\d+"#, options: .regularExpression)
        else { return nil }
        return String(storeURL[range].dropFirst(3))  // drop "/id"
    }

    /// Pull the OpenRTB app.publisher.id (== sellers.json seller id / schain sid)
    /// from the CDN S2S_CONFIG blob, accepting either a string or a JSON number.
    private static func resolvePublisherId(from config: SellwildConfig) -> String? {
        guard let s2s = config.remoteValues?["S2S_CONFIG"] as? [String: Any] else { return nil }
        switch s2s["publisherId"] ?? s2s["sellerId"] {
        case let s as String where !s.isEmpty: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    /// Publisher id resolved at bootstrap, retained so `applyGlobalORTB()` can
    /// re-emit it alongside geo without re-reading config.
    private static var resolvedPublisherId: String?

    /// Emit one combined global ORTB config carrying `app.publisher.id` and
    /// `device.geo`. `setGlobalORTBConfig` is last-write-wins, so both live in a
    /// single object rather than two competing calls.
    private static func applyGlobalORTB() {
        var app: [String: Any] = [:]
        if let pid = resolvedPublisherId, !pid.isEmpty {
            app["publisher"] = ["id": pid]
        }
        var device: [String: Any] = [:]
        if let geoDict = SellwildGeoStore.current?.ortbGeoDict, !geoDict.isEmpty {
            device["geo"] = geoDict
        }
        var root: [String: Any] = [:]
        if !app.isEmpty { root["app"] = app }
        if !device.isEmpty { root["device"] = device }
        guard !root.isEmpty,
              JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root),
              let json = String(data: data, encoding: .utf8) else { return }
        Targeting.shared.setGlobalORTBConfig(json)
    }

    /// Set or update partner-supplied geo at runtime, emitted as OpenRTB
    /// `device.geo` on subsequent native Prebid auctions. Use when location is
    /// resolved or changes after `bootstrap(with:)`. Re-emits the combined ORTB
    /// config so `app.publisher.id` is preserved. Pass `nil` to clear geo.
    ///
    /// The value is also stored in `SellwildGeoStore.current`, so other SDK
    /// surfaces (e.g. the listings feed) and host-app code can read the current
    /// geo — it is not confined to the Prebid auction path.
    public static func setGeo(_ geo: SellwildGeo?) {
        SellwildGeoStore.current = geo
        applyGlobalORTB()
    }

    @inline(__always)
    private static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[SellwildPrebidMobile] \(message())")
        #endif
    }
}
