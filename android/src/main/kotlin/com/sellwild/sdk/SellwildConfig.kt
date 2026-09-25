package com.sellwild.sdk

import com.sellwild.sdk.core.Issue
import com.sellwild.sdk.core.RemoteValues
import com.sellwild.sdk.core.Resolved
import com.sellwild.sdk.failures.SellwildFailures
import org.json.JSONObject

/**
 * Main configuration for the Sellwild ad SDK.
 * Mirrors the web widget's ICustomizations, adapted for Android.
 */
data class SellwildConfig(
    // Identity
    val partnerCode: String,
    /**
     * URL of the listings data. Optional in 1.2.0+ — typically populated from
     * remote config. When null, [effectiveListingsUrl] falls back to the
     * general listings cache, [DEFAULT_LISTINGS_URL].
     */
    val listingsUrl: String? = null,
    val slug: String = "",
    val name: String = "",

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
    /**
     * Bargain Hunter affiliate tag. When set, listing tap URLs that already
     * carry a `listing.url` get a `?tag={bhTag}` query param appended, matching
     * the web widget's `getListingUrl()` behavior.
     */
    val bhTag: String? = null,
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

    // Geo — partner-supplied location (state, zip, city, lat/lon). Emitted as
    // OpenRTB device.geo on native Prebid auctions; its `state` keys per-state
    // listing caches. Set via the configure overrides, or update at runtime with
    // SellwildPrebidMobile.setGeo(...).
    val geo: SellwildGeo? = null,

    // Prebid Server S2S (optional)
    // Route all Prebid.js bidder calls through a Prebid Server instance instead of running
    // client-side adapters in the WebView. Solves cookie/IDFA limitations.
    // Leave null to use the default Prebid.js client-side mode.
    val prebidServer: PrebidServerConfig? = null,

    // GrowthCode Signal Resolve (identity) — local overrides for the GrowthCode
    // sync. Each set field wins over the corresponding remote `GROWTHCODE_*` key;
    // otherwise the remote value (or a default) applies. Leave null to drive
    // entirely from the CMS.
    val growthCode: SellwildGrowthCodeConfig? = null,

    // Localized (geo-based) secondary listings — local override for the remote
    // `LOCALIZED_LISTINGS` integration object. When set, it wins entirely over
    // the remote value; otherwise the remote value applies. Leave null to drive
    // entirely from the CMS.
    val localizedListings: SellwildLocalizedListingsConfig? = null,

    // Debug
    val debug: Boolean = false,
    /**
     * Server-side auction debug. When true, flips Prebid Mobile's pbsDebug,
     * adding `ext.prebid.debug=1` + `returnallbidstatus` so the PBS response
     * carries the full debug block. Heavier responses; leave off in production.
     * Independent of [debug] (log verbosity).
     */
    val pbsDebug: Boolean = false,
) {
    /**
     * Effective listings URL. Returns [listingsUrl] when set, otherwise falls
     * back to the general listings cache, [DEFAULT_LISTINGS_URL].
     */
    val effectiveListingsUrl: String
        get() = listingsUrl?.takeIf { it.isNotEmpty() }
            ?: DEFAULT_LISTINGS_URL

    fun toJson(): JSONObject = JSONObject().apply {
        put("partnerCode", partnerCode)
        put("listingsUrl", effectiveListingsUrl)
        put("slug", slug)
        put("name", name)
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

    companion object {
        /**
         * Fallback listings source used when [listingsUrl] is null or empty.
         * Points at the general (non-partner-specific) listings cache blob.
         */
        const val DEFAULT_LISTINGS_URL = "https://cache.sellwild.com/listings-img-data-sm"
    }
}

/**
 * Local, code-supplied GrowthCode settings. Each field, when set, takes
 * precedence over the corresponding remote `GROWTHCODE_*` key. Leave fields
 * null to drive them from the CMS.
 */
data class SellwildGrowthCodeConfig(
    /** Master on/off. When set, wins over remote `GROWTHCODE_ENABLED`. */
    val enabled: Boolean? = null,
    /** GrowthCode PartnerID — the `pid` query param. Required for the sync to run. */
    val partnerId: String? = null,
    /** Sync endpoint. Defaults to the GrowthCode hosted endpoint. */
    val endpoint: String? = null,
    /** Publisher domain sent as `u`/`h` (a native app has no page URL). */
    val syncUrl: String? = null,
    /** Send the device advertising id (GAID) when available. Default true. When
     *  false, the SDK skips the call entirely for devices with no usable id. */
    val sendMaid: Boolean? = null,
    /** Minimum hours between syncs. Default 48. */
    val ttlHours: Int? = null,
)

/**
 * Local, code-supplied localized-listings settings. When this object is set it
 * takes precedence over the remote `LOCALIZED_LISTINGS` object as a whole (not
 * field-by-field). `enabled == false` disables; an absent `enabled` on a present
 * object counts as on. Requires `baseUrl` + `urlTemplate` to activate.
 */
data class SellwildLocalizedListingsConfig(
    /** Master on/off. Absent (null) on a present object counts as on; `false` disables. */
    val enabled: Boolean? = null,
    /** Optional label for the source, e.g. "sportserver". */
    val source: String? = null,
    /** Cache base URL, e.g. "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/". */
    val baseUrl: String? = null,
    /** Filename template with a `{state}` token, e.g. "sports-img-data-sm-webp-{state}.json". */
    val urlTemplate: String? = null,
    /** Dispersion percent: 25 → every 4th feed slot is a localized listing. */
    val frequency: Int? = null,
    /** Force a state (2-letter), overriding geo resolution — e.g. a known-Alabama site. */
    val forceState: String? = null,
)

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

// ── Remote config shell ──────────────────────────────────────────────────────
// Pure readers in core/ return what they could not use as issues; these two lines
// are the impure half that reports them.

/** Reports every issue through logFailure, once each, and returns the value. */
internal fun <T> Resolved<T>.reported(): T {
    issues.report()
    return value
}

/** Reports each issue through logFailure. */
internal fun List<Issue>.report() = forEach {
    SellwildFailures.log(
        code = it.code,
        component = it.component,
        severity = it.severity,
        error = it.error,
        message = it.message,
        zoneId = it.zoneId,
    )
}

/**
 * The stored remote config ([SellwildConfig.remoteJson]) as an object for the resolvers
 * that read raw CDN keys; null without one. Text that does not parse is reported as
 * config.remote_values.parse once, not again on each read of the same text (see
 * [reportedUnparsedRemoteJson]), and the resolver falls back to its defaults.
 */
internal fun remoteObject(remoteJson: String?): JSONObject? {
    val parsed = RemoteValues.parse(remoteJson)
    if (parsed.issues.isNotEmpty() && reportedUnparsedRemoteJson != remoteJson) {
        reportedUnparsedRemoteJson = remoteJson
        parsed.issues.report()
    }
    return parsed.value
}

/**
 * The remote config text last reported as config.remote_values.parse. Every resolver reads
 * the stored config, several of them on each ad load, so the same bad text would otherwise be
 * reported on every read, not once (FAILURES.md 9). An app has one stored config, so the last
 * text is enough; a different bad text is reported again.
 */
@Volatile
private var reportedUnparsedRemoteJson: String? = null

/**
 * [reported], but each issue once per [source] text. The resolvers that read the stored
 * remote config (ad stack, banner sizes, localized listings) run on every ad or feed load,
 * several times each, and would otherwise report the same bad value on every read, not once
 * (FAILURES.md 9). An issue is the same when its code and message are, as in the gate's dedupe
 * key (FAILURES.md 5.6), which has no zone: the same bad value in a second zone is not
 * reported again. A different [source] text, such as a refreshed remote config, is new, and
 * its issues are reported again.
 */
internal fun <T> Resolved<T>.reportedOncePer(source: String?): T {
    ReportedIssues.fresh(source, issues).report()
    return value
}

/**
 * The issues [reportedOncePer] reported, per source text. Only the [MAX_SOURCES] texts used
 * last are kept: an app has one stored config, and a local localized-listings override is a
 * second source, so a few cover every config an app switches between.
 */
private object ReportedIssues {
    private const val MAX_SOURCES = 8

    private val bySource = object : LinkedHashMap<String?, MutableSet<String>>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String?, MutableSet<String>>) = size > MAX_SOURCES
    }

    /** The [issues] not yet reported from [source]; they count as reported from now on. */
    @Synchronized
    fun fresh(source: String?, issues: List<Issue>): List<Issue> {
        if (issues.isEmpty()) return issues
        val seen = bySource.getOrPut(source) { HashSet() }
        return issues.filter { seen.add("${it.code}|${it.message}") }
    }

    @Synchronized
    fun clear() = bySource.clear()
}

/** Forgets which remote config text and issues were reported. Tests only (FailuresRule). */
internal fun resetRemoteObjectReportsForTests() {
    reportedUnparsedRemoteJson = null
    ReportedIssues.clear()
}

/**
 * An app that builds its [SellwildConfig] by hand never calls configure(), which is what sets
 * the partner logFailure stamps on every failure (FAILURES.md 3.2). The first SDK entry that
 * gets such a config sets it, unless one is set already.
 */
internal fun SellwildConfig.claimFailurePartner() {
    if (partnerCode.isEmpty()) return
    SellwildFailures.setContext { if (it.partnerCode.isNullOrEmpty()) it.copy(partnerCode = partnerCode) else it }
}
