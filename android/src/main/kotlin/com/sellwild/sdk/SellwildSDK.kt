package com.sellwild.sdk

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * First-class entry point for configuring the Sellwild SDK.
 *
 * In 1.2.0+, partners can integrate the SDK with just a `partnerCode` and
 * `slug`. Everything else — listings URL, ad zones, app identity, refresh
 * intervals, waterfall partners, compliance flags — is fetched from the
 * Sellwild CDN at app launch.
 *
 * ```kotlin
 * val config = SellwildSDK.configure(
 *     partnerCode = "weatherbug",
 *     slug = "weatherbug-main"
 * )
 * ```
 *
 * On any network failure, timeout, or 404 the call returns a
 * `SellwildConfig(partnerCode = ...)` with deterministic defaults (the
 * listings endpoint is derived from `partnerCode`), so ads still render.
 */
object SellwildSDK {

    /**
     * Build a [SellwildConfig] by fetching `partnerCode/slug.json` from the
     * Sellwild CDN and applying it onto SDK defaults.
     *
     * @param partnerCode The partner identifier provisioned by Sellwild.
     * @param slug The CMS slug for this app's config (e.g. `"weatherbug-main"`).
     * @param timeoutMs Network timeout in milliseconds. Default `5000`.
     * @param overrides Optional lambda to override fields after the remote
     *   config is applied. Use this for app-controlled values (e.g.
     *   `appBundleId = context.packageName`).
     */
    suspend fun configure(
        partnerCode: String,
        slug: String,
        timeoutMs: Int = 5000,
        overrides: ((SellwildConfig) -> SellwildConfig)? = null,
    ): SellwildConfig = withContext(Dispatchers.IO) {
        var config = SellwildConfig(partnerCode = partnerCode)

        runCatching {
            val url = URL("https://widget.sellwild.com/app/$partnerCode/$slug.json")
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            if (connection.responseCode in 200..299) {
                val body = connection.inputStream.bufferedReader().readText()
                // Stash the raw payload so unmapped CDN keys (new bidders,
                // forward-compatible settings) flow through to the WebView
                // attribute serializer without an SDK release.
                config = apply(JSONObject(body), config).copy(remoteJson = body)
            }
        }
        // Silent fallback — config retains defaults on any failure.

        overrides?.let { config = it(config) }
        config
    }

