package com.sellwild.sdk

import org.json.JSONObject

/**
 * Main configuration for the Sellwild ad SDK.
 * Mirrors the web widget's ICustomizations, adapted for Android.
 */
data class SellwildConfig(
    // Identity
    val partnerCode: String,
    /**
     * URL of the listings API. Optional in 1.2.0+ — typically populated from
     * remote config. When null, [effectiveListingsUrl] derives a default of
     * `"$apiBaseUrl/widget/listings?partner=$partnerCode"`.
     */
    val listingsUrl: String? = null,
    val slug: String = "",
    val name: String = "",
    val apiBaseUrl: String = "https://api.sellwild.com",

    // Display
    val title: String? = null,
    /**
     * Optional URL the feed header title links to. Tapping the title in
     * `SellwildFeedView` opens this URL in Custom Tabs. When null, the title
     * is non-tappable.
     */
    val partnerUrl: String? = null,
    /**
     * COL1 — single-column row schedule for `SellwildFeedView`.
     * Each character is one row, top to bottom:
     *   `L` = listing card
     *   `G` = GAM 300x250 ad (zone ID drawn from `mobileZids` in order)
     *   `D` = direct ad unit (300x250, currently rendered identically to `G`)
     *   `B` = 320x50 banner (zone ID = `mobileBannerZid`)
     * The renderer iterates the string left-to-right and stops when the
     * string is exhausted. When null or empty, the feed falls back to a
     * default of "LLGLLGLLG".
     */
    val col1: String? = null,
    val linkText: String? = "View all",
    val buyNowText: String? = "Buy now",
    val titleColor: String = "#000000",
    val titleSize: Int = 16,
    val linkColor: String = "#0066cc",
    val fontSize: Int = 13,
    val fontColor: String = "#ffffff",
    val priceColor: String = "#333333",
    val priceFontColor: String = "#ffffff",
    val marginBottom: Int = 10,
    val cardWidth: String = "300px",
    val colors: List<String> = listOf("#333333"),
    val overlayTitle: Boolean = false,
    val watermark: Boolean = false,
    val watermarkTitle: String = "Powered by Sellwild",

    // Ads - Display
    /** Ad system to initialize. Defaults to "PrebidOnly". AdStack silently
     *  no-ops if this is unset, so the SDK always sets it. */
    val adType: String? = null,
    val bannerZid: String? = null,
    val bottomBannerZid: String? = null,
    val mobileBannerZid: String? = null,
    val mobileZids: List<String> = emptyList(),
    val hideBannerTop: Boolean = false,
    val hideBannerBottom: Boolean = false,
    val gamTag: String? = null,
    val gptProxyUrl: String? = null,
    val disableGpt: Boolean = false,
    val adDisableDisplay: Boolean = false,

    // Ads - Refresh
    val adRefreshMax: Int = 0,
    val adRefreshMaxMobile: Int = 0,
    val adRefreshIntervalMs: Long = 30_000L,
    val maxFailedAuctions: Int = 3,
    val prebidSrc: String? = null,
    val floorMultiplier: Float = 1.0f,

    // Ads - Compliance
    val gppEnabled: Boolean = false,
    val tcfVersion: Int = 0,
    val iabCats: List<String> = emptyList(),

    // Ad Networks (deprecated 1.2.1 — use remoteJson; will be removed in 2.0)
    @Deprecated("Access via remoteJson instead. Will be removed in 2.0.")
    val ix: IxConfig? = null,
    @Deprecated("Access via remoteJson instead. Will be removed in 2.0.")
    val openx: OpenxConfig? = null,
    @Deprecated("Access via remoteJson instead. Will be removed in 2.0.")
    val pubmatic: PubmaticConfig? = null,
    @Deprecated("Access via remoteJson instead. Will be removed in 2.0.")
    val appnexus: AppnexusConfig? = null,

    // Waterfall Partners (deprecated 1.2.1)
    @Deprecated("Access via remoteJson instead. Will be removed in 2.0.")
    val pubVentures: WaterfallPartnerConfig? = null,
    @Deprecated("Access via remoteJson instead. Will be removed in 2.0.")
    val saambaa: WaterfallPartnerConfig? = null,
    @Deprecated("Access via remoteJson instead. Will be removed in 2.0.")
    val opsco: WaterfallPartnerConfig? = null,
    @Deprecated("Access via remoteJson instead. Will be removed in 2.0.")
    val bidstream: WaterfallPartnerConfig? = null,

    /**
     * Raw remote-config payload as fetched from the CDN, as the original
     * JSON string. Populated by [SellwildSDK.configure].
     *
     * The widget's WebView attribute parser is case-insensitive and accepts
     * arbitrary keys, so every entry in this payload is forwarded to the
     * widget verbatim. This means the SDK does NOT need a release whenever
     * the CMS adds a new bidder or remote setting — partners receive new
     * fields automatically the moment the CDN JSON includes them.
     */
    val remoteJson: String? = null,

    // Third-party
    val boltive: Boolean = false,
    val boltiveClientId: String = "",
    val lotame: Boolean = false,

    // Mobile ad controls (toggled remotely via CMS app config)
    val enableInterstitial: Boolean = false,
    val enableFullscreenVideo: Boolean = false,
    val interstitialsPerSession: Int = 1,
    val videoTakeoversPerSession: Int = 0,

    // Mobile app identity (for ortb2.app in Prebid.js)
    // Without appBundleId, Prebid.js sends bids as web (ortb2.site) traffic instead
    // of in-app traffic. DSPs that buy app inventory separately will not bid, and
    // app-ads.txt enforcement is bypassed.
    val appBundleId: String? = null,   // Android package name (e.g. "com.mycompany.myapp")
    val appStoreUrl: String? = null,   // Google Play Store URL for the host app

    // Prebid Server S2S (optional)
    // Route all Prebid.js bidder calls through a Prebid Server instance instead of running
    // client-side adapters in the WebView. Solves cookie/IDFA limitations.
    // Leave null to use the default Prebid.js client-side mode.
    val prebidServer: PrebidServerConfig? = null,

    // Debug
    val debug: Boolean = false,
) {
    /**
     * Effective listings URL. Returns [listingsUrl] when set, otherwise derives
     * a deterministic default from [partnerCode].
     */
    val effectiveListingsUrl: String
        get() = listingsUrl?.takeIf { it.isNotEmpty() }
            ?: "$apiBaseUrl/widget/listings?partner=$partnerCode"

    fun toJson(): JSONObject = JSONObject().apply {
        put("partnerCode", partnerCode)
        put("listingsUrl", effectiveListingsUrl)
        put("slug", slug)
        put("name", name)
        put("apiBaseUrl", apiBaseUrl)
        title?.let { put("title", it) }
        linkText?.let { put("linkText", it) }
        buyNowText?.let { put("buyNowText", it) }
        put("titleColor", titleColor)
        put("titleSize", titleSize)
        put("linkColor", linkColor)
        put("fontSize", fontSize)
        put("fontColor", fontColor)
        put("priceColor", priceColor)
        put("priceFontColor", priceFontColor)
        put("marginBottom", marginBottom)
        put("hideBannerTop", hideBannerTop)
        put("hideBannerBottom", hideBannerBottom)
        gamTag?.let { put("gamTag", it) }
        gptProxyUrl?.let { put("gptProxyUrl", it) }
        put("disableGpt", disableGpt)
        put("adRefreshMax", adRefreshMax)
        put("adRefreshMaxMobile", adRefreshMaxMobile)
        put("adRefreshInterval", adRefreshIntervalMs)
        put("boltive", boltive)
        put("boltiveClientId", boltiveClientId)
        put("enableInterstitial", enableInterstitial)
        put("enableFullscreenVideo", enableFullscreenVideo)
        put("interstitialsPerSession", interstitialsPerSession)
        put("videoTakeoversPerSession", videoTakeoversPerSession)
        put("debug", debug)
    }
}

