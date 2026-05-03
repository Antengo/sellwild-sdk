// SellwildPrebidMobile.kt — Prebid Mobile SDK bridge (required, not optional).
//
// In 1.3.0+, Prebid Mobile (3.x) and the Google Mobile Ads SDK (24.x) are
// REQUIRED dependencies of SellwildSDK. SellwildAdView runs a native Prebid
// auction and renders into an `AdManagerAdView` — there is no WebView in the
// banner ad path.
//
// This file is the single point of contact between the SDK and Prebid Mobile.
// It reads its parameters off `SellwildConfig.prebidServer` /
// `config.remoteJson["S2S_CONFIG"]` so partners do not have to wire Prebid
// by hand.

package com.sellwild.sdk

import android.content.Context
import android.util.Log
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.admanager.AdManagerAdRequest
import com.google.android.gms.ads.admanager.AdManagerAdView
import org.json.JSONObject
import org.prebid.mobile.BannerAdUnit
import org.prebid.mobile.BannerParameters
import org.prebid.mobile.OnCompleteListener
import org.prebid.mobile.PrebidMobile
import org.prebid.mobile.ResultCode
import org.prebid.mobile.Signals
import org.prebid.mobile.TargetingParams

/**
 * Bootstrap + auction bridge for Prebid Mobile + GMA.
 *
 * Public surface:
 *  - [bootstrap] is idempotent. Safe to call from every `SellwildSDK.configure`
 *    result and from every `SellwildAdView.load()`. Only the first call
 *    actually initializes the underlying SDKs.
 *  - [runBannerAuction] runs a Prebid auction for an [AdManagerAdView] and
 *    triggers `loadAd()` after the auction completes. GAM still serves on
 *    no-bid, so ad fill is always attempted.
 */
object SellwildPrebidMobile {

    private const val TAG = "SellwildPrebidMobile"
    private const val DEFAULT_PREBID_ENDPOINT = "https://prebid.sellwild.com/openrtb2/auction"

    private val lock = Any()
    @Volatile private var didBootstrap = false
    // Whether PrebidMobile.initializeSdk reached SUCCEEDED. If not, callers
    // should skip the auction and load GAM directly so ads still serve when
    // Prebid Server is unreachable.
    @Volatile private var prebidReady = false

    /** True once Prebid Mobile has reported a successful init. */
    @JvmStatic
    fun isReady(): Boolean = prebidReady

    /**
     * Initialize Prebid Mobile + GMA from a [SellwildConfig]. Idempotent —
     * subsequent calls are no-ops.
     *
     * Resolution order for the Prebid Server URL + account id:
     *   1. Typed [SellwildConfig.prebidServer] (set by SDK code or a partner override).
     *   2. Raw CDN passthrough at `config.remoteJson["S2S_CONFIG"]`.
     *   3. Sellwild's hosted Prebid Server (so the SDK does *something* on
     *      partial CMS configuration).
     */
    @JvmStatic
    fun bootstrap(context: Context, config: SellwildConfig): Boolean {
        synchronized(lock) {
            if (didBootstrap) return true

            // GMA first — Prebid hands off to GAM, GAM must be live before any
            // ad request runs. start() is idempotent on the GMA side too.
            try {
                MobileAds.initialize(context.applicationContext) { /* no-op */ }
            } catch (e: Throwable) {
                Log.w(TAG, "MobileAds.initialize threw: ${e.message}")
            }

            val resolved = resolvePrebidServer(config)

            PrebidMobile.setPrebidServerAccountId(resolved.accountId)
            PrebidMobile.setTimeoutMillis(config.prebidServer?.timeout ?: 1500)
            PrebidMobile.setShareGeoLocation(true)
            if (config.debug) {
                PrebidMobile.setLogLevel(PrebidMobile.LogLevel.DEBUG)
            }

            // Populate ortb2.app so DSPs see in-app traffic, not web traffic.
            config.appBundleId?.let { TargetingParams.setBundleName(it) }
            config.appStoreUrl?.let { TargetingParams.setStoreUrl(it) }

            try {
                PrebidMobile.initializeSdk(context.applicationContext, resolved.url) { status ->
                    Log.d(TAG, "PrebidMobile.initializeSdk status: $status")
                    // Status enum values are SUCCEEDED / FAILED in Prebid 3.x.
                    prebidReady = status.toString().equals("SUCCEEDED", ignoreCase = true)
                }
            } catch (e: Throwable) {
                Log.e(TAG, "PrebidMobile.initializeSdk threw", e)
            }

            didBootstrap = true
            return true
        }
    }

