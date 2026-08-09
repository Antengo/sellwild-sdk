import Foundation

// MARK: - Core Configuration

/// Main configuration object for the Sellwild ad SDK.
/// Mirrors the web widget's ICustomizations, adapted for native mobile.
public struct SellwildConfig: Codable {

    // MARK: Identity
    public var partnerCode: String
    public var slug: String
    public var name: String

    // MARK: API
    /// URL of the listings API. Optional in 1.2.0+ — typically populated from
    /// remote config. When unset, the SDK falls back to the general listings
    /// cache at `defaultListingsCacheURL`.
    public var listingsUrl: String?

    /// General listings cache — a generic image-data blob served from the CDN
    /// (not partner-scoped). Used as the fallback when no `listingsUrl` is set.
    public static let defaultListingsCacheURL = "https://cache.sellwild.com/listings-img-data-sm"

    /// Effective listings URL. Returns `listingsUrl` when set, otherwise falls
    /// back to the general listings cache (`defaultListingsCacheURL`).
    public var effectiveListingsUrl: String {
        if let url = listingsUrl, !url.isEmpty { return url }
        return SellwildConfig.defaultListingsCacheURL
    }

    // MARK: Display
    public var title: String?
    /// Optional URL the feed header title links to. Tapping the title in
    /// `SellwildFeedView` opens this URL in `SFSafariViewController`. When
    /// `nil`, the title is non-tappable.
    public var partnerUrl: String?
    /// COL1 — single-column row schedule for `SellwildFeedView`.
    /// Each character is one row, top to bottom:
    ///   `L` = listing card
    ///   `G` = GAM 300x250 ad (zone ID drawn from `mobileZids` in order)
    ///   `D` = direct ad unit (300x250, currently rendered identically to `G`)
    ///   `B` = 320x50 banner (zone ID = `mobileBannerZid`)
    /// The renderer iterates the string left-to-right and stops when the
    /// string is exhausted. When `nil` or empty, the feed falls back to a
    /// default of `"LLGLLGLLG"`.
    public var col1: String?
    /// Bargain Hunter affiliate tag. When set, listing tap URLs that already
    /// carry a `listing.url` get a `?tag={bhTag}` query param appended, matching
    /// the web widget's `getListingUrl()` behavior.
    public var bhTag: String?
    public var linkText: String?
    public var buyNowText: String?
    public var titleColor: String
    public var titleSize: Int
    public var linkColor: String
    public var fontSize: Int
    public var fontColor: String
    public var priceColor: String
    public var priceFontColor: String
    /// Feed background color (hex). Maps to CDN `BG_COLOR` / `BACKGROUND`.
    /// When nil, the feed uses a light neutral so white listing cards have
    /// gentle contrast instead of floating on a near-black surface.
    public var bgColor: String?
    public var marginBottom: Int
    public var colors: [String]
    public var overlayTitle: Bool
    public var watermark: Bool
    public var watermarkTitle: String

    // MARK: Ads - Display
    /// Ad system to initialize. Defaults to "PrebidOnly". AdStack silently
    /// no-ops if this is unset, so the SDK always sets it. See htmlBuilder.
    public var adType: String?
    public var bannerZid: String?
    public var bottomBannerZid: String?
    public var mobileBannerZid: String?
    public var mobileZids: [String]
    public var hideBannerTop: Bool
    public var hideBannerBottom: Bool
    public var gamTag: String?
    public var gptProxyUrl: String?
    public var disableGpt: Bool
    public var adDisableDisplay: Bool

    // MARK: Ads - Refresh
    public var adRefreshMax: Int
    public var adRefreshMaxMobile: Int
    public var adRefreshInterval: TimeInterval
    public var maxFailedAuctions: Int
    public var prebidSrc: String?

    // MARK: Ads - Compliance
    public var gppEnabled: Bool
    public var tcfVersion: Int
    public var iabCats: [String]

