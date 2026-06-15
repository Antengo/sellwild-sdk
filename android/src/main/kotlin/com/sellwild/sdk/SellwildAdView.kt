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
import org.prebid.mobile.AdSize as PrebidAdSize
import org.prebid.mobile.api.exceptions.AdException
import org.prebid.mobile.api.rendering.BannerView as PrebidBannerView
import org.prebid.mobile.api.rendering.listeners.BannerViewListener

/**
 * Native banner ad view. As of 1.3.0 this view runs a Prebid Mobile auction
 * and renders into an [AdManagerAdView]. There is **no WebView** in the ad
 * path.
 *
 * As of 1.4.0 the view can be segmented by ad stack (see [SellwildAdStack]),
 * toggled remotely via `AD_STACK` / `AD_STACK_BY_ZONE`:
 *   - [SellwildAdStack.BOTH]        Prebid auction → GAM renders (default).
 *   - [SellwildAdStack.GAM_ONLY]    Plain GAM request, no Prebid auction.
 *   - [SellwildAdStack.PREBID_ONLY] Prebid's own rendering [PrebidBannerView],
 *                                   NO GAM request (and so no GAM request fees).
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

    /**
     * Optional code-level ad-stack override. When set, wins over the remote
     * `AD_STACK` / `AD_STACK_BY_ZONE` config — intended for QA / testing.
     */
    var adStackOverride: SellwildAdStack? = null

    private lateinit var config: SellwildConfig
    private lateinit var adSize: AdSize
    private var zoneId: String? = null

    private var bannerView: AdManagerAdView? = null
    private var prebidBanner: PrebidBannerView? = null
    private var refreshHandler: Handler? = null
    private var refreshCount = 0

    /** The ad stack this view resolves to, given the current config + override. */
    val resolvedAdStack: SellwildAdStack
        get() = SellwildAdStack.resolve(config.remoteJson, zoneId, adStackOverride)

    fun setup(config: SellwildConfig, adSize: AdSize, zoneId: String? = null) {
        this.config = config
        this.adSize = adSize
        this.zoneId = zoneId

        when (resolvedAdStack) {
            SellwildAdStack.PREBID_ONLY -> ensurePrebidBanner()
            SellwildAdStack.BOTH, SellwildAdStack.GAM_ONLY -> ensureGamBanner()
        }
    }

    /**
     * Run the ad path for the resolved stack and load an ad. Safe to call
     * multiple times; each call triggers a fresh load.
     */
    fun load() {
        // Idempotent — first call wins, the rest are cheap.
        SellwildPrebidMobile.bootstrap(context, config)

        when (resolvedAdStack) {
            SellwildAdStack.PREBID_ONLY -> loadPrebidOnly()
            SellwildAdStack.GAM_ONLY -> loadGam(runAuction = false)
            SellwildAdStack.BOTH -> loadGam(runAuction = true)
        }
    }

    fun pause() {
        refreshHandler?.removeCallbacksAndMessages(null)
        refreshHandler = null
        bannerView?.pause()
        prebidBanner?.stopRefresh()
    }

    fun resume() {
        bannerView?.resume()
    }

    fun destroy() {
        pause()
        bannerView?.destroy()
        bannerView = null
        prebidBanner?.destroy()
        prebidBanner = null
    }

    // ── GAM path (.both / .gamOnly) ──────────────────────────────────────────

    private fun ensureGamBanner(): AdManagerAdView {
        // Tear down a Prebid-only banner if we previously rendered one.
        prebidBanner?.let {
            it.destroy()
            removeView(it)
            prebidBanner = null
        }
        bannerView?.let { return it }

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
        return banner
    }

    private fun loadGam(runAuction: Boolean) {
        val banner = ensureGamBanner()

        // GMA forbids reassigning adUnitId on an existing AdManagerAdView.
        // setup() already set it from the initial config; if the resolved unit
        // changes (e.g. config swap between loads), the caller needs a fresh
        // SellwildAdView. We just leave the unit alone here.

        val configId = zoneId
        if (!runAuction || configId.isNullOrEmpty() || !SellwildPrebidMobile.isReady()) {
            // No auction (.gamOnly), no zoneId to bid against, or Prebid Mobile
            // hasn't initialized yet. In every case, fall through to a plain
            // GAM request so GAM line items still serve.
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

    // ── Prebid-only path (.prebidOnly) ───────────────────────────────────────

    private fun ensurePrebidBanner(): PrebidBannerView? {
        val configId = zoneId
        if (configId.isNullOrEmpty()) {
            // Prebid rendering needs a configId. We deliberately do NOT build a
            // GAM banner here — that would incur the GAM request fees that
            // .prebidOnly exists to avoid.
            return null
        }

        // Tear down a GAM banner if we previously rendered one.
        bannerView?.let {
            it.destroy()
            removeView(it)
            bannerView = null
        }
        prebidBanner?.let { return it }

        // BannerView(context, configId, adSize) uses Prebid's standalone
        // rendering — it makes a Prebid Server bid request and renders the
        // winning creative itself, with no ad-server (GAM) call.
        val prebid = PrebidBannerView(
            context,
            configId,
            PrebidAdSize(adSize.width, adSize.height),
        ).apply {
            setBannerListener(prebidBannerListener())
            // Prebid's rendering banner owns its own auto-refresh.
            if (config.adRefreshMaxMobile > 0) {
                setAutoRefreshDelay((config.adRefreshIntervalMs / 1000L).toInt())
            }
        }
        prebidBanner = prebid

        val dp = context.resources.displayMetrics.density
        val widthPx = (adSize.width * dp).toInt()
        val heightPx = (adSize.height * dp).toInt()
        addView(prebid, LayoutParams(widthPx, heightPx))
        return prebid
    }

    private fun loadPrebidOnly() {
        val prebid = ensurePrebidBanner()
        if (prebid == null) {
            listener?.onAdFailed(
                this,
                "SellwildAdView resolved to PREBID_ONLY but has no zoneId; " +
                    "Prebid rendering requires a configId.",
            )
            return
        }
        prebid.loadAd()
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

    private fun prebidBannerListener() = object : BannerViewListener {
        override fun onAdLoaded(bannerView: PrebidBannerView?) {
            val self = this@SellwildAdView
            self.listener?.onAdLoaded(self)
            self.listener?.onAdImpression(self, self.zoneId.orEmpty())
        }

        override fun onAdDisplayed(bannerView: PrebidBannerView?) {}

        override fun onAdFailed(bannerView: PrebidBannerView?, exception: AdException?) {
            val self = this@SellwildAdView
            self.listener?.onAdFailed(self, exception?.message ?: "Prebid ad failed")
        }

        override fun onAdClicked(bannerView: PrebidBannerView?) {
            val self = this@SellwildAdView
            self.listener?.onAdClicked(self)
        }

        override fun onAdClosed(bannerView: PrebidBannerView?) {}
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
     *   3. A size-appropriate Google test ad unit — partners notice their
     *      CMS is missing a `GAM` field in production.
     */
    private fun resolveGAMAdUnitID(): String = resolveGAMAdUnitID(config, adSize)

    companion object {
        private const val TAG = "SellwildAdView"

        // Google-provided test ad units. /6499/example/banner only fills 320x50;
        // mrec / leaderboard / etc. need their own test units or they no-fill.
        internal const val GAM_TEST_AD_UNIT_BANNER = "/6499/example/banner"
        internal const val GAM_TEST_AD_UNIT_ADAPTIVE = "/21775744923/example/adaptive-banner"

        /**
         * Resolve the GAM ad unit ID. Order of preference:
         *   1. `config.gamTag` (the real GAM ad unit path provisioned by the CMS).
         *   2. `config.remoteJson["GAM"]` raw passthrough, if set.
         *   3. A size-appropriate Google test ad unit (320x50 → banner test
         *      unit, everything else → adaptive-banner test unit which fills
         *      MREC / leaderboard / large sizes).
         */
        internal fun resolveGAMAdUnitID(config: SellwildConfig, adSize: AdSize? = null): String {
            config.gamTag?.takeIf { it.isNotEmpty() }?.let { return it }

            config.remoteJson?.let { raw ->
                runCatching {
                    val obj = JSONObject(raw)
                    val gam = obj.optString("GAM", "")
                    if (gam.isNotEmpty()) return gam
                }
            }

            val testUnit = if (adSize != null && adSize.width == 320 && adSize.height == 50) {
                GAM_TEST_AD_UNIT_BANNER
            } else {
                GAM_TEST_AD_UNIT_ADAPTIVE
            }

            if (config.debug) {
                android.util.Log.w(
                    TAG,
                    "No GAM ad unit configured. Falling back to Google's test ad " +
                        "unit `$testUnit`. Set `GAM` in your CMS config " +
                        "to enable production fill.",
                )
            }
            return testUnit
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
            "AD_DISABLE_DISPLAY", "AD_STACK", "AD_STACK_BY_ZONE", "AD_REFRESH_MAX",
            "AD_REFRESH_MAX_MOBILE", "AD_REFRESH_INTERVAL", "MAX_FAILED_AUCTIONS",
            "PREBID_DEFER", "PREBID_SRC", "AD_GEO_BLOCK", "AD_GEO_BLOCK_REFRESH",
            "GPP_ENABLED", "TCF_VERSION", "CONSENT_MANAGEMENT", "SCHAIN_SID",
            "S2S_CONFIG", "IAB_CATS", "APP_BUNDLE_ID", "APP_STORE_URL",
            "ENABLE_INTERSTITIAL", "ENABLE_FULLSCREEN_VIDEO",
            "INTERSTITIALS_PER_SESSION", "VIDEO_TAKEOVERS_PER_SESSION", "DEBUG",
            "MEMBERSHIP_TYPE",
        )
    }
}
