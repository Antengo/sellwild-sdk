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

    /// Initialize PrebidMobile + GMA SDK from a `SellwildConfig`.
    ///
    /// Idempotent: safe to call from every `SellwildSDK.configure(...)` result
    /// and from every `SellwildAdView.load()` — only the first call performs
    /// SDK initialization. Later calls with the same effective config return
    /// immediately; a later call with a DIFFERENT config re-applies the
    /// per-config Prebid fields (account id, server host/timeout, store URL,
    /// publisher id, app categories) without re-running SDK initialization.
    @discardableResult
    public static func bootstrap(with config: SellwildConfig) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let specified = perConfigFields(from: config)
        if didBootstrap {
            // Only fields this config actually specifies overwrite; absent ones
            // keep their last value, so a bare `SellwildConfig(partnerCode:)`
            // (or an RN-rebuilt config without remoteJSON) can't wipe a
            // CDN-resolved account / publisher id.
            let merged = specified.overlaying(appliedFields)
            if merged != appliedFields {
                // Only swap Host.shared when the URL itself changed: its tracking
                // URL is an unsynchronized var read by bid requests off-main, so a
                // needless rewrite (e.g. a timeout-only change) can race them.
                applyPerConfigFields(merged, updateHost: merged.serverURL != appliedFields?.serverURL)
            }
            return true
        }

        // GMA first — Prebid hands off to GAM, GAM must be live before any
        // ad request runs.
        MobileAds.shared.start(completionHandler: nil)

        // Resolve Prebid Server URL + account id + timeout. Typed config wins;
        // fall back to the CDN S2S_CONFIG; final fallback is Sellwild's hosted
        // Prebid Server so the SDK still does *something* on partial CMS config.
        let fields = specified.overlaying(PerConfigFields(
            serverURL: defaultPrebidEndpoint,
            accountId: config.partnerCode,
            timeout: defaultTimeoutMillis
        ))
        SellwildPrebid.shared.shareGeoLocation = true
        if config.debug {
            SellwildPrebid.shared.logLevel = .debug
        }
        // Server-side auction debug — adds ext.prebid.debug=1 + returnallbidstatus
        // so the PBS response carries the full debug block. Separate from log level.
        SellwildPrebid.shared.pbsDebug = config.pbsDebug

        if SellwildGeoStore.current == nil { SellwildGeoStore.current = config.geo }
        // Account / timeout / app identity / publisher id / cats, then the
        // combined global ORTB emit. The host is set by initializeSDK below.
        applyPerConfigFields(fields, updateHost: false)

        do {
            // Prebid 3.x signature: serverURL is required, GMA version is
            // checked for compatibility.
            let v = MobileAds.shared.versionNumber
            let gmaVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            try SellwildPrebid.initializeSDK(
                serverURL: fields.serverURL ?? defaultPrebidEndpoint,
                gadMobileAdsVersion: gmaVersion
            ) { status, error in
                if let error {
                    log("SellwildPrebid SDK init error: \(error.localizedDescription)")
                } else {
                    log("SellwildPrebid SDK init status: \(status)")
                    // Ready = completed without error. Deliberately not matched
                    // against a status enum token (brittle against the shaded
                    // fork's naming); a clean completion means auctions can run.
                    lock.lock(); initialized = true; lock.unlock()
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
           let ortbExt = ortbExtJSON(for: bidderParams, gpid: gpid) {
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

    /// Per-config Prebid fields `bootstrap` applies (and re-applies when a later
    /// config differs). nil = "this config doesn't specify it".
    private struct PerConfigFields: Equatable {
        var serverURL: String?
        var accountId: String?
        var timeout: Int?
        var storeURL: String?
        var publisherId: String?
        var cats: [String]?

        /// Fill fields this value leaves nil from `base`.
        func overlaying(_ base: PerConfigFields?) -> PerConfigFields {
            guard let base else { return self }
            return PerConfigFields(
                serverURL: serverURL ?? base.serverURL,
                accountId: accountId ?? base.accountId,
                timeout: timeout ?? base.timeout,
                storeURL: storeURL ?? base.storeURL,
                publisherId: publisherId ?? base.publisherId,
                cats: cats ?? base.cats
            )
        }
    }

    /// Last fields applied by `bootstrap`. Protected by `lock`.
    private static var appliedFields: PerConfigFields?

    private static func perConfigFields(from config: SellwildConfig) -> PerConfigFields {
        let server = specifiedPrebidServer(from: config)
        return PerConfigFields(
            serverURL: server?.endpoint,
            accountId: server?.accountId,
            timeout: server?.timeout,
            storeURL: config.appStoreUrl,
            publisherId: resolvePublisherId(from: config),
            // IAB content categories (IAB_CATS) → ORTB app.cat, so DSPs get content
            // taxonomy / brand-safety context on the bid request. Content signal, not
            // consent — safe to always attach when the CMS provides it.
            cats: config.iabCats.isEmpty ? nil : config.iabCats
        )
    }

    /// Push `f` into Prebid targeting and re-emit the global ORTB config.
    /// Caller holds `lock`. nil fields are left untouched.
    private static func applyPerConfigFields(_ f: PerConfigFields, updateHost: Bool) {
        if let acct = f.accountId { SellwildPrebid.shared.prebidServerAccountId = acct }
        if let t = f.timeout { SellwildPrebid.shared.timeoutMillis = t }
        if updateHost, let url = f.serverURL {
            do {
                try Host.shared.setHostURL(url, nonTrackingURLString: nil)
            } catch {
                log("SellwildPrebid host update failed: \(error.localizedDescription)")
            }
        }

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
        if let numericId = appStoreId(from: f.storeURL) {
            Targeting.shared.itunesID = numericId
        }
        // storeURL is independent of the bundle id — set it whenever configured
        // so a valid appStoreUrl is never dropped just because appBundleId is nil.
        if let store = f.storeURL {
            Targeting.shared.storeURL = store
        }

        // app.publisher.id must equal the sellers.json seller id (== schain sid)
        // for supply-chain coherence. No Targeting property maps to
        // app.publisher.id, so inject it via the global ORTB config.
        // Capture the resolved publisher id + cats, then emit ONE combined global
        // ORTB config (app.publisher.id + app.cat + device.geo).
        // setGlobalORTBConfig is last-write-wins, so all must live in a single
        // object; a later setGeo(_:) re-emits it with updated geo.
        // resolvedPublisherId is protected by `lock` — the caller holds it.
        // applyGlobalORTB() takes a snapshot under the same (recursive) lock, so
        // a concurrent setGeo() can't race the emit.
        resolvedPublisherId = f.publisherId
        resolvedCats = f.cats
        appliedFields = f
        applyGlobalORTB()
    }

    /// Prebid Server fields the config actually specifies: typed
    /// `prebidServer` (SDK code / partner override) wins, else the CDN
    /// `S2S_CONFIG` (usually a JS object-literal string — see
    /// `SellwildS2SConfig`). nil when neither is usable.
    private static func specifiedPrebidServer(from config: SellwildConfig) -> SellwildS2SConfig? {
        if let p = config.prebidServer {
            return SellwildS2SConfig(accountId: p.accountId, endpoint: p.endpoint, timeout: p.timeout)
        }
        return SellwildS2SConfig.parse(config.remoteValues?["S2S_CONFIG"])
    }

    private static let defaultTimeoutMillis = 1500

    private static let defaultPrebidEndpoint =
        "https://prebid.sellwild.com/openrtb2/auction"

    /// Wrap CDN bidder params (+ optional GPID) as `imp.ext` JSON. Prebid Server
    /// merges this with its own stored impression configuration. Delegates to
    /// `SellwildGpid.impExtJSON` so gpid + pbadslot are constructed at the single
    /// point shared with the `.prebidOnly` path.
    private static func ortbExtJSON(for params: [String: Any], gpid: String?) -> String? {
        SellwildGpid.impExtJSON(gpid: gpid, bidderParams: params)
    }

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

    /// Pull the OpenRTB app.publisher.id (== sellers.json seller id / schain sid)
    /// from the raw CDN payload's top-level `PUBLISHER_ID` (fallback `SELLER_ID`),
    /// accepting either a string or a JSON number.
    ///
    /// Reads the top-level key directly rather than the old `S2S_CONFIG` dict
    /// cast: S2S_CONFIG ships as a raw String (a JS object-literal), so the
    /// `[String: Any]` cast always failed and the publisher id was never set.
    /// Returns nil when absent/empty, preserving today's behavior (no
    /// app.publisher.id emitted) for partners without the key.
    private static func resolvePublisherId(from config: SellwildConfig) -> String? {
        guard let raw = config.remoteValues else { return nil }
        switch raw["PUBLISHER_ID"] ?? raw["SELLER_ID"] {
        case let s as String where !s.isEmpty: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
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

    /// Emit one combined global ORTB config carrying `app.publisher.id` and
    /// `device.geo`. `setGlobalORTBConfig` is last-write-wins, so both live in a
    /// single object rather than two competing calls.
    ///
    /// Thread-safe: takes a snapshot of `resolvedPublisherId` and the current
    /// geo under `lock`, then serializes and hands the string to Prebid outside
    /// the lock. Callers may invoke this from any thread; `bootstrap()` and
    /// `setGeo()` are already the only writers.
    private static func applyGlobalORTB() {
        lock.lock()
        let pid = resolvedPublisherId
        let cats = resolvedCats
        let geoDict = SellwildGeoStore.current?.ortbGeoDict
        lock.unlock()

        var app: [String: Any] = [:]
        if let pid, !pid.isEmpty {
            app["publisher"] = ["id": pid]
        }
        if let cats, !cats.isEmpty {
            app["cat"] = cats
        }
        // device.devicetype (IAB OpenRTB enum) is emitted on EVERY request so
        // DSPs and source-side analytics can bucket by device class. The iOS
        // Prebid fork does not populate it (Android does end-to-end), so inject
        // it here via the same global-ORTB merge path that already carries
        // device.geo — buyers receive device.os/make/model the same way.
        var device: [String: Any] = ["devicetype": deviceType(for: UIDevice.current.userInterfaceIdiom)]
        if let geoDict, !geoDict.isEmpty {
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
    /// The value is also stored in `SellwildGeoStore.current` (itself
    /// thread-safe), so other SDK surfaces (e.g. the listings feed) and
    /// host-app code can read the current geo — it is not confined to the
    /// Prebid auction path.
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