    // MARK: Ad Networks
    /// Deprecated in 1.2.1 — bidder configs now flow through `remoteJSON` as
    /// raw CDN passthrough. Kept for back-compat; will be removed in 2.0.
    @available(*, deprecated, message: "Access via remoteJSON instead. Will be removed in 2.0.")
    public var ix: IxConfig?
    @available(*, deprecated, message: "Access via remoteJSON instead. Will be removed in 2.0.")
    public var openx: OpenxConfig?
    @available(*, deprecated, message: "Access via remoteJSON instead. Will be removed in 2.0.")
    public var pubmatic: PubmaticConfig?
    @available(*, deprecated, message: "Access via remoteJSON instead. Will be removed in 2.0.")
    public var appnexus: AppnexusConfig?

    // MARK: Waterfall Partners
    @available(*, deprecated, message: "Access via remoteJSON instead. Will be removed in 2.0.")
    public var pubVentures: WaterfallPartnerConfig?
    @available(*, deprecated, message: "Access via remoteJSON instead. Will be removed in 2.0.")
    public var saambaa: WaterfallPartnerConfig?
    @available(*, deprecated, message: "Access via remoteJSON instead. Will be removed in 2.0.")
    public var opsco: WaterfallPartnerConfig?
    @available(*, deprecated, message: "Access via remoteJSON instead. Will be removed in 2.0.")
    public var bidstream: WaterfallPartnerConfig?

    // MARK: Remote Passthrough
    /// Raw remote-config payload as fetched from the CDN, stored as the
    /// original JSON bytes. Populated by `SellwildRemoteConfig.configure`.
    ///
    /// The widget's WebView attribute parser is case-insensitive and accepts
    /// arbitrary keys, so every entry in `remoteJSON` is forwarded to the
    /// widget verbatim. This means the SDK does NOT need a release whenever
    /// the CMS adds a new bidder or remote setting — partners receive new
    /// fields automatically the moment the CDN JSON includes them.
    ///
    /// Stored as `Data?` rather than `[String: Any]?` so the struct stays
    /// Codable. Use `remoteValues` for an `[String: Any]` view.
    public var remoteJSON: Data?

