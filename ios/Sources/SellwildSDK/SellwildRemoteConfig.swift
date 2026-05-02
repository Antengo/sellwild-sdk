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
///     partnerCode: "weatherbug",
///     slug: "weatherbug-main"
/// )
/// ```
///
/// On any network failure, timeout, or 404 the call returns a
/// `SellwildConfig(partnerCode:)` with deterministic defaults (the listings
/// endpoint is derived from `partnerCode`), so ads still render.
public enum SellwildSDK {

    /// Build a `SellwildConfig` by fetching `partnerCode/slug.json` from the
    /// Sellwild CDN and applying it onto SDK defaults.
    ///
    /// - Parameters:
    ///   - partnerCode: The partner identifier provisioned by Sellwild.
    ///   - slug: The CMS slug for this app's config (e.g. `"weatherbug-main"`).
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
        var config = SellwildConfig(partnerCode: partnerCode)

        let url = URL(string:
            "https://widget.sellwild.com/app/\(partnerCode)/\(slug).json"
        )!

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                config = apply(raw, to: config)
                // Stash the raw payload so unmapped CDN keys (new bidders,
                // forward-compatible settings) flow through to the WebView
                // attribute serializer without an SDK release.
                config.remoteJSON = data
            }
        } catch {
            // Silent fallback — config retains defaults.
        }

        overrides?(&config)

        // Bootstrap PrebidMobile + GMA SDK as soon as we have a config. This
        // is idempotent — only the first call performs initialization, every
        // call after that is a cheap lock + early return. Doing it here means
        // partners get a fully-initialized native ad stack just by calling
        // `configure(...)`; no extra wiring required at the call site.
        SellwildPrebidMobile.bootstrap(with: config)

        return config
    }

    /// Maps CONSTANT_CASE CDN keys onto the corresponding `SellwildConfig` fields.
    static func apply(
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
        if let v = raw["LINK_TEXT"]        as? String   { c.linkText = v }
        if let v = raw["BUY_NOW_TEXT"]     as? String   { c.buyNowText = v }
        if let v = raw["TITLE_COLOR"]      as? String   { c.titleColor = v }
        if let v = raw["LINK_COLOR"]       as? String   { c.linkColor = v }
        if let v = raw["FONT_COLOR"]       as? String   { c.fontColor = v }
        if let v = raw["PRICE_COLOR"]      as? String   { c.priceColor = v }
        if let v = raw["PRICE_FONT_COLOR"] as? String   { c.priceFontColor = v }
        if let v = raw["MARGIN_BOTTOM"]    as? Int      { c.marginBottom = v }
        if let v = raw["COLORS"]           as? [String] { c.colors = v }
        if let v = raw["OVERLAY_TITLE"]    as? Bool     { c.overlayTitle = v }
        if let v = raw["WATERMARK"]        as? Bool     { c.watermark = v }
        if let v = raw["WATERMARK_TITLE"]  as? String   { c.watermarkTitle = v }

        // Ad zones
        if let v = raw["BANNER_ZID"]         as? String   { c.bannerZid = v }
        if let v = raw["BOTTOM_BANNER_ZID"]  as? String   { c.bottomBannerZid = v }
        if let v = raw["MOBILE_BANNER_ZID"]  as? String   { c.mobileBannerZid = v }
        if let v = raw["MOBILE_ZID"]         as? [String] { c.mobileZids = v }
        if let v = raw["HIDE_BANNER_TOP"]    as? Bool     { c.hideBannerTop = v }
        if let v = raw["HIDE_BANNER_BOTTOM"] as? Bool     { c.hideBannerBottom = v }
        if let v = raw["GAM"]                as? String   { c.gamTag = v }
        if let v = raw["DISABLE_GPT"]        as? Bool     { c.disableGpt = v }
        if let v = raw["AD_DISABLE_DISPLAY"] as? Bool     { c.adDisableDisplay = v }

        // Refresh
        if let v = raw["AD_REFRESH_MAX"]        as? Int { c.adRefreshMax = v }
        if let v = raw["AD_REFRESH_MAX_MOBILE"] as? Int { c.adRefreshMaxMobile = v }
        if let v = raw["AD_REFRESH_INTERVAL"]   as? Double {
            c.adRefreshInterval = v
        }
        if let v = raw["MAX_FAILED_AUCTIONS"] as? Int { c.maxFailedAuctions = v }

        // Compliance
        if let v = raw["GPP_ENABLED"] as? Bool     { c.gppEnabled = v }
        if let v = raw["TCF_VERSION"] as? Int      { c.tcfVersion = v }
        if let v = raw["IAB_CATS"]    as? [String] { c.iabCats = v }

        // Mobile ad controls
        if let v = raw["ENABLE_INTERSTITIAL"]         as? Bool { c.enableInterstitial = v }
        if let v = raw["ENABLE_FULLSCREEN_VIDEO"]     as? Bool { c.enableFullscreenVideo = v }
        if let v = raw["INTERSTITIALS_PER_SESSION"]   as? Int  { c.interstitialsPerSession = v }
        if let v = raw["VIDEO_TAKEOVERS_PER_SESSION"] as? Int  { c.videoTakeoversPerSession = v }

        // App identity
        if let v = raw["APP_BUNDLE_ID"] as? String { c.appBundleId = v }
        if let v = raw["APP_STORE_URL"] as? String { c.appStoreUrl = v }

        // Third-party
        if let v = raw["BOLTIVE"]           as? Bool   { c.boltive = v }
        if let v = raw["BOLTIVE_CLIENT_ID"] as? String { c.boltiveClientId = v }
        if let v = raw["LOTAME"]            as? Bool   { c.lotame = v }

        // Debug
        if let v = raw["DEBUG"] as? Bool { c.debug = v }

        return c
    }
}