    /**
     * Run a Prebid auction for an already-constructed [AdManagerAdView] and
     * trigger `loadAd()` once the auction completes. GAM serves on no-bid.
     *
     * @param adView         A configured [AdManagerAdView] (ad unit id, ad
     *                       sizes, ad listener already set by the caller).
     * @param configId       Prebid Server stored impression id.
     * @param widthDp        Banner width in dp.
     * @param heightDp       Banner height in dp.
     * @param bidderParams   Optional CDN bidder params (raw CONSTANT_CASE
     *                       passthrough). Forwarded to Prebid Server as
     *                       `imp.ext.prebid.bidder` JSON.
     * @param completion     Called with the Prebid [ResultCode] after the
     *                       auction completes (and after `loadAd()` is fired).
     */
    @JvmStatic
    @JvmOverloads
    fun runBannerAuction(
        adView: AdManagerAdView,
        configId: String,
        widthDp: Int,
        heightDp: Int,
        bidderParams: Map<String, Any?> = emptyMap(),
        completion: ((ResultCode) -> Unit)? = null,
    ) {
        val unit = BannerAdUnit(configId, widthDp, heightDp)
        unit.bannerParameters = BannerParameters().apply {
            api = listOf(Signals.Api.MRAID_3, Signals.Api.OMID_1)
        }

        ortbExtJson(bidderParams)?.let { unit.setImpOrtbConfig(it) }

        val request = AdManagerAdRequest.Builder().build()
        unit.fetchDemand(request, OnCompleteListener { result ->
            // Whether or not Prebid won, always trigger GAM load so GAM's own
            // demand can fill on no-bid.
            adView.loadAd(request)
            completion?.invoke(result)
        })
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    internal data class PrebidServerResolution(val url: String, val accountId: String)

    internal fun resolvePrebidServer(config: SellwildConfig): PrebidServerResolution {
        // 1. Typed config.
        config.prebidServer?.let {
            return PrebidServerResolution(url = it.endpoint, accountId = it.accountId)
        }

        // 2. Raw CDN passthrough.
        val raw = config.remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() }
        val s2s = raw?.optJSONObject("S2S_CONFIG")
        if (s2s != null) {
            val url = s2s.optString("endpoint", "")
                .ifEmpty { s2s.optString("url", "") }
                .ifEmpty { DEFAULT_PREBID_ENDPOINT }
            val account = s2s.optString("accountId", "")
                .ifEmpty { s2s.optString("account", "") }
                .ifEmpty { config.partnerCode }
            return PrebidServerResolution(url = url, accountId = account)
        }

        // 3. Sellwild-hosted default.
        return PrebidServerResolution(
            url = DEFAULT_PREBID_ENDPOINT,
            accountId = config.partnerCode,
        )
    }

    /**
     * Wrap CDN bidder params as `imp.ext.prebid.bidder` JSON. Bidder names are
     * lowercased — CDN ships CONSTANT_CASE, Prebid expects lowercase.
     */
    internal fun ortbExtJson(params: Map<String, Any?>): String? {
        if (params.isEmpty()) return null
        val bidders = JSONObject()
        for ((k, v) in params) {
            if (v == null) continue
            bidders.put(k.lowercase(), v)
        }
        if (bidders.length() == 0) return null
        val ext = JSONObject().apply {
            put("ext", JSONObject().apply {
                put("prebid", JSONObject().apply {
                    put("bidder", bidders)
                })
            })
        }
        return ext.toString()
    }

    // Test-only seam to reset the bootstrap latch.
    internal fun resetForTesting() {
        synchronized(lock) { didBootstrap = false }
    }
}