    /// Convenience: the raw CDN payload as a dictionary, parsed lazily on access.
    /// Returns nil if `remoteJSON` is unset or fails to parse.
    public var remoteValues: [String: Any]? {
        guard let data = remoteJSON else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Third-party
    public var boltive: Bool
    public var boltiveClientId: String
    public var lotame: Bool

    // MARK: Mobile app identity (for ortb2.app in Prebid.js)
    /// iOS bundle identifier of the host app (e.g. "com.mycompany.myapp").
    /// Used to populate `ortb2.app.bundle` so Prebid.js declares in-app inventory
    /// rather than web (ortb2.site) traffic. Without this, DSPs that buy app inventory
    /// separately will not bid and app-ads.txt enforcement is bypassed.
    public var appBundleId: String?
    /// App Store URL of the host app. Populates `ortb2.app.storeurl`.
    public var appStoreUrl: String?

    // MARK: Geo
    /// Partner-supplied geo (state, zip, city, lat/lon, …). Emitted as OpenRTB
    /// `device.geo` on native Prebid auctions, and its `state` keys per-state
    /// listing caches. Set via the `configure` overrides closure, or update at
    /// runtime with `SellwildPrebidMobile.setGeo(_:)`.
    public var geo: SellwildGeo?

    // MARK: Mobile ad controls (toggled remotely via CMS app config)
    public var enableInterstitial: Bool
    public var enableFullscreenVideo: Bool
    public var interstitialsPerSession: Int
    public var videoTakeoversPerSession: Int

    // MARK: Prebid Server S2S (optional)
    /// Route all Prebid.js bidder calls through a Prebid Server instance instead of
    /// running client-side adapters in the WebView. Solves cookie/IDFA limitations.
    /// Leave nil to use the default Prebid.js client-side mode.
    public var prebidServer: PrebidServerConfig?

    // MARK: GrowthCode Signal Resolve (identity)
    /// Local overrides for GrowthCode Signal Resolve. Each set field wins over
    /// the corresponding remote `GROWTHCODE_*` key; otherwise the remote value
    /// (or a default) applies. Leave nil to drive entirely from the CMS.
    public var growthCode: SellwildGrowthCodeConfig? = nil

    // MARK: Localized (geo-based) secondary listings
    /// Local override for the localized-listings integration. When set, it wins
    /// entirely over the remote `LOCALIZED_LISTINGS` object; otherwise the
    /// remote value applies. Leave nil to drive entirely from the CMS.
    public var localizedListings: SellwildLocalizedListingsConfig? = nil

    // MARK: Widget override
    /// Override the widget JS bundle URL. Leave nil to use the default generic bundle
    /// at https://widget.sellwild.com/partner.js, which reads all config from element attributes.
    /// Set to a publisher-specific compiled bundle URL to skip attribute serialization.
    public var widgetJsUrl: String?

    // MARK: Debug
    public var debug: Bool
    /// Server-side auction debug. When true, the SDK flips Prebid Mobile's
    /// `pbsDebug`, adding `ext.prebid.debug=1` + `returnallbidstatus` to the
    /// auction so the response carries the full debug block (per-bidder status,
    /// resolvedrequest, cache calls). Heavier responses — leave off in
    /// production. Independent of `debug` (which controls SDK log verbosity).
    public var pbsDebug: Bool

    public init(
        partnerCode: String,
        listingsUrl: String? = nil,
        slug: String = "",
        name: String = ""
    ) {
        self.partnerCode = partnerCode
        self.listingsUrl = listingsUrl
        self.slug = slug
        self.name = name

        // Defaults
        self.titleColor = "#000000"
        self.titleSize = 16
        self.linkColor = "#0066cc"
        self.fontSize = 13
        self.fontColor = "#ffffff"
        self.priceColor = "#333333"
        self.priceFontColor = "#ffffff"
        self.bgColor = nil
        self.marginBottom = 10
        self.colors = ["#333333"]
        self.overlayTitle = false
        self.watermark = false
        self.watermarkTitle = "Powered by Sellwild"
        self.mobileZids = []
        self.hideBannerTop = false
        self.hideBannerBottom = false
        self.disableGpt = false
        self.adDisableDisplay = false
        self.adRefreshMax = 0
        self.adRefreshMaxMobile = 0
        self.adRefreshInterval = 30.0
        self.maxFailedAuctions = 3
        self.gppEnabled = false
        self.tcfVersion = 0
        self.iabCats = []
        self.boltive = false
        self.boltiveClientId = ""
        self.lotame = false
        self.enableInterstitial = false
        self.enableFullscreenVideo = false
        self.interstitialsPerSession = 1
        self.videoTakeoversPerSession = 0
        self.appBundleId = nil
        self.appStoreUrl = nil
        self.geo = nil
        self.prebidServer = nil
        self.widgetJsUrl = nil
        self.debug = false
        self.pbsDebug = false
        self.remoteJSON = nil
    }
}

// MARK: - Prebid Server S2S Configuration

/// Configuration for routing Prebid.js header bidding through a Prebid Server instance.
/// Solves cookie and IDFA limitations that affect Prebid.js running in a native WebView.
public struct PrebidServerConfig: Codable {
    /// Your Prebid Server account ID.
    public var accountId: String
    /// Full URL to the Prebid Server auction endpoint.
    /// e.g. "https://prebid-server.example.com/openrtb2/auction"
    public var endpoint: String
    /// Bidder codes to route through Prebid Server.
    /// Must match the s2s adapter names in your Prebid Server config.
    public var bidders: [String]
    /// S2S auction timeout in ms. Default: 1500.
    public var timeout: Int
    /// Optional: Prebid Server /cookie_sync endpoint.
    public var syncEndpoint: String?

