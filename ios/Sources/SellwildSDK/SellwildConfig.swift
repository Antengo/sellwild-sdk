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
    public var listingsUrl: String
    public var apiBaseUrl: String

    // MARK: Display
    public var title: String?
    public var linkText: String?
    public var buyNowText: String?
    public var titleColor: String
    public var titleSize: Int
    public var linkColor: String
    public var fontSize: Int
    public var fontColor: String
    public var priceColor: String
    public var priceFontColor: String
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
    public var ix: IxConfig?
    public var openx: OpenxConfig?
    public var pubmatic: PubmaticConfig?
    public var appnexus: AppnexusConfig?

    // MARK: Waterfall Partners
    public var pubVentures: WaterfallPartnerConfig?
    public var saambaa: WaterfallPartnerConfig?
    public var opsco: WaterfallPartnerConfig?
    public var bidstream: WaterfallPartnerConfig?

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

    // MARK: Prebid Server S2S (optional)
    /// Route all Prebid.js bidder calls through a Prebid Server instance instead of
    /// running client-side adapters in the WebView. Solves cookie/IDFA limitations.
    /// Leave nil to use the default Prebid.js client-side mode.
    public var prebidServer: PrebidServerConfig?

    // MARK: Widget override
    /// Override the widget JS bundle URL. Leave nil to use the default generic bundle
    /// at https://widget.sellwild.com/partner.js, which reads all config from element attributes.
    /// Set to a publisher-specific compiled bundle URL to skip attribute serialization.
    public var widgetJsUrl: String?

    // MARK: Debug
    public var debug: Bool

    public init(
        partnerCode: String,
        listingsUrl: String,
        apiBaseUrl: String = "https://api.sellwild.com",
        slug: String = "",
        name: String = ""
    ) {
        self.partnerCode = partnerCode
        self.listingsUrl = listingsUrl
        self.apiBaseUrl = apiBaseUrl
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
        self.appBundleId = nil
        self.appStoreUrl = nil
        self.prebidServer = nil
        self.widgetJsUrl = nil
        self.debug = false
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
