import Foundation

/// First-class entry point for configuring the Sellwild SDK.
///
/// In 1.2.0+, partners can integrate the SDK with just a `partnerCode` and
/// `slug`. Everything else — listings URL, ad zones, app identity, refresh
/// intervals, waterfall partners, compliance flags — is fetched from the
/// Sellwild CDN at app launch.
///
/// ```swift
/// let config = await SellwildSDK.configure(
///     partnerCode: "acme",
///     slug: "acme-main"
/// )
/// ```
///
/// Every successful fetch is persisted to disk (see `SellwildConfigCache`).
/// On a network failure, timeout, server error or malformed response the call
/// falls back to the last good payload for this `partnerCode` + `slug`, applied
/// exactly as a fresh one would be — so ad zones and the ad stack survive an
/// offline or flaky launch. There is no expiry: a stale config beats none.
///
/// A 403, 404 or 410 is different: the CDN is saying the config was removed
/// (it answers 403 for a missing file). That is authoritative — the saved copy
/// is deleted and defaults are returned, so removing the CDN file works as a
/// kill switch.
///
/// Otherwise, only when there is no cached payload either (first launch with
/// no network) does the call return a bare `SellwildConfig(partnerCode:)` with
/// defaults.
/// That config has NO ad zones, so the feed shows listings but no ads, and
/// standalone ad views report `missingZoneIdForPrebidOnly` unless the host
/// supplies a zone id (the unknown ad stack defaults to `.prebidOnly`, which
/// never issues a Google Ad Manager request).
public enum SellwildSDK {

    /// SDK version, stamped into analytics events (`attributes.sdkVersion`) and
    /// the config-fetch User-Agent beacon. Keep in lockstep with the podspec
    /// `s.version` and the other platforms' version constants.
    public static let sdkVersion = "1.8.1"

    /// Build a `SellwildConfig` by fetching `partnerCode/slug.json` from the
    /// Sellwild CDN and applying it onto SDK defaults.
    ///
    /// - Parameters:
    ///   - partnerCode: The partner identifier provisioned by Sellwild.
    ///   - slug: The CMS slug for this app's config (e.g. `"acme-main"`).
    ///   - timeout: Network timeout in seconds. Default `5.0`.
    ///   - overrides: Optional closure to override fields after the remote
    ///     config is applied. Use this for app-controlled values (e.g.
    ///     `appBundleId = Bundle.main.bundleIdentifier`).
    public static func configure(
        partnerCode: String,
        slug: String,
        timeout: TimeInterval = 5.0,
        overrides: ((inout SellwildConfig) -> Void)? = nil
    ) async -> SellwildConfig {
        let outcome = await fetchRemotePayload(
            partnerCode: partnerCode, slug: slug, timeout: timeout
        )
        var config = resolveConfig(
            partnerCode: partnerCode, slug: slug, outcome: outcome
        )

        overrides?(&config)

        // Bootstrap PrebidMobile + GMA SDK as soon as we have a config. This
        // is idempotent — only the first call performs initialization, every
        // call after that is a cheap lock + early return. Doing it here means
        // partners get a fully-initialized native ad stack just by calling
        // `configure(...)`; no extra wiring required at the call site.
        // ...on the main actor: GMA `MobileAds.start`, Prebid `initializeSDK`, and
        // `Targeting` mutations are main-thread-sensitive, but this continuation
        // can resume off-main after the URLSession await above.
        await MainActor.run { SellwildPrebidMobile.bootstrap(with: config) }

        return config
    }

    /// What a config fetch produced.
    enum FetchOutcome: Equatable {
        /// 2xx with a JSON-object body.
        case payload(Data)
        /// The CDN says this config does not exist (see `goneStatusCodes`).
        /// Authoritative: the saved copy is discarded, not reused.
        case gone
        /// Anything else (network error, timeout, 5xx, malformed body). The
        /// saved copy, if any, is reused.
        case failed
    }

    /// Statuses that mean "this config was removed", so removing the CDN file
    /// works as a kill switch even for devices holding a saved copy. The CDN
    /// answers 403 (not 404) for a missing object, so 403 is included.
    static let goneStatusCodes: Set<Int> = [403, 404, 410]

    /// Classify an HTTP response. Network-free so it is unit-testable.
    static func fetchOutcome(statusCode: Int, body: Data) -> FetchOutcome {
        if goneStatusCodes.contains(statusCode) { return .gone }
        guard (200..<300).contains(statusCode),
              SellwildConfigCache.jsonObject(body) != nil
        else { return .failed }
        return .payload(body)
    }

