package com.sellwild.sdk

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.browser.customtabs.CustomTabsIntent
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdSize as GmaAdSize
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.admanager.AdManagerAdRequest
import com.google.android.gms.ads.admanager.AdManagerAdView
import org.json.JSONObject
import com.sellwild.prebid.AdSize as PrebidAdSize
import com.sellwild.prebid.api.exceptions.AdException
import com.sellwild.prebid.api.rendering.BannerView as PrebidBannerView
import com.sellwild.prebid.api.rendering.VideoView as PrebidVideoView
import com.sellwild.prebid.api.rendering.listeners.BannerViewListener

/**
 * Per-surface once-guard for the web-parity `firstAdViewed` event.
 *
 * The web widget fires `firstAdViewed` once per page load (an in-memory closure
 * flag) so analytics can dedupe the per-render `adRenderSucceeded` down to a
 * single impression; a full navigation reloads the bundle and re-fires it. Native
 * mirrors that per ad *surface*: a standalone [SellwildAdView] owns its own guard
 * (surface = the view) and [SellwildFeedView] shares one across all its ad rows
 * (surface = the feed), so exactly one `firstAdViewed` fires per surface mount —
 * regardless of ad refreshes or how many slots the surface renders — and a fresh
 * mount (navigation) fires again. In-memory only; never persisted.
 */
class SellwildFirstAdViewedGuard {
    @Volatile private var fired = false