    public init(
        accountId: String,
        endpoint: String,
        bidders: [String],
        timeout: Int = 1500,
        syncEndpoint: String? = nil
    ) {
        self.accountId = accountId
        self.endpoint = endpoint
        self.bidders = bidders
        self.timeout = timeout
        self.syncEndpoint = syncEndpoint
    }
}

// MARK: - GrowthCode Signal Resolve Configuration

/// Local, code-supplied GrowthCode settings. Each field, when set, takes
/// precedence over the corresponding remote `GROWTHCODE_*` key. Leave fields
/// nil to drive them from the CMS.
public struct SellwildGrowthCodeConfig: Codable {
    /// Master on/off. When set, wins over remote `GROWTHCODE_ENABLED`.
    public var enabled: Bool?
    /// GrowthCode PartnerID — the `pid` query param. Required for the sync to run.
    public var partnerId: String?
    /// Sync endpoint. Defaults to the GrowthCode hosted endpoint.
    public var endpoint: String?
    /// Publisher domain sent as `u`/`h` (a native app has no page URL).
    public var syncUrl: String?
    /// Send the device advertising id (IDFA) when the host app holds ATT
    /// authorization. Default true. When false, the SDK skips the call entirely
    /// for devices with no usable id.
    public var sendMaid: Bool?
    /// Minimum hours between syncs. Default 48.
    public var ttlHours: Int?

    public init(
        enabled: Bool? = nil,
        partnerId: String? = nil,
        endpoint: String? = nil,
        syncUrl: String? = nil,
        sendMaid: Bool? = nil,
        ttlHours: Int? = nil
    ) {
        self.enabled = enabled
        self.partnerId = partnerId
        self.endpoint = endpoint
        self.syncUrl = syncUrl
        self.sendMaid = sendMaid
        self.ttlHours = ttlHours
    }
}

// MARK: - Localized Listings Configuration

/// Local, code-supplied localized-listings settings. When this object is set it
/// takes precedence over the remote `LOCALIZED_LISTINGS` object as a whole (not
/// field-by-field). `enabled == false` disables; an absent `enabled` on a
/// present object counts as on. Requires `baseUrl` + `urlTemplate` to activate.
public struct SellwildLocalizedListingsConfig: Codable {
    /// Master on/off. Absent (nil) on a present object counts as on; `false` disables.
    public var enabled: Bool?
    /// Optional label for the source, e.g. "sportserver".
    public var source: String?
    /// Cache base URL, e.g. "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/".
    public var baseUrl: String?
    /// Filename template with a `{state}` token, e.g. "sports-img-data-sm-webp-{state}.json".
    public var urlTemplate: String?
    /// Dispersion percent: 25 → every 4th feed slot is a localized listing.
    public var frequency: Int?
    /// Force a state (2-letter), overriding geo resolution — e.g. a known-Alabama site.
    public var forceState: String?

    public init(
        enabled: Bool? = nil,
        source: String? = nil,
        baseUrl: String? = nil,
        urlTemplate: String? = nil,
        frequency: Int? = nil,
        forceState: String? = nil
    ) {
        self.enabled = enabled
        self.source = source
        self.baseUrl = baseUrl
        self.urlTemplate = urlTemplate
        self.frequency = frequency
        self.forceState = forceState
    }
}

// MARK: - Ad Network Configs

public struct IxConfig: Codable {
    public var disabled: Bool?
    public var siteIdM: String
    public var siteIdD: String
}

public struct OpenxConfig: Codable {
    public var disabled: Bool?
    public var delDomain: String
    public var unitM: String
    public var unitD: String
}

public struct PubmaticConfig: Codable {
    public var disabled: Bool?
    public var pubIdM: String
    public var adSlotM: String
    public var adSlotD: String
}

public struct AppnexusConfig: Codable {
    public var disabled: Bool?
    public var placementIdM: Int
    public var placementIdD: Int
}

public struct WaterfallPartnerConfig: Codable {
    public var disabled: Bool?
    public var floorM: Double
    public var floorD: Double
    public var placementM300x250: String
    public var placementM320x50: String
    public var placementD300x250: String
    public var placementD728x90: String
    public var probabilityM: Double
    public var probabilityD: Double
    public var frequencyMax: Int
    public var frequencyDuration: TimeInterval
    public var geo: String
}

// MARK: - Ad Size

public enum AdSize: String, CaseIterable {
    case banner320x50  = "320x50"
    case mrec300x250   = "300x250"
    case leaderboard728x90 = "728x90"
    case halfPage300x600  = "300x600"
    case wideSkyscraper160x600 = "160x600"

    public var cgSize: CGSize {
        let parts = rawValue.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return .zero }
        return CGSize(width: parts[0], height: parts[1])
    }
}
