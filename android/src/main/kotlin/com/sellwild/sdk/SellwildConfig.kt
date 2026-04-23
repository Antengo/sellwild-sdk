package com.sellwild.sdk

import org.json.JSONObject

/**
 * Main configuration for the Sellwild ad SDK.
 * Mirrors the web widget's ICustomizations, adapted for Android.
 */
data class SellwildConfig(
    // Identity
    val partnerCode: String,
    val listingsUrl: String,
    val slug: String = "",
    val name: String = "",
    val apiBaseUrl: String = "https://api.sellwild.com",

    // Display
    val title: String? = null,
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

    // Ad Networks
    val ix: IxConfig? = null,
    val openx: OpenxConfig? = null,
    val pubmatic: PubmaticConfig? = null,
    val appnexus: AppnexusConfig? = null,

    // Waterfall Partners
    val pubVentures: WaterfallPartnerConfig? = null,
    val saambaa: WaterfallPartnerConfig? = null,
    val opsco: WaterfallPartnerConfig? = null,
    val bidstream: WaterfallPartnerConfig? = null,

    // Third-party
    val boltive: Boolean = false,
    val boltiveClientId: String = "",
    val lotame: Boolean = false,

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
    fun toJson(): JSONObject = JSONObject().apply {
        put("partnerCode", partnerCode)
        put("listingsUrl", listingsUrl)
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