    /** Runs [block] the first time only; subsequent calls are no-ops. */
    fun fireOnce(block: () -> Unit) {
        if (fired) return
        synchronized(this) {
            if (fired) return
            fired = true
        }
        block()
    }
}

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
 * Marketplace listings render natively too, via [SellwildFeedView] — the SDK
 * ships no WebView-based surfaces.
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
open class SellwildAdView @JvmOverloads constructor(
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

        /**
         * A house ad backfilled an empty slot (no-fill). NOT a paid impression —
         * report it separately. Fires only when the house backdrop is actually
         * visible. See [SellwildHouseAd].
         */
        fun onHouseAdImpression(adView: SellwildAdView, zoneId: String) {}
    }

    var listener: Listener? = null

    /**
     * Opt in to defensive layout self-healing for hosts that don't lay out this
     * view's children — React Native (esp. the New Architecture / Fabric interop)
     * and custom native wrappers that host this view. Those hosts size the view
     * they manage but skip the measure pass on natively-added children, so the
     * ad ends up 0-sized and fails the viewability check (width>0 + on-screen
     * rect) — no viewable impression, no burl. When enabled, if this view is
     * 0-sized while its parent has real bounds, it re-measures + lays itself out
     * to fill the parent. Guarded to that broken case, so a correctly-laid-out
     * host never triggers it. Also enabled remotely via
     * `MOBILE_LAYOUT_SELF_HEAL`; either source turns it on.
     */
    var layoutSelfHeal: Boolean = false

    /**
     * Per-surface guard for the web-parity `firstAdViewed` event. A standalone
     * view keeps its own (surface = the view); [SellwildFeedView] injects a
     * single shared guard across all its ad rows (surface = the feed) so exactly
     * one `firstAdViewed` fires per surface mount. See [SellwildFirstAdViewedGuard].
     */
    var firstAdViewedGuard = SellwildFirstAdViewedGuard()

    /**
     * Optional code-level ad-stack override. When set, wins over the remote
     * `AD_STACK` / `AD_STACK_BY_ZONE` config — intended for QA / testing.
     */
    var adStackOverride: SellwildAdStack? = null

    /**
     * Effective GPID override for this placement. When set, wins over the
     * remotely-resolved [SellwildGpid.resolveBase] base — the feed sets it to
     * inject the per-slot occurrence suffix (`base#n`). Standalone views leave
     * it null and auto-resolve the bare base. Internal — not a public RN-facing
     * prop; set before [setup]/[load] so the prebidOnly imp-ext picks it up.
     */
    var gpidOverride: String? = null

    /**
     * A listing the feed supplies as house-ad backfill when no CMS house image
     * (`HOUSE_AD_IMAGE`) is configured. Rendered only in the MREC slot — a
     * 320x50 banner is too small for a card. See [SellwildHouseAd].
     */
    var houseFallbackListing: SellwildListing? = null

    private lateinit var config: SellwildConfig
    private lateinit var adSize: AdSize
    private var zoneId: String? = null

    private var bannerView: AdManagerAdView? = null
    // House-ad backdrop. Sits behind the paid creative and shows through only
    // when the slot is empty (no-fill, or the transient PREBID_ONLY refresh gap).
    private var houseView: SellwildHouseAdView? = null
    private var prebidBanner: PrebidBannerView? = null
    private var nativeAdView: SellwildNativeAdView? = null
    private var refreshHandler: Handler? = null
    private var refreshCount = 0
    // prebidOnly renders (initial + auto-refreshes). Caps Prebid's internal
    // auto-refresh at effectiveRefreshMax, which it otherwise ignores.
    private var prebidRefreshCount = 0
    // True once the prebidOnly BannerView has rendered a creative at least once.
    // Gates the reattach behavior: if we already have a rendered creative, a
    // reattach should keep it (so its viewability tracker can fire the
    // impression/burl) rather than discard it with a fresh auction.
    private var prebidHasRenderedCreative = false

    /**
     * Effective mobile refresh cap: the mobile-specific `AD_REFRESH_MAX_MOBILE`
     * when set, else the shared `AD_REFRESH_MAX` (matches iOS + web). Used to
     * gate both the GAM refresh timer and the prebidOnly auto-refresh so a
     * partner who sets only `AD_REFRESH_MAX` still gets refresh on both paths.
     */
    private val effectiveRefreshMax: Int
        get() = if (config.adRefreshMaxMobile > 0) config.adRefreshMaxMobile else config.adRefreshMax

    /**
     * Whether another prebidOnly auction fits the refresh cap. The budget is the
     * first render + up to [effectiveRefreshMax] refreshes; [prebidRefreshCount]
     * counts renders, so it's spent once the count exceeds the max (the same
     * point the render listener calls stopRefresh()).
     */
    private val hasPrebidRefreshBudget: Boolean
        get() = effectiveRefreshMax > 0 && prebidRefreshCount <= effectiveRefreshMax

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

    /**
     * The GPID value applied to this placement's Prebid imp — [gpidOverride]
     * when the feed injected a suffixed value, else the remotely-resolved base.
     * Null → no gpid/pbadslot is set on the imp.
     */
    private val effectiveGpid: String?
        get() = gpidOverride ?: SellwildGpid.resolveBase(config.remoteJson, zoneId)

    fun setup(config: SellwildConfig, adSize: AdSize, zoneId: String? = null) {
        this.config = config
        this.adSize = adSize
        this.zoneId = zoneId

        // Honor the CMS analytics kill switch (EVENTS_ENABLED) and stamp the
        // partner (attributes.code) so events attribute correctly — both before
        // any emit.
        SellwildEventQueue.shared(context).apply {
            enabled = SellwildEvents.isEnabled(config.remoteJson)
            partnerCode = config.partnerCode
        }

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
        if (!::config.isInitialized) {
            Log.w(TAG, "load() called before setup(); ignoring.")
            return
        }
        // Idempotent — first call wins, the rest are cheap.
        SellwildPrebidMobile.bootstrap(context, config)

        // Resolve GrowthCode identity (once per launch, throttled, off-main). No-op
        // unless enabled with a partner id; injects/merges eids into the auction.
        SellwildGrowthCode.resolveIfNeeded(context, config, zoneId)

        // Put the house-ad backdrop behind the slot before the paid creative
        // loads, so an empty slot (no-fill, or the PREBID_ONLY refresh teardown
        // gap) shows house inventory instead of a blank. The paid creative renders
        // on top and covers it, so the slot auto-reverts when fill returns.
        installHouseBackdrop()

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
        // Paused mid cold-start wait → the pending first auction is cancelled;
        // flag it so resume() re-issues load() instead of only restarting refresh.
        if (prebidWaitAttempts > 0) needsReloadOnResume = true
        refreshHandler?.removeCallbacksAndMessages(null)
        refreshHandler = null
        prebidWaitHandler?.removeCallbacksAndMessages(null)
        prebidWaitHandler = null
        prebidWaitAttempts = 0
        bannerView?.pause()
        prebidBanner?.stopRefresh()
    }

    fun resume() {
        if (!::config.isInitialized) {
            Log.w(TAG, "resume() called before setup(); ignoring.")
            return
        }
        if (needsReloadOnResume) {
            needsReloadOnResume = false
            load() // the first auction never completed (paused mid cold-start)
            return
        }
        bannerView?.resume()
        // Restart the refresh cadence paused by pause(): our timer on the GAM
        // path. On prebidOnly, setting the delay alone doesn't re-arm — pause()'s
        // stopRefresh() latched the banner (the fork clears that only on a new bid
        // request), so re-issue loadAd() to actually resume the auto-refresh
        // cadence (parity with iOS resume()).
        when (resolvedAdStack) {
            SellwildAdStack.BOTH, SellwildAdStack.GAM_ONLY -> scheduleRefresh()
            SellwildAdStack.PREBID_ONLY ->
                // Only while the refresh cap has budget: once it is spent, a reattach
                // starts no new auction (with either flag) — the last creative stays.
                if (hasPrebidRefreshBudget && !nativeEnabled) {
                    // Default (flag off): re-issue loadAd() to un-latch the fork's
                    // refresh cadence — but this discards the current creative
                    // before its viewability tracker fires, so burl (the viewable
                    // impression) almost never fires on a scrolling feed.
                    // Flag on: keep the already-rendered creative so its tracker
                    // fires the impression/burl now that we're back on screen, and
                    // resume the cadence on a DELAYED refresh instead of an
                    // immediate re-auction. See MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH.
                    // Order matters: the cheap flag short-circuits before
                    // keepsPrebidCreativeOnReattach, which parses remoteJson — so a
                    // reattach with no rendered creative (common on fast scroll)
                    // skips the parse entirely.
                    if (prebidHasRenderedCreative && keepsPrebidCreativeOnReattach) {
                        schedulePrebidRefresh()
                    } else {
                        prebidBanner?.loadAd()
                    }
                }
        }
    }

    /**
     * Whether a prebidOnly reattach should keep the already-rendered creative
     * (letting its viewability tracker fire the impression/burl) and resume the
     * refresh cadence on a delayed timer, instead of immediately re-auctioning
     * (which discards the creative before it can be counted).
     *
     * Remote-config gated; defaults to `false` (today's behavior) so it ships
     * dormant and can be validated per-partner from the CDN with no release.
     * Set `MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH: true` to enable.
     */
    private val keepsPrebidCreativeOnReattach: Boolean
        get() {
            if (!::config.isInitialized) return false
            val obj = config.remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return false
            if (!obj.has("MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH") ||
                obj.isNull("MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH")
            ) {
                return false
            }
            return when (val v = obj.get("MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH")) {
                is Boolean -> v
                is Number -> v.toInt() != 0
                is String -> v.lowercase() in setOf("1", "true", "yes", "on")
                else -> false
            }
        }

    /**
     * Resume the prebidOnly refresh cadence WITHOUT discarding the current
     * creative: wait one refresh interval, then re-auction. During the wait the
     * already-rendered creative stays on screen, so its viewability tracker can
     * fire the impression/burl. Only re-auctions if still attached and under the
     * refresh cap. Reuses the shared [refreshHandler]; never stacks callbacks.
     */
    private fun schedulePrebidRefresh() {
        if (!hasPrebidRefreshBudget) return
        val handler = refreshHandler ?: Handler(Looper.getMainLooper()).also { refreshHandler = it }
        handler.removeCallbacksAndMessages(null)
        val interval = config.adRefreshIntervalMs.coerceAtLeast(MIN_REFRESH_INTERVAL_MS)
        handler.postDelayed({
            if (isAttachedToWindow) prebidBanner?.loadAd()
        }, interval)
    }

    // ── Detached-refresh pause (default ON) ──────────────────────────────────
    // Pause the refresh cadence while this view is fully detached from the window
    // (recycled / in the RecyclerView pool) and resume on re-attach. A detached
    // view that keeps posting refresh load()s leaks the view/Activity and burns
    // never-rendered auctions (invalid traffic). ON by default; set
    // MOBILE_PAUSE_REFRESH_DETACHED = false to opt out. Off-screen-but-ATTACHED
    // refreshes are unaffected — this only gates FULLY-detached views.

    private var isPausedForDetach = false
    // Set when pause() interrupts an in-flight first auction (cold-start wait);
    // resume() then re-issues load() so the first impression isn't lost.
    private var needsReloadOnResume = false

    private val pausesRefreshWhenDetached: Boolean
        get() {
            if (!::config.isInitialized) return false
            val obj = config.remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return true
            if (!obj.has("MOBILE_PAUSE_REFRESH_DETACHED") || obj.isNull("MOBILE_PAUSE_REFRESH_DETACHED")) return true
            return when (val v = obj.get("MOBILE_PAUSE_REFRESH_DETACHED")) {
                is Boolean -> v
                is Number -> v.toInt() != 0
                is String -> v.lowercase() in setOf("1", "true", "yes", "on")
                else -> true
            }
        }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopLayoutSelfHeal()
        if (pausesRefreshWhenDetached && !isPausedForDetach) {
            isPausedForDetach = true
            pause()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startLayoutSelfHealIfEnabled()
        if (pausesRefreshWhenDetached && isPausedForDetach) {
            isPausedForDetach = false
            resume()
        }
    }

    // ── Layout self-heal (default OFF; see [layoutSelfHeal]) ──────────────────
    private var selfHealListener: android.view.ViewTreeObserver.OnGlobalLayoutListener? = null

    /** True when self-heal is enabled by the host property or remote config. */
    private fun isLayoutSelfHealEnabled(): Boolean {
        if (layoutSelfHeal) return true
        if (!::config.isInitialized) return false
        val obj = config.remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return false
        if (!obj.has("MOBILE_LAYOUT_SELF_HEAL") || obj.isNull("MOBILE_LAYOUT_SELF_HEAL")) return false
        return when (val v = obj.get("MOBILE_LAYOUT_SELF_HEAL")) {
            is Boolean -> v
            is Number -> v.toInt() != 0
            is String -> v.lowercase() in setOf("1", "true", "yes", "on")
            else -> false
        }
    }

    private fun startLayoutSelfHealIfEnabled() {
        if (selfHealListener != null || !isLayoutSelfHealEnabled()) return
        val l = android.view.ViewTreeObserver.OnGlobalLayoutListener { healLayoutIfCollapsed() }
        selfHealListener = l
        viewTreeObserver.addOnGlobalLayoutListener(l)
    }

    private fun stopLayoutSelfHeal() {
        selfHealListener?.let { viewTreeObserver.removeOnGlobalLayoutListener(it) }
        selfHealListener = null
    }

    /**
     * If this view is 0-sized while its parent has real bounds (the RN /
     * custom-wrapper case where the host didn't measure our children), force a
     * measure + layout to fill the parent. Converges: once sized, the guard is
     * false, so it won't re-fire.
     */
    private fun healLayoutIfCollapsed() {
        if (width != 0 && height != 0) return
        val p = parent as? View ?: return
        val w = p.width
        val h = p.height
        if (w <= 0 || h <= 0) return
        measure(
            View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY),
        )
        layout(0, 0, w, h)
    }

    fun destroy() {
        pause()
        bannerView?.destroy()
        bannerView = null
        prebidBanner?.destroy()
        prebidBanner = null
        prebidHasRenderedCreative = false
        nativeAdView?.destroy()
        nativeAdView = null
    }

    // ── House ad backdrop ────────────────────────────────────────────────────

    /**
     * Create (once) and populate the house-ad backdrop for this slot. Content
     * precedence: CMS house image → feed-supplied listing (MREC only) → nothing.
     * Called on every [load]; content is refreshed but the view is reused.
     */
    private fun installHouseBackdrop() {
        val creative = SellwildHouseAd.resolve(config.remoteJson, zoneId, adSize.width, adSize.height)
        val listing = houseFallbackListing
        val isMrec = adSize.width >= 300 && adSize.height >= 250
        if (!SellwildHouseAd.isEnabled(config.remoteJson) ||
            (creative == null && !(listing != null && isMrec))
        ) {
            houseView?.visibility = GONE
            return
        }

        val view = houseView ?: SellwildHouseAdView(context).also {
            houseView = it
            addView(it, 0) // behind any paid creative
        }
        view.visibility = VISIBLE

        if (creative != null) {
            view.onTap = { openHouseUrl(creative.clickUrl) }
            view.showImage(creative)
        } else if (listing != null) {
            view.onTap = { openHouseUrl(listing.tapUrl(config.partnerCode, config.bhTag)) }
            view.showListing(listing, config)
        }
    }

    /** Fire the house-impression callback when the backdrop is actually visible. */
    private fun recordHouseImpressionIfShowing() {
        val v = houseView ?: return
        if (v.visibility != VISIBLE) return
        listener?.onHouseAdImpression(this, zoneId.orEmpty())
    }

    /** Show/hide the house backdrop. Kept as a class method so the inherited
     *  View VISIBLE/GONE constants resolve unqualified — the ad-listener
     *  callbacks that toggle it are anonymous objects, not View subclasses. */
    private fun setHouseVisible(visible: Boolean) {
        houseView?.visibility = if (visible) VISIBLE else GONE
    }

    /** Best-effort, SDK-surface mute of auto-playing creative audio in this
     *  slot's WebView(s). No Prebid-fork dependency. See [SellwildAdAudioGuard]. */
    private fun applyAudioGuard() {
        SellwildAdAudioGuard.apply(this, config.remoteJson)
    }

    /**
     * Defense-in-depth against outstream audio, run on EVERY prebidOnly render
     * regardless of whether this zone requested video (a video creative can win
     * either way):
     *  1. Placement validation — [PrebidBannerView.getBidResponse]'s
     *     `isVideo()` (type-checks `ext.prebid.type`, falls back to sniffing the
     *     raw `adm` for VAST) tells us whether the winning bid is ACTUALLY video
     *     regardless of what `imp.video` we requested. On a mismatch (video won
     *     a zone that never enabled video — a bidder/stored-imp ignoring the
     *     request), report it via analytics for visibility.
     *  2. Direct player enforcement — unlike iOS, the shaded fork exposes no
     *     client-side mute CONFIG on the rendering path (no
     *     `VideoControlsConfiguration` equivalent); the only enforcement point
     *     is [PrebidVideoView.mute], found by walking [bannerView]'s own child
     *     hierarchy (mirrors [SellwildAdAudioGuard]'s WebView walk). The
     *     request-side `AutoPlaySoundOff` playback-method signal
     *     ([SellwildVideo.outstreamParameters]) is advisory only — bidders can
     *     ignore it — so this call is the actual enforcement, not the request.
     */
    private fun enforceVideoMuteAndValidatePlacement(bannerView: PrebidBannerView) {
        val expectedVideo = SellwildVideo.isEnabled(config.remoteJson, zoneId)
        val looksLikeVideo = runCatching { bannerView.bidResponse?.isVideo() }.getOrNull() == true
        if (!looksLikeVideo) return

        if (!expectedVideo) {
            if (config.debug) {
                Log.d("SellwildAdView", "[prebidOnly] placement mismatch — video creative won a banner-only zone ${zoneId.orEmpty()}")
            }
            SellwildEventQueue.shared(context).track("placementMismatch", label = zoneId.orEmpty())
        }

        val wantsSound = expectedVideo && SellwildVideo.soundEnabled(config.remoteJson, zoneId)
        for (videoView in videoViews(bannerView)) {
            videoView.mute(!wantsSound)
        }
    }

    /** Depth-first collect every [PrebidVideoView] in the subtree rooted at
     *  [root] (mirrors [SellwildAdAudioGuard]'s WebView walk). */
    private fun videoViews(root: View): List<PrebidVideoView> {
        if (root is PrebidVideoView) return listOf(root)
        if (root !is ViewGroup) return emptyList()
        val found = mutableListOf<PrebidVideoView>()
        for (i in 0 until root.childCount) {
            found.addAll(videoViews(root.getChildAt(i)))
        }
        return found
    }

    private fun openHouseUrl(url: String?) {
        // http/https only — the click URL is remote CMS config; never hand an
        // arbitrary scheme (intent:/market:/deep link) to an ACTION_VIEW intent.
        val uri = SellwildSafeUrl.external(url) ?: return
        runCatching { CustomTabsIntent.Builder().build().launchUrl(context, uri) }
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

        // Reserve the widest/tallest size the auction may return (primary + any
        // BANNER_SIZES fallbacks) so a wider/taller fallback creative doesn't clip.
        val bound = SellwildAdSizes.boundingSize(resolvedAdSizes)
        val dp = context.resources.displayMetrics.density
        val widthPx = (bound.width * dp).toInt()
        val heightPx = (bound.height * dp).toInt()
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
        // Bidder params are configured server-side in the stored imp. Don't send
        // CMS config inline — it includes non-bidder keys that PBS rejects
        // (parity with iOS, which sends empty bidder params).
        SellwildPrebidMobile.runBannerAuction(
            adView = banner,
            configId = configId,
            widthDp = size.width,
            heightDp = size.height,
            video = SellwildVideo.isEnabled(config.remoteJson, zoneId),
            adSizes = resolvedAdSizes,
            gpid = effectiveGpid,
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
            if (effectiveRefreshMax > 0) {
                setAutoRefreshDelay((config.adRefreshIntervalMs.coerceAtLeast(MIN_REFRESH_INTERVAL_MS) / 1000L).toInt())
            }
            // Multiformat: request banner AND outstream video on one imp when
            // enabled. The shaded fork (3.3.2-sw1) exposes setAdUnitFormats on the
            // rendering BannerView; the render path (DisplayView -> PrebidRenderer
            // -> PrebidDisplayView) renders whichever creative wins (VideoView for
            // a VAST bid, banner otherwise). Mirrors the iOS prebidOnly path.
            if (SellwildVideo.isEnabled(config.remoteJson, zoneId)) {
                setAdUnitFormats(SellwildVideo.bannerVideoFormats())
                setVideoParameters(SellwildVideo.outstreamParameters())
            }
            // Multi-size fallback for the Prebid-rendered banner (primary above).
            SellwildAdSizes.applyRendering(resolvedAdSizes, this)
            // GPID: emit imp.ext.gpid + imp.ext.data.pbadslot. This path sets no
            // bidder params (that's the .both auction ext), so only the gpid is
            // carried; null gpid → nothing is set. Verified the rendering
            // BannerView exposes setImpOrtbConfig(String) in fork 3.3.2.
            SellwildGpid.impExtJson(effectiveGpid)?.let { setImpOrtbConfig(it) }
        }
        prebidBanner = prebid

        // Reserve the widest/tallest size the auction may return so a wider/
        // taller multi-size winner doesn't clip before it renders. Once the
        // creative renders, the sw3 fork surfaces the won size and
        // prebidBannerListener tightens this box down to it.
        val bound = SellwildAdSizes.boundingSize(resolvedAdSizes)
        val dp = context.resources.displayMetrics.density
        val widthPx = (bound.width * dp).toInt()
        val heightPx = (bound.height * dp).toInt()
        addView(prebid, LayoutParams(widthPx, heightPx))
        return prebid
    }

    /**
     * Shrink the reserved multi-size prebidOnly slot to the creative that won.
     * The slot is reserved at the bounding box of all requested sizes; once the
     * sw3 fork surfaces the won size we resize the rendering banner to it so a
     * smaller winner (e.g. 320x50 in a 300x250 + 320x50 slot) doesn't leave
     * whitespace. No-op on a missing view or non-positive size.
     */
    private fun tightenPrebidSlot(widthDp: Int, heightDp: Int) {
        if (widthDp <= 0 || heightDp <= 0) return
        val pb = prebidBanner ?: return
        val dp = context.resources.displayMetrics.density
        pb.layoutParams = LayoutParams((widthDp * dp).toInt(), (heightDp * dp).toInt())
        pb.requestLayout()
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
        // Cold-start guard (mirrors loadGam): Prebid init is async and races the
        // first load(). Unlike GAM we can't fall back to a GAM request, so a
        // premature loadAd() no-fills and leaves the slot blank. Wait briefly for
        // readiness, then load regardless once the wait budget is spent.
        if (!SellwildPrebidMobile.isReady() && prebidWaitAttempts < maxPrebidWaitAttempts) {
            prebidWaitAttempts++
            val h = prebidWaitHandler ?: Handler(Looper.getMainLooper()).also { prebidWaitHandler = it }
            h.postDelayed({ loadPrebidOnly() }, prebidWaitIntervalMs)
            return
        }
        prebidWaitAttempts = 0
        prebidRefreshCount = 0
        prebidHasRenderedCreative = false
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
                // Native creative filled — hide the house backdrop so it can't
                // bleed through the transparent native template (parity with the
                // GAM/prebid banner paths, whose opaque creatives cover it).
                self.setHouseVisible(false)
                self.applyAudioGuard()
                self.listener?.onAdLoaded(self)
                // Native fills to the (capped) height; report it so the host
                // slot resizes to the template rather than clipping.
                self.listener?.onAdResize(self, adSize.width, cap)
                self.listener?.onAdImpression(self, self.zoneId.orEmpty())
                self.emitAdRender()
            }
            onClick = {
                val self = this@SellwildAdView
                self.listener?.onAdClicked(self)
                SellwildEventQueue.shared(self.context).track("click", label = self.zoneId.orEmpty())
            }
            onFailed = { message ->
                val self = this@SellwildAdView
                self.listener?.onAdFailed(self, message)
                SellwildEventQueue.shared(self.context).track("adError", action = message, label = self.zoneId.orEmpty())
                // Native no-fill — the house backdrop (installed in load()) is
                // still showing, so record it as a house impression, matching the
                // banner no-fill callbacks. No-op unless the house view is visible.
                self.recordHouseImpressionIfShowing()
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
        // Cold-start guard (mirrors loadPrebidOnly): native fetchDemand can race
        // Prebid init, and native is one-shot (no auto-refresh/retry) — a premature
        // no-fill strands the slot on house/blank for its lifetime. Wait briefly
        // for readiness, then load regardless once the wait budget is spent.
        if (!SellwildPrebidMobile.isReady() && prebidWaitAttempts < maxPrebidWaitAttempts) {
            prebidWaitAttempts++
            val h = prebidWaitHandler ?: Handler(Looper.getMainLooper()).also { prebidWaitHandler = it }
            h.postDelayed({ loadPrebidNative() }, prebidWaitIntervalMs)
            return
        }
        prebidWaitAttempts = 0
        native.load()
    }

    // ── Internals ──────────────────────────────────────────────────────────

    /**
     * Emit the per-render `adRenderSucceeded` (fires on every render/refresh,
     * unchanged) plus — once per ad surface — the web-parity `firstAdViewed`.
     * `firstAdViewed` carries the same `attributes.code` (stamped in the queue
     * flush) but no label, matching the web widget's payload, and is deduped by
     * [firstAdViewedGuard] so it lands once per surface mount even across refreshes.
     */
    private fun emitAdRender() {
        val q = SellwildEventQueue.shared(context)
        q.track("adRenderSucceeded", label = zoneId.orEmpty())
        firstAdViewedGuard.fireOnce {
            q.track("firstAdViewed")
            android.util.Log.d(
                "SellwildEvents",
                "[firstAdViewed] fired once for this ad surface (zone ${zoneId.orEmpty()})",
            )
        }
    }

    private fun bannerAdListener() = object : AdListener() {
        override fun onAdLoaded() {
            val self = this@SellwildAdView
            // Paid creative rendered — hide the house backdrop so a transparent
            // or smaller-than-slot creative can't bleed through (re-shown on a
            // later no-fill). Mirrors the native path; don't rely on the creative
            // being opaque and full-slot.
            self.setHouseVisible(false)
            self.applyAudioGuard()
            self.listener?.onAdLoaded(self)
            // Report the actual rendered creative size so multi-size fallbacks
            // (e.g. a 320x50 win in a 300x250 request) resize the host slot.
            self.bannerView?.adSize?.let { self.listener?.onAdResize(self, it.width, it.height) }
            self.listener?.onAdImpression(self, self.zoneId.orEmpty())
            self.emitAdRender()
            scheduleRefresh()
        }

        override fun onAdFailedToLoad(error: LoadAdError) {
            val self = this@SellwildAdView
            // No-fill — surface the house backdrop (re-shown in case a prior fill
            // hid it) so the slot isn't blank, then record the house impression.
            self.setHouseVisible(true)
            self.listener?.onAdFailed(self, error.message)
            SellwildEventQueue.shared(self.context).track("adError", action = error.message, label = self.zoneId.orEmpty())
            self.recordHouseImpressionIfShowing()
            scheduleRefresh()
        }

        override fun onAdClicked() {
            val self = this@SellwildAdView
            self.listener?.onAdClicked(self)
            SellwildEventQueue.shared(self.context).track("click", label = self.zoneId.orEmpty())
        }
    }

    private fun prebidBannerListener() = object : BannerViewListener {
        override fun onAdLoaded(bannerView: PrebidBannerView?) {
            val self = this@SellwildAdView
            // Cap prebidOnly auto-refresh at effectiveRefreshMax. Prebid's internal
            // auto-refresh is otherwise unbounded (unlike the counted GAM path).
            // Fires on the initial render + each refresh; stop once the budget is
            // spent. Fails safe: if this stops firing on refresh, behavior is today's.
            if (self.effectiveRefreshMax > 0) {
                self.prebidRefreshCount++
                if (self.prebidRefreshCount > self.effectiveRefreshMax) bannerView?.stopRefresh()
            }
            if (self.config.debug) android.util.Log.d("SellwildAdView", "[prebidOnly] rendered — zone ${self.zoneId.orEmpty()}")
            self.prebidHasRenderedCreative = true
            // Paid creative rendered — hide the house backdrop so a transparent or
            // smaller-than-slot creative can't bleed through. NOTE: Prebid's
            // rendering banner self-refreshes with a teardown gap the backdrop used
            // to cover; that gap now shows the slot background briefly instead of
            // house inventory. Acceptable vs. the bleed-through it prevents, and
            // only affects PREBID_ONLY with refresh enabled.
            self.setHouseVisible(false)
            self.applyAudioGuard()
            bannerView?.let { self.enforceVideoMuteAndValidatePlacement(it) }
            self.listener?.onAdLoaded(self)
            // sw3 fork getters surface the winning creative size, so tighten the
            // reserved multi-size bounding box to what actually rendered and
            // report it. Falls back to the primary when the fork can't report a
            // size (0 — e.g. no-fill), preserving prior behavior.
            val wonW = bannerView?.creativeWidth ?: 0
            val wonH = bannerView?.creativeHeight ?: 0
            val w = if (wonW > 0) wonW else self.adSize.width
            val h = if (wonH > 0) wonH else self.adSize.height
            self.tightenPrebidSlot(w, h)
            self.listener?.onAdResize(self, w, h)
            self.listener?.onAdImpression(self, self.zoneId.orEmpty())
            self.emitAdRender()
        }

        override fun onAdDisplayed(bannerView: PrebidBannerView?) {}

        override fun onAdFailed(bannerView: PrebidBannerView?, exception: AdException?) {
            val self = this@SellwildAdView
            // Loud on purpose: this is how we diagnose why .prebidOnly renders blank.
            if (self.config.debug) android.util.Log.w("SellwildAdView", "[prebidOnly] failed to render — zone ${self.zoneId.orEmpty()}: ${exception?.message}")
            // No-fill — surface the house backdrop (re-shown in case a prior fill
            // hid it) so the slot isn't blank, then record the house impression.
            self.setHouseVisible(true)
            self.listener?.onAdFailed(self, exception?.message ?: "Prebid ad failed")
            SellwildEventQueue.shared(self.context).track("adError", action = exception?.message, label = self.zoneId.orEmpty())
            self.recordHouseImpressionIfShowing()
        }

        override fun onAdClicked(bannerView: PrebidBannerView?) {
            val self = this@SellwildAdView
            self.listener?.onAdClicked(self)
            SellwildEventQueue.shared(self.context).track("click", label = self.zoneId.orEmpty())
        }

        override fun onAdClosed(bannerView: PrebidBannerView?) {}
    }

    private fun scheduleRefresh() {
        // Detached (paused for detach): a GAM load that lands after pause() must
        // not re-arm refresh on an off-window view — resume() restarts it.
        if (isPausedForDetach) return
        val maxRefresh = effectiveRefreshMax
        if (maxRefresh <= 0 || refreshCount >= maxRefresh) return

        val handler = refreshHandler ?: Handler(Looper.getMainLooper()).also { refreshHandler = it }
        handler.removeCallbacksAndMessages(null) // never stack refresh callbacks (resume()/re-load)
        // Floor the interval so a mis-scaled AD_REFRESH_INTERVAL (a seconds value
        // read as ms) can't fire a sub-second refresh storm.
        val interval = config.adRefreshIntervalMs.coerceAtLeast(MIN_REFRESH_INTERVAL_MS)
        handler.postDelayed({
            refreshCount++
            load()
        }, interval)
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

        /** Floor for the GAM manual-refresh timer — storm guard against a
         *  mis-scaled AD_REFRESH_INTERVAL (a seconds value read as ms). */
        private const val MIN_REFRESH_INTERVAL_MS = 10_000L

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
    }
}
