package com.sellwild.sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.widget.FrameLayout
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdSize as GmaAdSize
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.admanager.AdManagerAdRequest
import com.google.android.gms.ads.admanager.AdManagerAdView
import org.json.JSONObject

/**
 * Native banner ad view. As of 1.3.0 this view runs a Prebid Mobile auction
 * and renders into an [AdManagerAdView]. There is **no WebView** in the ad
 * path.
 *
 * The widget surface ([SellwildWidgetView]) still uses a WebView for
 * marketplace listings — that surface is intentionally a WebView. Banners and
 * other monetizing ad units render natively.
 *
 * Usage:
 * ```kotlin
 * val config = SellwildSDK.configure(context, "weatherbug", "weatherbug-weatherbug")
 * val ad = SellwildAdView(context).apply {
 *     setup(config, AdSize.BANNER_320x50, zoneId = "43")
 * }
 * parent.addView(ad)
 * ad.load()
 * ```
 */
class SellwildAdView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    interface Listener {
        fun onAdLoaded(adView: SellwildAdView) {}
        fun onAdImpression(adView: SellwildAdView, zoneId: String) {}
        fun onAdClicked(adView: SellwildAdView) {}
        fun onAdFailed(adView: SellwildAdView, message: String) {}
    }

    var listener: Listener? = null

    private lateinit var config: SellwildConfig
    private lateinit var adSize: AdSize
    private var zoneId: String? = null

    private var bannerView: AdManagerAdView? = null
    private var refreshHandler: Handler? = null
    private var refreshCount = 0

    fun setup(config: SellwildConfig, adSize: AdSize, zoneId: String? = null) {
        this.config = config
        this.adSize = adSize
        this.zoneId = zoneId

        if (bannerView == null) {
            val banner = AdManagerAdView(context).apply {
                setAdSizes(GmaAdSize(adSize.width, adSize.height))
                adUnitId = resolveGAMAdUnitID()
                adListener = bannerAdListener()
            }
            bannerView = banner

            val dp = context.resources.displayMetrics.density
            val widthPx = (adSize.width * dp).toInt()
            val heightPx = (adSize.height * dp).toInt()
            addView(banner, LayoutParams(widthPx, heightPx))
        }
    }

    /**
     * Run the Prebid auction and load the winning ad. Safe to call multiple
     * times; each call triggers a fresh auction + GAM request.
     */
    fun load() {
        val banner = bannerView ?: run {
            listener?.onAdFailed(this, "SellwildAdView.load() called before setup()")
            return
        }

        // Idempotent — first call wins, the rest are cheap.
        SellwildPrebidMobile.bootstrap(context, config)

        // Re-resolve in case `config` was swapped between loads.
        banner.adUnitId = resolveGAMAdUnitID()

        val configId = zoneId
        if (configId.isNullOrEmpty()) {
            // No zoneId means we can't run a Prebid auction. Fall through to a
            // plain GAM request so GAM line items still serve.
            banner.loadAd(AdManagerAdRequest.Builder().build())
            return
        }

        SellwildPrebidMobile.runBannerAuction(
            adView = banner,
            configId = configId,
            widthDp = adSize.width,
            heightDp = adSize.height,
            bidderParams = bidderParamsFromRemote(config),
        )
    }

    fun pause() {
        refreshHandler?.removeCallbacksAndMessages(null)
        refreshHandler = null
        bannerView?.pause()
    }

    fun resume() {
        bannerView?.resume()
    }

    fun destroy() {
        pause()
        bannerView?.destroy()
        bannerView = null
    }

    // ── Internals ──────────────────────────────────────────────────────────

    private fun bannerAdListener() = object : AdListener() {
        override fun onAdLoaded() {
            val self = this@SellwildAdView
            self.listener?.onAdLoaded(self)
            self.listener?.onAdImpression(self, self.zoneId.orEmpty())
            scheduleRefresh()
        }

        override fun onAdFailedToLoad(error: LoadAdError) {
            val self = this@SellwildAdView
            self.listener?.onAdFailed(self, error.message)
            scheduleRefresh()
        }

        override fun onAdClicked() {
            val self = this@SellwildAdView
            self.listener?.onAdClicked(self)
        }
    }

    private fun scheduleRefresh() {
        val maxRefresh = if (config.adRefreshMaxMobile > 0) config.adRefreshMaxMobile else config.adRefreshMax
        if (maxRefresh <= 0 || refreshCount >= maxRefresh) return

        val handler = Handler(Looper.getMainLooper())
        refreshHandler = handler
        handler.postDelayed({
            refreshCount++
            load()
        }, config.adRefreshIntervalMs)
    }

    /**
     * Resolve the GAM ad unit ID. Order of preference:
     *   1. `config.gamTag` (the real GAM ad unit path provisioned by the CMS).
     *   2. `config.remoteJson["GAM"]` raw passthrough, if set.
     *   3. GMA test ad unit (`/6499/example/banner`) — partners notice their
     *      CMS is missing a `GAM` field in production.
     */
    private fun resolveGAMAdUnitID(): String = resolveGAMAdUnitID(config)

    companion object {
        private const val TAG = "SellwildAdView"

        internal const val GAM_TEST_AD_UNIT = "/6499/example/banner"

        /**
         * Resolve the GAM ad unit ID. Order of preference:
         *   1. `config.gamTag` (the real GAM ad unit path provisioned by the CMS).
         *   2. `config.remoteJson["GAM"]` raw passthrough, if set.
         *   3. GMA test ad unit (`/6499/example/banner`) — partners notice their
         *      CMS is missing a `GAM` field in production.
         */
        internal fun resolveGAMAdUnitID(config: SellwildConfig): String {
            config.gamTag?.takeIf { it.isNotEmpty() }?.let { return it }

            config.remoteJson?.let { raw ->
                runCatching {
                    val obj = JSONObject(raw)
                    val gam = obj.optString("GAM", "")
                    if (gam.isNotEmpty()) return gam
                }
            }

            if (config.debug) {
                android.util.Log.w(
                    TAG,
                    "No GAM ad unit configured. Falling back to Google's test ad " +
                        "unit `/6499/example/banner`. Set `GAM` in your CMS config " +
                        "to enable production fill.",
                )
            }
            return GAM_TEST_AD_UNIT
        }

        /**
         * Forward bidder configs from the raw CDN payload as ext data on the
         * Prebid auction. Each new bidder added to the CMS becomes available
         * to every consuming app immediately, no SDK release.
         */
        internal fun bidderParamsFromRemote(config: SellwildConfig): Map<String, Any?> {
            val raw = config.remoteJson ?: return emptyMap()
            val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()

            val params = mutableMapOf<String, Any?>()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                // CDN ships bidder params as CONSTANT_CASE; non-bidder typed
                // keys are skipped via the static deny list.
                if (key != key.uppercase()) continue
                if (NON_BIDDER_REMOTE_KEYS.contains(key)) continue
                params[key] = obj.opt(key)
            }
            return params
        }

        /** CDN keys that are first-class typed config and not bidder params. */
        private val NON_BIDDER_REMOTE_KEYS: Set<String> = setOf(
            "CODE", "LISTINGS", "SLUG", "NAME", "TITLE", "COLORS", "LINK_TEXT",
            "BUY_NOW_TEXT", "FONT_FAMILY", "FONT_URL", "FONT_COLOR", "PRICE_COLOR",
            "PRICE_FONT_COLOR", "MARGIN_BOTTOM", "CARD_WIDTH", "OVERLAY_TITLE",
            "CSS", "WATERMARK", "WATERMARK_TITLE", "BANNER_ZID", "BOTTOM_BANNER_ZID",
            "MOBILE_BANNER_ZID", "MOBILE_ZID", "DISPLAY_ZID", "HIDE_BANNER_TOP",
            "HIDE_BANNER_BOTTOM", "GAM", "DISABLE_GPT", "AD_UNITS", "SAFE_FRAME",
            "AD_DISABLE_DISPLAY", "AD_REFRESH_MAX", "AD_REFRESH_MAX_MOBILE",
            "AD_REFRESH_INTERVAL", "MAX_FAILED_AUCTIONS", "PREBID_DEFER",
            "PREBID_SRC", "AD_GEO_BLOCK", "AD_GEO_BLOCK_REFRESH", "GPP_ENABLED",
            "TCF_VERSION", "CONSENT_MANAGEMENT", "SCHAIN_SID", "S2S_CONFIG",
            "IAB_CATS", "APP_BUNDLE_ID", "APP_STORE_URL", "ENABLE_INTERSTITIAL",
            "ENABLE_FULLSCREEN_VIDEO", "INTERSTITIALS_PER_SESSION",
            "VIDEO_TAKEOVERS_PER_SESSION", "DEBUG", "MEMBERSHIP_TYPE",
        )
    }
}