    /**
     * Maps CONSTANT_CASE CDN keys onto the corresponding [SellwildConfig]
     * fields. Public so the React Native bridge (separate Gradle module)
     * can rebuild a feed-ready config from the JS-resolved `remote` JSON
     * without re-fetching the CDN payload.
     */
    fun apply(raw: JSONObject, base: SellwildConfig): SellwildConfig {
        return base.copy(
            // Identity
            partnerCode = raw.optStringOrNull("CODE") ?: base.partnerCode,
            slug = raw.optStringOrNull("SLUG") ?: base.slug,
            name = raw.optStringOrNull("NAME") ?: base.name,
            listingsUrl = raw.optStringOrNull("LISTINGS") ?: base.listingsUrl,

            // Display
            title = raw.optStringOrNull("TITLE") ?: base.title,
            partnerUrl = raw.optStringOrNull("PARTNER_URL") ?: base.partnerUrl,
            col1 = raw.optStringOrNull("COL1") ?: base.col1,
            bhTag = raw.optStringOrNull("BH_TAG") ?: base.bhTag,
            linkText = raw.optStringOrNull("LINK_TEXT") ?: base.linkText,
            buyNowText = raw.optStringOrNull("BUY_NOW_TEXT") ?: base.buyNowText,
            titleColor = raw.optStringOrNull("TITLE_COLOR") ?: base.titleColor,
            linkColor = raw.optStringOrNull("LINK_COLOR") ?: base.linkColor,
            fontColor = raw.optStringOrNull("FONT_COLOR") ?: base.fontColor,
            priceColor = raw.optStringOrNull("PRICE_COLOR") ?: base.priceColor,
            priceFontColor = raw.optStringOrNull("PRICE_FONT_COLOR") ?: base.priceFontColor,
            marginBottom = raw.optIntOrNull("MARGIN_BOTTOM") ?: base.marginBottom,
            colors = raw.optStringListOrNull("COLORS") ?: base.colors,
            overlayTitle = raw.optBooleanOrNull("OVERLAY_TITLE") ?: base.overlayTitle,
            watermark = raw.optBooleanOrNull("WATERMARK") ?: base.watermark,
            watermarkTitle = raw.optStringOrNull("WATERMARK_TITLE") ?: base.watermarkTitle,

            // Ad zones
            bannerZid = raw.optStringOrNull("BANNER_ZID") ?: base.bannerZid,
            bottomBannerZid = raw.optStringOrNull("BOTTOM_BANNER_ZID") ?: base.bottomBannerZid,
            // Per-platform placement resolution (this mapper only ever runs on
            // Android — the Kotlin SDK — so RN / Flutter hosts on Android resolve
            // here too). Three tiers, most specific first, per placement:
            //   1. per-placement per-platform (MOBILE_ZID_ANDROID / MOBILE_BANNER_ZID_ANDROID)
            //   2. platform-wide "ALL" (MOBILE_ZID_ALL_ANDROID — one value every
            //      mobile placement on this OS falls back to)
            //   3. shared base (MOBILE_ZID / MOBILE_BANNER_ZID)
            // Backward compatible: no suffixed key = today's behavior unchanged.
            mobileBannerZid = raw.optStringNonEmptyOrNull("MOBILE_BANNER_ZID_ANDROID")
                ?: raw.optStringNonEmptyOrNull("MOBILE_ZID_ALL_ANDROID")
                ?: raw.optStringOrNull("MOBILE_BANNER_ZID") ?: base.mobileBannerZid,
            mobileZids = raw.optStringListNonEmptyOrNull("MOBILE_ZID_ANDROID")
                ?: raw.optStringNonEmptyOrNull("MOBILE_ZID_ALL_ANDROID")?.let { listOf(it) }
                ?: raw.optStringListOrNull("MOBILE_ZID") ?: base.mobileZids,
            hideBannerTop = raw.optBooleanOrNull("HIDE_BANNER_TOP") ?: base.hideBannerTop,
            hideBannerBottom = raw.optBooleanOrNull("HIDE_BANNER_BOTTOM") ?: base.hideBannerBottom,
            gamTag = raw.optStringOrNull("GAM") ?: base.gamTag,
            disableGpt = raw.optBooleanOrNull("DISABLE_GPT") ?: base.disableGpt,
            adDisableDisplay = raw.optBooleanOrNull("AD_DISABLE_DISPLAY") ?: base.adDisableDisplay,

            // Refresh
            adRefreshMax = raw.optIntOrNull("AD_REFRESH_MAX") ?: base.adRefreshMax,
            adRefreshMaxMobile = raw.optIntOrNull("AD_REFRESH_MAX_MOBILE") ?: base.adRefreshMaxMobile,
            adRefreshIntervalMs = raw.optDoubleOrNull("AD_REFRESH_INTERVAL")
                ?.let { (it * 1000).toLong() } ?: base.adRefreshIntervalMs,
            maxFailedAuctions = raw.optIntOrNull("MAX_FAILED_AUCTIONS") ?: base.maxFailedAuctions,

            // Compliance
            gppEnabled = raw.optBooleanOrNull("GPP_ENABLED") ?: base.gppEnabled,
            tcfVersion = raw.optIntOrNull("TCF_VERSION") ?: base.tcfVersion,
            iabCats = raw.optStringListOrNull("IAB_CATS") ?: base.iabCats,

            // Mobile ad controls
            enableInterstitial = raw.optBooleanOrNull("ENABLE_INTERSTITIAL")
                ?: base.enableInterstitial,
            enableFullscreenVideo = raw.optBooleanOrNull("ENABLE_FULLSCREEN_VIDEO")
                ?: base.enableFullscreenVideo,
            interstitialsPerSession = raw.optIntOrNull("INTERSTITIALS_PER_SESSION")
                ?: base.interstitialsPerSession,
            videoTakeoversPerSession = raw.optIntOrNull("VIDEO_TAKEOVERS_PER_SESSION")
                ?: base.videoTakeoversPerSession,

            // App identity
            appBundleId = raw.optStringOrNull("APP_BUNDLE_ID") ?: base.appBundleId,
            appStoreUrl = raw.optStringOrNull("APP_STORE_URL") ?: base.appStoreUrl,

            // Third-party
            boltive = raw.optBooleanOrNull("BOLTIVE") ?: base.boltive,
            boltiveClientId = raw.optStringOrNull("BOLTIVE_CLIENT_ID") ?: base.boltiveClientId,
            lotame = raw.optBooleanOrNull("LOTAME") ?: base.lotame,

            // Debug
            debug = raw.optBooleanOrNull("DEBUG") ?: base.debug,
            pbsDebug = raw.optBooleanOrNull("PBS_DEBUG") ?: base.pbsDebug,
        )
    }
}

private fun JSONObject.optStringOrNull(key: String): String? =
    if (has(key) && !isNull(key)) optString(key) else null

private fun JSONObject.optIntOrNull(key: String): Int? =
    if (has(key) && !isNull(key)) optInt(key) else null

private fun JSONObject.optDoubleOrNull(key: String): Double? =
    if (has(key) && !isNull(key)) optDouble(key) else null

private fun JSONObject.optBooleanOrNull(key: String): Boolean? =
    if (has(key) && !isNull(key)) optBoolean(key) else null

private fun JSONObject.optStringListOrNull(key: String): List<String>? {
    if (!has(key) || isNull(key)) return null
    val arr = optJSONArray(key) ?: return null
    return List(arr.length()) { i -> arr.optString(i) }
}

/** Like [optStringOrNull] but also treats an empty string as absent. */
private fun JSONObject.optStringNonEmptyOrNull(key: String): String? =
    optStringOrNull(key)?.ifEmpty { null }

/** Like [optStringListOrNull] but also treats an empty list as absent. */
private fun JSONObject.optStringListNonEmptyOrNull(key: String): List<String>? =
    optStringListOrNull(key)?.ifEmpty { null }