data class IxConfig(
    val disabled: Boolean = false,
    val siteIdM: String,
    val siteIdD: String,
)

data class OpenxConfig(
    val disabled: Boolean = false,
    val delDomain: String,
    val unitM: String,
    val unitD: String,
)

data class PubmaticConfig(
    val disabled: Boolean = false,
    val pubIdM: String,
    val adSlotM: String,
    val adSlotD: String,
)

data class AppnexusConfig(
    val disabled: Boolean = false,
    val placementIdM: Int,
    val placementIdD: Int,
)

data class WaterfallPartnerConfig(
    val disabled: Boolean = false,
    val floorM: Float,
    val floorD: Float,
    val placementM300x250: String,
    val placementM320x50: String,
    val placementD300x250: String,
    val placementD728x90: String,
    val probabilityM: Float,
    val probabilityD: Float,
    val frequencyMax: Int,
    val frequencyDurationMs: Long,
    val geo: String,
)

/**
 * Configuration for routing Prebid.js header bidding through a Prebid Server instance.
 * Solves cookie and IDFA limitations that affect Prebid.js running in a native WebView.
 */
data class PrebidServerConfig(
    /** Your Prebid Server account ID. */
    val accountId: String,
    /**
     * Full URL to the Prebid Server auction endpoint.
     * e.g. "https://prebid-server.example.com/openrtb2/auction"
     */
    val endpoint: String,
    /**
     * Bidder codes to route through Prebid Server.
     * Must match the s2s adapter names in your Prebid Server config.
     */
    val bidders: List<String>,
    /** S2S auction timeout in ms. Default: 1500. */
    val timeout: Int = 1500,
    /** Optional Prebid Server /cookie_sync endpoint. */
    val syncEndpoint: String? = null,
)

enum class AdSize(val width: Int, val height: Int) {
    BANNER_320x50(320, 50),
    MREC_300x250(300, 250),
    LEADERBOARD_728x90(728, 90),
    HALF_PAGE_300x600(300, 600),
    WIDE_SKYSCRAPER_160x600(160, 600);

    val label: String get() = "${width}x${height}"
}
