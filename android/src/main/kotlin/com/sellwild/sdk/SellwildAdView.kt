package com.sellwild.sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.widget.FrameLayout
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdSize as GmaAdSize
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.admanager.AdManagerAdRequest
import com.google.android.gms.ads.admanager.AdManagerAdView
import org.json.JSONObject
import com.sellwild.prebid.AdSize as PrebidAdSize
import com.sellwild.prebid.api.exceptions.AdException
import com.sellwild.prebid.api.rendering.BannerView as PrebidBannerView
import com.sellwild.prebid.api.rendering.listeners.BannerViewListener

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
        /**
         * The ad rendered at [width]x[height] (dp). Fires on every render so a
         * host can resize its slot to the actual creative — the winning
         * multi-size banner, an outstream video, or the capped native template.
         * Enables dynamic sizing where the slot isn't a fixed banner (React
         * Native especially).
         */
        fun onAdResize(adView: SellwildAdView, width: Int, height: Int) {}
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
    private var nativeAdView: SellwildNativeAdView? = null
    private var refreshHandler: Handler? = null
    private var refreshCount = 0

    // Cold-start guard: Prebid Mobile init is async and races the first load().
    // Wait up to ~1.2s (8 × 150ms) for init before falling back to GAM-only, so
    // the first impression isn't silently downgraded and loses Prebid demand.
    private var prebidWaitHandler: Handler? = null
    private var prebidWaitAttempts = 0
    private val maxPrebidWaitAttempts = 8
    private val prebidWaitIntervalMs = 150L

    /** The ad stack this view resolves to, given the current config + override. */
    val resolvedAdStack: SellwildAdStack
        get() = SellwildAdStack.resolve(config.remoteJson, zoneId, adStackOverride)

    /**
     * Native reuses the slot on PREBID_ONLY only: Prebid fetches demand and we
     * render the assets. On BOTH/GAM_ONLY a native creative would need GAM
     * native line items + a GADNativeAd renderer (ad-ops), so we fall through to
     * the banner path there.
     */
    private val nativeEnabled: Boolean
        get() = resolvedAdStack == SellwildAdStack.PREBID_ONLY &&
            SellwildNative.isEnabled(config.remoteJson, zoneId)

    /**
     * The banner size set for this placement — the [adSize] primary plus any
     * remote `BANNER_SIZES` / `BANNER_SIZES_BY_ZONE` fallbacks (primary first).
     */
    private val resolvedAdSizes: List<SellwildAdSizes.Size>
        get() = SellwildAdSizes.resolve(
            config.remoteJson,
            zoneId,
            SellwildAdSizes.Size(adSize.width, adSize.height),
        )

    fun setup(config: SellwildConfig, adSize: AdSize, zoneId: String? = null) {
        this.config = config
        this.adSize = adSize
        this.zoneId = zoneId

        when {
            nativeEnabled -> ensureNativeAdView()
            resolvedAdStack == SellwildAdStack.PREBID_ONLY -> ensurePrebidBanner()
            else -> ensureGamBanner()
        }
    }

    /**
     * Run the ad path for the resolved stack and load an ad. Safe to call
     * multiple times; each call triggers a fresh load.
     */
    fun load() {
        // Idempotent — first call wins, the rest are cheap.
        SellwildPrebidMobile.bootstrap(context, config)

        if (nativeEnabled) {
            loadPrebidNative()
            return
        }

        when (resolvedAdStack) {
            SellwildAdStack.PREBID_ONLY -> loadPrebidOnly()
            SellwildAdStack.GAM_ONLY -> loadGam(runAuction = false)
            SellwildAdStack.BOTH -> loadGam(runAuction = true)
        }
    }

    fun pause() {
        refreshHandler?.removeCallbacksAndMessages(null)
        refreshHandler = null
        prebidWaitHandler?.removeCallbacksAndMessages(null)
        prebidWaitHandler = null
        prebidWaitAttempts = 0
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
        nativeAdView?.destroy()
        nativeAdView = null
    }

    // ── GAM path (.both / .gamOnly) ──────────────────────────────────────────

    private fun ensureGamBanner(): AdManagerAdView {
        // Tear down a Prebid-only banner / native view if we previously
        // rendered one.
        prebidBanner?.let {
            it.destroy()
            removeView(it)
            prebidBanner = null
        }
        nativeAdView?.let { it.destroy(); removeView(it); nativeAdView = null }
        bannerView?.let { return it }

        // Capture lateinit property to satisfy Kotlin's null-safety in lambdas.
        val size = adSize
        val banner = AdManagerAdView(context).apply {
            // Multi-size: primary + any BANNER_SIZES fallbacks.
            SellwildAdSizes.applyGam(resolvedAdSizes, this)
            adUnitId = resolveGAMAdUnitID()
            adListener = bannerAdListener()
        }
        bannerView = banner

        val dp = context.resources.displayMetrics.density
        val widthPx = (size.width * dp).toInt()
        val heightPx = (size.height * dp).toInt()
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
        // Plain GAM: .gamOnly, or no zone to bid against — no auction, no waiting.
        if (!runAuction || configId.isNullOrEmpty()) {
            prebidWaitAttempts = 0
            banner.loadAd(AdManagerAdRequest.Builder().build())
            return
        }

        // .both with a zone to bid against, but Prebid Mobile's async init may
        // not have finished on a cold start (it races the first load()). Wait
        // briefly so the first impression isn't silently downgraded to GAM-only
        // and loses Prebid demand; fall back to plain GAM only if init is too
        // slow or has failed.
        if (!SellwildPrebidMobile.isReady()) {
            if (prebidWaitAttempts < maxPrebidWaitAttempts) {
                prebidWaitAttempts++
                val h = prebidWaitHandler
                    ?: Handler(Looper.getMainLooper()).also { prebidWaitHandler = it }
                h.postDelayed({ loadGam(runAuction) }, prebidWaitIntervalMs)
                return
            }
            // Init never came up in time — serve GAM so fill is still attempted.
            prebidWaitAttempts = 0
            banner.loadAd(AdManagerAdRequest.Builder().build())
            return
        }

        prebidWaitAttempts = 0
        val size = adSize
        SellwildPrebidMobile.runBannerAuction(
            adView = banner,
            configId = configId,
            widthDp = size.width,
            heightDp = size.height,
            bidderParams = bidderParamsFromRemote(config),
            video = SellwildVideo.isEnabled(config.remoteJson, zoneId),
            adSizes = resolvedAdSizes,
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

        // Tear down a GAM banner / native view if we previously rendered one.
        bannerView?.let {
            it.destroy()
            removeView(it)
            bannerView = null
        }
        nativeAdView?.let { it.destroy(); removeView(it); nativeAdView = null }
        prebidBanner?.let { return it }

        // Capture lateinit property to satisfy Kotlin's null-safety in lambdas.
        val size = adSize

        // BannerView(context, configId, adSize) uses Prebid's standalone
        // rendering — it makes a Prebid Server bid request and renders the
        // winning creative itself, with no ad-server (GAM) call.
        val prebid = PrebidBannerView(
            context,
            configId,
            PrebidAdSize(size.width, size.height),
        ).apply {
            setBannerListener(prebidBannerListener())
            // Prebid's rendering banner owns its own auto-refresh.
            if (config.adRefreshMaxMobile > 0) {
                setAutoRefreshDelay((config.adRefreshIntervalMs / 1000L).toInt())
            }
            // Prebid-rendered outstream video (no GAM) is not supported on the
            // rendering BannerView in the current shaded fork — it has no
            // videoParameters setter (unlike iOS PrebidBannerView). The GAM
            // path (runBannerAuction with video=true) still delivers outstream
            // via a multiformat BannerAdUnit + GAM outstream line item, so
            // prebidOnly is the only surface losing video here.
            if (SellwildVideo.isEnabled(config.remoteJson, zoneId)) {
                Log.w(
                    TAG,
                    "prebidOnly outstream video requested but rendering " +
                        "BannerView has no videoParameters setter in the " +
                        "shaded fork — falling back to banner-only.",
                )
            }
            // Multi-size fallback for the Prebid-rendered banner (primary above).
            SellwildAdSizes.applyRendering(resolvedAdSizes, this)
        }
        prebidBanner = prebid

        val dp = context.resources.displayMetrics.density
        val widthPx = (size.width * dp).toInt()
        val heightPx = (size.height * dp).toInt()
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

    // ── Prebid native path (.prebidOnly + NATIVE_ENABLED) ────────────────────

    private fun ensureNativeAdView(): SellwildNativeAdView? {
        val configId = zoneId
        if (configId.isNullOrEmpty()) {
            // Native rendering needs a configId, same as PREBID_ONLY banners.
            return null
        }

        // Tear down banner render paths if we previously rendered one.
        bannerView?.let { it.destroy(); removeView(it); bannerView = null }
        prebidBanner?.let { it.destroy(); removeView(it); prebidBanner = null }
        nativeAdView?.let { return it }

        val cap = SellwildNative.maxHeight(config.remoteJson, zoneId, fallback = adSize.height)
        val native = SellwildNativeAdView(context, config, configId, cap).apply {
            onLoaded = {
                val self = this@SellwildAdView
                self.listener?.onAdLoaded(self)
                // Native fills to the (capped) height; report it so the host
                // slot resizes to the template rather than clipping.
                self.listener?.onAdResize(self, adSize.width, cap)
                self.listener?.onAdImpression(self, self.zoneId.orEmpty())
            }
            onClick = {
                val self = this@SellwildAdView
                self.listener?.onAdClicked(self)
            }
            onFailed = { message ->
                val self = this@SellwildAdView
                self.listener?.onAdFailed(self, message)
            }
        }
        nativeAdView = native
        addView(native, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        return native
    }

    private fun loadPrebidNative() {
        val native = ensureNativeAdView()
        if (native == null) {
            listener?.onAdFailed(
                this,
                "SellwildAdView resolved to native but has no zoneId; " +
                    "Prebid native rendering requires a configId.",
            )
            return
        }
        native.load()
    }

    // ── Internals ──────────────────────────────────────────────────────────

    private fun bannerAdListener() = object : AdListener() {
        override fun onAdLoaded() {
            val self = this@SellwildAdView
            self.listener?.onAdLoaded(self)
            // Report the actual rendered creative size so multi-size fallbacks
            // (e.g. a 320x50 win in a 300x250 request) resize the host slot.
            self.bannerView?.adSize?.let { self.listener?.onAdResize(self, it.width, it.height) }
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
            if (self.config.debug) android.util.Log.d("SellwildAdView", "[prebidOnly] rendered — zone ${self.zoneId.orEmpty()}")
            self.listener?.onAdLoaded(self)
            // Best-effort: the rendering BannerView doesn't surface the winning
            // creative size to this callback, so report the primary. Multi-size
            // prebidOnly fallbacks won't shrink the slot — a known limitation.
            self.listener?.onAdResize(self, self.adSize.width, self.adSize.height)
            self.listener?.onAdImpression(self, self.zoneId.orEmpty())
        }

        override fun onAdDisplayed(bannerView: PrebidBannerView?) {}

        override fun onAdFailed(bannerView: PrebidBannerView?, exception: AdException?) {
            val self = this@SellwildAdView
            // Loud on purpose: this is how we diagnose why .prebidOnly renders blank.
            if (self.config.debug) android.util.Log.w("SellwildAdView", "[prebidOnly] failed to render — zone ${self.zoneId.orEmpty()}: ${exception?.message}")
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
            "MEMBERSHIP_TYPE", "PBS_DEBUG",
            // Ad-format toggles: read directly by SellwildVideo / SellwildNative,
            // not bidder params — keep them out of the .both auction ext.
            "VIDEO_ENABLED", "VIDEO_ENABLED_BY_ZONE",
            "NATIVE_ENABLED", "NATIVE_ENABLED_BY_ZONE",
            "NATIVE_MAX_HEIGHT", "NATIVE_MAX_HEIGHT_BY_ZONE",
            "BANNER_SIZES", "BANNER_SIZES_BY_ZONE",
        )
    }
}