    /// Fetch the raw config payload from the CDN. `.failed` on an unbuildable
    /// URL, network error, timeout, other non-2xx, or a body that isn't a JSON
    /// object — the caller then falls back to the saved payload.
    static func fetchRemotePayload(
        partnerCode: String,
        slug: String,
        timeout: TimeInterval
    ) async -> FetchOutcome {
        // A partnerCode/slug that can't form a URL is treated like a fetch
        // failure rather than crashing the host app.
        guard let url = URL(string:
            "https://widget.sellwild.com/app/\(partnerCode)/\(slug).json"
        ) else { return .failed }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Version beacon: fires on every config fetch (independent of the events
        // kill switch) and lands in CloudFront cs(User-Agent) logs for an
        // installed-base census.
        request.setValue("SellwildSDK/\(sdkVersion) (ios)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .failed }
        return fetchOutcome(statusCode: http.statusCode, body: data)
    }

    /// Outcome-based entry point used by `configure`. `.gone` discards the
    /// saved copy and returns defaults; otherwise see `resolveConfig(fetched:)`.
    static func resolveConfig(
        partnerCode: String,
        slug: String,
        outcome: FetchOutcome,
        cacheDirectory: URL? = nil
    ) -> SellwildConfig {
        switch outcome {
        case .payload(let data):
            return resolveConfig(
                partnerCode: partnerCode, slug: slug, fetched: data, cacheDirectory: cacheDirectory
            )
        case .failed:
            return resolveConfig(
                partnerCode: partnerCode, slug: slug, fetched: nil, cacheDirectory: cacheDirectory
            )
        case .gone:
            SellwildConfigCache.remove(
                partnerCode: partnerCode, slug: slug, directory: cacheDirectory
            )
            return SellwildConfig(partnerCode: partnerCode)
        }
    }

    /// Decide which payload configures the SDK — the freshly fetched one, else
    /// the last good one from disk, else none (defaults) — and apply it.
    /// Network-free so the fetched-vs-cached decision is unit-testable.
    ///
    /// - Parameters:
    ///   - fetched: The raw response body of a successful fetch, or nil when
    ///     the fetch failed for any reason.
    ///   - cacheDirectory: Cache location override for tests; nil = default.
    static func resolveConfig(
        partnerCode: String,
        slug: String,
        fetched: Data?,
        cacheDirectory: URL? = nil
    ) -> SellwildConfig {
        var config = SellwildConfig(partnerCode: partnerCode)

        if let data = fetched, let raw = SellwildConfigCache.jsonObject(data) {
            config = apply(raw, to: config)
            // Stash the raw payload so unmapped CDN keys (new bidders,
            // forward-compatible settings) stay readable via remoteValues
            // without an SDK release.
            config.remoteJSON = data
            SellwildConfigCache.store(
                data, partnerCode: partnerCode, slug: slug, directory: cacheDirectory
            )
        } else if let data = SellwildConfigCache.load(
            partnerCode: partnerCode, slug: slug, directory: cacheDirectory
        ), let raw = SellwildConfigCache.jsonObject(data) {
            // Fetch failed — reuse the last good payload exactly as if it had
            // just been fetched.
            config = apply(raw, to: config)
            config.remoteJSON = data
        }
        // else: no fetch and no cache — config retains defaults.

        return config
    }

    /// Maps CONSTANT_CASE CDN keys onto the corresponding `SellwildConfig`
    /// fields. Public so the React Native bridge (separate Swift module
    /// via cocoapods) can rebuild a feed-ready config from the JS-resolved
    /// `remote` payload without re-fetching the CDN.
    public static func apply(
        _ raw: [String: Any],
        to base: SellwildConfig
    ) -> SellwildConfig {
        var c = base

        // Identity
        if let v = raw["CODE"]      as? String { c.partnerCode = v }
        if let v = raw["SLUG"]      as? String { c.slug = v }
        if let v = raw["NAME"]      as? String { c.name = v }
        if let v = raw["LISTINGS"]  as? String { c.listingsUrl = v }

        // Display
        if let v = raw["TITLE"]            as? String   { c.title = v }
        if let v = raw["PARTNER_URL"]      as? String   { c.partnerUrl = v }
        if let v = raw["COL1"]             as? String   { c.col1 = v }
        if let v = raw["BH_TAG"]           as? String   { c.bhTag = v }
        if let v = raw["LINK_TEXT"]        as? String   { c.linkText = v }
        if let v = raw["BUY_NOW_TEXT"]     as? String   { c.buyNowText = v }
        if let v = raw["TITLE_COLOR"]      as? String   { c.titleColor = v }
        if let v = raw["LINK_COLOR"]       as? String   { c.linkColor = v }
        if let v = raw["FONT_COLOR"]       as? String   { c.fontColor = v }
        if let v = raw["PRICE_COLOR"]      as? String   { c.priceColor = v }
        if let v = raw["PRICE_FONT_COLOR"] as? String   { c.priceFontColor = v }
        if let v = (raw["BG_COLOR"] ?? raw["BACKGROUND"]) as? String { c.bgColor = v }
        if let v = raw["MARGIN_BOTTOM"]    as? Int      { c.marginBottom = v }
        if let v = raw["COLORS"]           as? [String] { c.colors = v }
        if let v = raw["OVERLAY_TITLE"]    as? Bool     { c.overlayTitle = v }
        if let v = raw["WATERMARK"]        as? Bool     { c.watermark = v }
        if let v = raw["WATERMARK_TITLE"]  as? String   { c.watermarkTitle = v }

        // Ad zones
        if let v = raw["BANNER_ZID"]         as? String   { c.bannerZid = v }
        if let v = raw["BOTTOM_BANNER_ZID"]  as? String   { c.bottomBannerZid = v }

        // Per-platform placement resolution (this mapper only ever runs on iOS
        // — the Swift SDK — so RN hosts on iOS resolve here too).
        // Three tiers, most specific first, per placement:
        //   1. per-placement per-platform  (MOBILE_ZID_IOS / MOBILE_BANNER_ZID_IOS)
        //   2. platform-wide "ALL"         (MOBILE_ZID_ALL_IOS — one value every
        //      mobile placement on this OS falls back to)
        //   3. shared base                 (MOBILE_ZID / MOBILE_BANNER_ZID)
        // Backward compatible: no suffixed key = today's behavior unchanged.
        let allIOS = (raw["MOBILE_ZID_ALL_IOS"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let v = raw["MOBILE_BANNER_ZID_IOS"] as? String, !v.isEmpty {
            c.mobileBannerZid = v
        } else if let v = allIOS {
            c.mobileBannerZid = v
        } else if let v = raw["MOBILE_BANNER_ZID"] as? String {
            c.mobileBannerZid = v
        }
        if let v = raw["MOBILE_ZID_IOS"] as? [String], !v.isEmpty {
            c.mobileZids = v
        } else if let v = allIOS {
            c.mobileZids = [v]
        } else if let v = raw["MOBILE_ZID"] as? [String] {
            c.mobileZids = v
        }
        if let v = raw["HIDE_BANNER_TOP"]    as? Bool     { c.hideBannerTop = v }
        if let v = raw["HIDE_BANNER_BOTTOM"] as? Bool     { c.hideBannerBottom = v }
        if let v = raw["GAM"]                as? String   { c.gamTag = v }
        if let v = raw["DISABLE_GPT"]        as? Bool     { c.disableGpt = v }
        if let v = raw["AD_DISABLE_DISPLAY"] as? Bool     { c.adDisableDisplay = v }

        // Refresh
        if let v = raw["AD_REFRESH_MAX"]        as? Int { c.adRefreshMax = v }
        if let v = raw["AD_REFRESH_MAX_MOBILE"] as? Int { c.adRefreshMaxMobile = v }
        // AD_REFRESH_INTERVAL is milliseconds (matches web + TS core); the iOS
        // API (`adRefreshInterval`, a TimeInterval) is seconds — convert.
        if let v = raw["AD_REFRESH_INTERVAL"]   as? Double {
            c.adRefreshInterval = v / 1000.0
        }
        if let v = raw["MAX_FAILED_AUCTIONS"] as? Int { c.maxFailedAuctions = v }

        // Compliance
        if let v = raw["GPP_ENABLED"] as? Bool     { c.gppEnabled = v }
        if let v = raw["TCF_VERSION"] as? Int      { c.tcfVersion = v }
        // IAB_CATS ships as an array OR a string — one value ("IAB15") or
        // comma-separated ("IAB15,IAB19"). Trim entries and drop blanks.
        let rawCats: [String]? = (raw["IAB_CATS"] as? [String])
            ?? (raw["IAB_CATS"] as? String)?.components(separatedBy: ",")
        if let v = rawCats {
            c.iabCats = v.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        // Mobile ad controls
        if let v = raw["ENABLE_INTERSTITIAL"]         as? Bool { c.enableInterstitial = v }
        if let v = raw["ENABLE_FULLSCREEN_VIDEO"]     as? Bool { c.enableFullscreenVideo = v }
        if let v = raw["INTERSTITIALS_PER_SESSION"]   as? Int  { c.interstitialsPerSession = v }
        if let v = raw["VIDEO_TAKEOVERS_PER_SESSION"] as? Int  { c.videoTakeoversPerSession = v }

        // App identity — per-platform override wins (APP_*_IOS), else the shared value.
        // (On the native Prebid path app.bundle is derived from the store URL's numeric id,
        // so APP_STORE_URL[_IOS] is the one that must carry the App Store link.)
        if let v = (raw["APP_BUNDLE_ID_IOS"] as? String) ?? (raw["APP_BUNDLE_ID"] as? String) { c.appBundleId = v }
        if let v = (raw["APP_STORE_URL_IOS"] as? String) ?? (raw["APP_STORE_URL"] as? String) { c.appStoreUrl = v }

        // Third-party
        if let v = raw["BOLTIVE"]           as? Bool   { c.boltive = v }
        if let v = raw["BOLTIVE_CLIENT_ID"] as? String { c.boltiveClientId = v }
        if let v = raw["LOTAME"]            as? Bool   { c.lotame = v }

        // Debug
        if let v = raw["DEBUG"] as? Bool { c.debug = v }
        if let v = raw["PBS_DEBUG"] as? Bool { c.pbsDebug = v }

        return c
    }
}

// MARK: - SellwildConfigCache
//
// Last-good remote config, persisted so a failed fetch (offline launch, CDN
// blip, timeout) still configures ad zones and the ad stack. One file per
// partnerCode + slug:
//
//   <Application Support>/SellwildSDK/config-<partner>-<slug>-<hash>.json
//
// <hash> is a stable hash of the raw "partner/slug" key, so keys that
// sanitize to the same text never share a file.
//
// The file holds the raw CDN response body, untouched. No TTL — a stale
// config beats none. Every disk error is swallowed: caching is best-effort
// and must never throw or crash the host app.

enum SellwildConfigCache {

    /// Default cache directory, or nil if Application Support is unavailable.
    static var defaultDirectory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SellwildSDK", isDirectory: true)
    }

    /// Replace anything outside `[A-Za-z0-9_-]` with `_` so partner/slug are
    /// safe as a single path component (no separators, no `..`).
    static func sanitize(_ component: String) -> String {
        String(component.unicodeScalars.map { u -> Character in
            switch u {
            case "A"..."Z", "a"..."z", "0"..."9", "_", "-": return Character(u)
            default: return "_"
            }
        })
    }

    /// Longest sanitized partner/slug kept in the file name.
    static let maxComponentLength = 64

    /// Stable (process-independent) FNV-1a hash of the raw key, as hex. Keeps
    /// keys that sanitize alike ("a-b"+"c" vs "a"+"b-c", "a/b" vs "a_b") in
    /// separate files. `hashValue` is seeded per process, so it can't be used.
    static func keyHash(partnerCode: String, slug: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(partnerCode)/\(slug)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    static func fileName(partnerCode: String, slug: String) -> String {
        let partner = String(sanitize(partnerCode).prefix(maxComponentLength))
        let slugPart = String(sanitize(slug).prefix(maxComponentLength))
        return "config-\(partner)-\(slugPart)-\(keyHash(partnerCode: partnerCode, slug: slug)).json"
    }

    static func fileURL(partnerCode: String, slug: String, directory: URL? = nil) -> URL? {
        (directory ?? defaultDirectory)?
            .appendingPathComponent(fileName(partnerCode: partnerCode, slug: slug), isDirectory: false)
    }

    /// Persist a raw config payload. Creates the directory on demand and
    /// writes atomically. Failures are ignored.
    static func store(_ data: Data, partnerCode: String, slug: String, directory: URL? = nil) {
        guard let url = fileURL(partnerCode: partnerCode, slug: slug, directory: directory) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort — a failed write just means no fallback next launch.
        }
    }

    /// The last stored payload for this partner + slug, or nil if there is
    /// none or it can't be read.
    static func load(partnerCode: String, slug: String, directory: URL? = nil) -> Data? {
        guard let url = fileURL(partnerCode: partnerCode, slug: slug, directory: directory) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Delete the stored payload for this partner + slug, if any. Failures are
    /// ignored.
    static func remove(partnerCode: String, slug: String, directory: URL? = nil) {
        guard let url = fileURL(partnerCode: partnerCode, slug: slug, directory: directory) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Parse a payload as a JSON object; nil for anything else.
    static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
