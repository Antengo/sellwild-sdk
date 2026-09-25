package com.sellwild.sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.browser.customtabs.CustomTabsIntent
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.admanager.AdManagerAdRequest
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.AdSize as PrebidAdSize
import com.sellwild.prebid.api.exceptions.AdException
import com.sellwild.prebid.api.rendering.BannerView as PrebidBannerView
import com.sellwild.prebid.api.rendering.VideoView as PrebidVideoView
import com.sellwild.prebid.api.rendering.listeners.BannerViewListener
import com.sellwild.sdk.core.AdDecisions
import com.sellwild.sdk.core.AdFlags
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.failures.SellwildLog
import java.util.concurrent.atomic.AtomicBoolean

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
    private val fired = AtomicBoolean(false)

    /** Runs [block] the first time only; subsequent calls are no-ops. */
    fun fireOnce(block: () -> Unit) {
        if (fired.compareAndSet(false, true)) block()
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
     * it null and auto-resolve the bare base. Internal — not a public RN/Flutter
     * prop; set before [setup]/[load] so the prebidOnly imp-ext picks it up.
     */
    var gpidOverride: String? = null

    /**
     * A listing the feed supplies as house-ad backfill when no CMS house image
     * (`HOUSE_AD_IMAGE`) is configured. Rendered only in the MREC slot — a
     * 320x50 banner is too small for a card. See [SellwildHouseAd].
     */
    var houseFallbackListing: SellwildListing? = null

    // Set by setup(). Until then [isSetUp] is false and load()/resume() refuse to run; the
    // placeholders below are never used to load an ad.
    private var config = SellwildConfig(partnerCode = "")
    private var adSize = AdSize.BANNER_320x50
    private var zoneId: String? = null
    private var isSetUp = false

    /** The zone as the listener and events carry it: "" when there is none. */
    private val zoneLabel: String get() = zoneId.orEmpty()

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
        get() = AdDecisions.refreshMax(config.adRefreshMaxMobile, config.adRefreshMax)

    // Cold-start guard: Prebid Mobile init is async and races the first load().
    // Wait up to ~1.2s (8 × 150ms) for init before falling back to GAM-only, so
    // the first impression isn't silently downgraded and loses Prebid demand
    // (AdDecisions.coldStart). Running out of time is reported (ad.prebid_init.timeout).
    private var prebidWaitHandler: Handler? = null
    private var prebidWaitAttempts = 0

    /** The GMA and Prebid calls that need a device or the network ([SellwildPrebidMobile.network]). */
    private val network: SellwildAdNetwork get() = SellwildPrebidMobile.network

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
        isSetUp = true
        config.claimFailurePartner()

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
        if (!isSetUp("load")) return
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
        if (!isSetUp("resume")) return
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
        //
        // prebidOnly, flag off (default): re-issue loadAd() to un-latch the fork's
        // refresh cadence — but this discards the current creative before its
        // viewability tracker fires, so burl (the viewable impression) almost never
        // fires on a scrolling feed. Flag on: keep the already-rendered creative so
        // its tracker fires the impression/burl now that we're back on screen, and
        // resume the cadence on a DELAYED refresh instead of an immediate
        // re-auction. See MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH. The cheap
        // rendered-creative flag is checked before the remote flag (a parse), so a
        // reattach with no rendered creative (common on fast scroll) skips the parse.
        val stack = if (resolvedAdStack == SellwildAdStack.PREBID_ONLY) AdDecisions.Stack.PREBID_ONLY else AdDecisions.Stack.GAM
        when (
            AdDecisions.resume(
                stack = stack,
                refreshMax = effectiveRefreshMax,
                nativeEnabled = { nativeEnabled },
                hasRenderedCreative = prebidHasRenderedCreative,
                keepCreative = { keepsPrebidCreativeOnReattach },
            )
        ) {
            AdDecisions.Resume.SCHEDULE_REFRESH -> scheduleRefresh()
            AdDecisions.Resume.KEEP_CREATIVE -> schedulePrebidRefresh()
            AdDecisions.Resume.RELOAD_PREBID -> prebidBanner?.let { network.loadRendering(it) }
            AdDecisions.Resume.NOTHING -> Unit
        }
    }

    /**
     * Whether [setup] ran. [load] or [resume] before it used to crash the host (the config is
     * lateinit); now the call is reported (ad.setup.missing), the listener hears it, and
     * nothing loads.
     */
    private fun isSetUp(call: String): Boolean {
        if (isSetUp) return true
        SellwildFailures.log(
            code = SellwildFailureCode.AD_SETUP_MISSING,
            component = SellwildFailureComponent.BANNER,
            severity = SellwildFailureSeverity.ERROR,
            message = "$call() called before setup()",
        )
        listener?.onAdFailed(this, "SellwildAdView.$call() called before setup()")
        return false
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
        get() = AdFlags.keepCreativeOnReattach(remoteObject(config.remoteJson))

    /**
     * Resume the prebidOnly refresh cadence WITHOUT discarding the current
     * creative: wait one refresh interval, then re-auction. During the wait the
     * already-rendered creative stays on screen, so its viewability tracker can
     * fire the impression/burl. Only re-auctions if still attached and under the
     * refresh cap. Reuses the shared [refreshHandler]; never stacks callbacks.
     */
    private fun schedulePrebidRefresh() {
        if (!AdDecisions.mayRefresh(prebidRefreshCount, effectiveRefreshMax)) return
        val handler = refreshHandler ?: Handler(Looper.getMainLooper()).also { refreshHandler = it }
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({
            if (isAttachedToWindow) prebidBanner?.let { network.loadRendering(it) }
        }, AdDecisions.refreshIntervalMs(config.adRefreshIntervalMs))
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
        get() = isSetUp && AdFlags.pauseRefreshWhenDetached(remoteObject(config.remoteJson))

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
    private fun isLayoutSelfHealEnabled(): Boolean =
        layoutSelfHeal || (isSetUp && AdFlags.layoutSelfHeal(remoteObject(config.remoteJson)))

    private fun startLayoutSelfHealIfEnabled() {
        if (!isLayoutSelfHealEnabled()) return
        stopLayoutSelfHeal() // never two listeners
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
        val p = parent as? View ?: return
        val (w, h) = AdDecisions.healedSize(width, height, p.width, p.height) ?: return
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
        when (
            val content = AdDecisions.house(
                enabled = SellwildHouseAd.isEnabled(config.remoteJson),
                image = creative,
                listing = houseFallbackListing,
                widthDp = adSize.width,
                heightDp = adSize.height,
            )
        ) {
            is AdDecisions.House.Image -> showHouse().apply {
                onTap = { openHouseUrl(content.image.clickUrl) }
                showImage(content.image)
            }
            is AdDecisions.House.Listing -> showHouse().apply {
                onTap = { openHouseUrl(content.listing.tapUrl(config.partnerCode, config.bhTag)) }
                showListing(content.listing, config)
            }
            else -> houseView?.visibility = GONE // AdDecisions.House.None
        }
    }

    /** The house backdrop, created once behind any paid creative, made visible. */
    private fun showHouse(): SellwildHouseAdView {
        val view = houseView ?: SellwildHouseAdView(context).also {
            houseView = it
            addView(it, 0) // behind any paid creative
        }
        view.visibility = VISIBLE
        return view
    }

    /** Fire the house-impression callback when the backdrop is actually visible. */
    private fun recordHouseImpressionIfShowing() {
        val v = houseView ?: return
        if (v.visibility != VISIBLE) return
        listener?.onHouseAdImpression(this, zoneLabel)
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
        val looksLikeVideo = try {
            bannerView.bidResponse?.isVideo() == true
        } catch (e: Throwable) {
            // Treated as not video, so mute enforcement is skipped for this render. Throwable,
            // as before this was reported: a fork built without isVideo() throws
            // NoSuchMethodError, which must not crash the host.
            logAd(SellwildFailureCode.AD_BID_INSPECT_EXCEPTION, SellwildFailureSeverity.WARN, error = e)
            false
        }
        if (!looksLikeVideo) return

        val check = AdDecisions.videoCheck(expectedVideo) { SellwildVideo.soundEnabled(config.remoteJson, zoneId) }
        if (check.mismatch) {
            // The existing event stays (A6); the failure is reported too.
            SellwildEventQueue.shared(context).track("placementMismatch", label = zoneLabel)
            logAd(
                SellwildFailureCode.AD_PLACEMENT_INVALID,
                SellwildFailureSeverity.WARN,
                message = "a video creative won a banner-only zone",
            )
        }
        for (videoView in videoViews(bannerView)) {
            videoView.mute(check.mute)
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
        val uri = SellwildSafeUrl.external(url)
        if (uri == null) {
            // No click URL configured is not a failure; one that is not http(s) is.
            if (!url.isNullOrEmpty()) {
                logHouse(SellwildFailureCode.HOUSE_OPEN_URL_INVALID, message = "the house ad click URL is not http(s)")
            }
            return
        }
        try {
            CustomTabsIntent.Builder().build().launchUrl(context, uri)
        } catch (e: Throwable) {
            // No browser, or the context cannot start an activity: the tap does nothing.
            // Throwable, as before this was reported: an Error here must not crash the host.
            logHouse(SellwildFailureCode.HOUSE_OPEN_URL_EXCEPTION, error = e, url = url)
        }
    }

    private fun logHouse(code: String, message: String? = null, error: Throwable? = null, url: String? = null) {
        SellwildFailures.log(
            code = code,
            component = SellwildFailureComponent.HOUSE,
            severity = SellwildFailureSeverity.WARN,
            error = error,
            message = message,
            url = url,
            zoneId = zoneId,
        )
    }

    /** Reports an ad failure for this slot. */
    private fun logAd(
        code: String,
        severity: String,
        message: String? = null,
        error: Throwable? = null,
        component: String = SellwildFailureComponent.BANNER,
    ) {
        SellwildFailures.log(
            code = code,
            component = component,
            severity = severity,
            error = error,
            message = message,
            zoneId = zoneId,
        )
    }

    /** Prebid init did not come up during the cold-start wait (the load goes on without it). */
    private fun logPrebidTimeout(then: String, component: String = SellwildFailureComponent.BANNER) {
        logAd(
            SellwildFailureCode.AD_PREBID_INIT_TIMEOUT,
            SellwildFailureSeverity.WARN,
            message = "Prebid not ready after ${AdDecisions.MAX_PREBID_WAIT_ATTEMPTS} waits; $then",
            component = component,
        )
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

        // Captured: inside apply, `adSize` is the AdManagerAdView's own.
        val size = adSize
        val banner = AdManagerAdView(context).apply {
            // Multi-size: primary + any BANNER_SIZES fallbacks.
            SellwildAdSizes.applyGam(resolvedAdSizes, this)
            // No configured unit falls back to Google's test unit, reported once per
            // config (ad.gam_unit.missing): it earns nothing.
            adUnitId = AdDecisions.gamAdUnit(config.gamTag, remoteObject(config.remoteJson), size.width, size.height)
                .reportedOncePer(config.remoteJson)
            adListener = bannerAdListener()
        }
        bannerView = banner

        // Reserve the widest/tallest size the auction may return (primary + any
        // BANNER_SIZES fallbacks) so a wider/taller fallback creative doesn't clip.
        addView(banner, boundingLayoutParams())
        return banner
    }

    /** Layout params for the bounding box of every size the auction may return. */
    private fun boundingLayoutParams(): LayoutParams {
        val bound = SellwildAdSizes.boundingSize(resolvedAdSizes)
        val dp = context.resources.displayMetrics.density
        return LayoutParams(AdDecisions.px(bound.width, dp), AdDecisions.px(bound.height, dp))
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
            network.loadGam(banner, AdManagerAdRequest.Builder().build())
            return
        }

        // .both with a zone to bid against, but Prebid Mobile's async init may
        // not have finished on a cold start (it races the first load()). Wait
        // briefly so the first impression isn't silently downgraded to GAM-only
        // and loses Prebid demand; fall back to plain GAM only if init is too
        // slow or has failed.
        when (AdDecisions.coldStart(SellwildPrebidMobile.isReady(), prebidWaitAttempts)) {
            AdDecisions.ColdStart.WAIT -> {
                waitForPrebid { loadGam(runAuction) }
                return
            }
            AdDecisions.ColdStart.TIMED_OUT -> {
                // Init never came up in time — serve GAM so fill is still attempted.
                prebidWaitAttempts = 0
                logPrebidTimeout("loading GAM without header bidding")
                network.loadGam(banner, AdManagerAdRequest.Builder().build())
                return
            }
            AdDecisions.ColdStart.READY -> Unit
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

        val size = adSize

        // BannerView(context, configId, adSize) uses Prebid's standalone
        // rendering — it makes a Prebid Server bid request and renders the
        // winning creative itself, with no ad-server (GAM) call.
        val prebid = PrebidBannerView(
            context,
            configId,
            PrebidAdSize(size.width, size.height),
        ).apply {
            setBannerListener(prebidEvents)
            // Prebid's rendering banner owns its own auto-refresh.
            if (effectiveRefreshMax > 0) {
                setAutoRefreshDelay(AdDecisions.autoRefreshDelaySeconds(config.adRefreshIntervalMs))
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
        // prebidEvents tightens this box down to it.
        addView(prebid, boundingLayoutParams())
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
        // AdDecisions.renderedSize never gives a non-positive size: it falls back to the primary.
        val pb = prebidBanner ?: return
        val dp = context.resources.displayMetrics.density
        pb.layoutParams = LayoutParams(AdDecisions.px(widthDp, dp), AdDecisions.px(heightDp, dp))
        pb.requestLayout()
    }

    private fun loadPrebidOnly() {
        val prebid = ensurePrebidBanner()
        if (prebid == null) {
            logAd(
                SellwildFailureCode.AD_ZONE_MISSING,
                SellwildFailureSeverity.ERROR,
                message = "PREBID_ONLY needs a zone id (the Prebid configId)",
            )
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
        when (AdDecisions.coldStart(SellwildPrebidMobile.isReady(), prebidWaitAttempts)) {
            AdDecisions.ColdStart.WAIT -> {
                waitForPrebid { loadPrebidOnly() }
                return
            }
            AdDecisions.ColdStart.TIMED_OUT -> logPrebidTimeout("loading the Prebid banner anyway")
            AdDecisions.ColdStart.READY -> Unit
        }
        prebidWaitAttempts = 0
        prebidRefreshCount = 0
        prebidHasRenderedCreative = false
        network.loadRendering(prebid)
    }

    /** One more cold-start wait for Prebid init, then [retry]. */
    private fun waitForPrebid(retry: () -> Unit) {
        prebidWaitAttempts++
        val h = prebidWaitHandler ?: Handler(Looper.getMainLooper()).also { prebidWaitHandler = it }
        h.postDelayed({ retry() }, AdDecisions.PREBID_WAIT_INTERVAL_MS)
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
                self.listener?.onAdImpression(self, self.zoneLabel)
                self.emitAdRender()
            }
            onClick = {
                val self = this@SellwildAdView
                self.listener?.onAdClicked(self)
                SellwildEventQueue.shared(self.context).track("click", label = self.zoneLabel)
            }
            onFailed = { message ->
                val self = this@SellwildAdView
                self.listener?.onAdFailed(self, message)
                SellwildEventQueue.shared(self.context).track("adError", action = message, label = self.zoneLabel)
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
            logAd(
                SellwildFailureCode.AD_ZONE_MISSING,
                SellwildFailureSeverity.ERROR,
                message = "native needs a zone id (the Prebid configId)",
                component = SellwildFailureComponent.NATIVE,
            )
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
        when (AdDecisions.coldStart(SellwildPrebidMobile.isReady(), prebidWaitAttempts)) {
            AdDecisions.ColdStart.WAIT -> {
                waitForPrebid { loadPrebidNative() }
                return
            }
            AdDecisions.ColdStart.TIMED_OUT ->
                logPrebidTimeout("loading the native ad anyway", SellwildFailureComponent.NATIVE)
            AdDecisions.ColdStart.READY -> Unit
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
        q.track("adRenderSucceeded", label = zoneLabel)
        firstAdViewedGuard.fireOnce {
            q.track("firstAdViewed")
            SellwildLog.debug { "[firstAdViewed] fired once for this ad surface (zone $zoneId)" }
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
            self.listener?.onAdImpression(self, self.zoneLabel)
            self.emitAdRender()
            scheduleRefresh()
        }

        override fun onAdFailedToLoad(error: LoadAdError) {
            val self = this@SellwildAdView
            // Empty slot — surface the house backdrop (re-shown in case a prior fill
            // hid it) so the slot isn't blank, then record the house impression.
            self.setHouseVisible(true)
            self.listener?.onAdFailed(self, error.message)
            SellwildEventQueue.shared(self.context).track("adError", action = error.message, label = self.zoneLabel)
            // adError stays for every empty slot (A6); a failure other than no-fill is
            // also reported.
            if (!AdDecisions.isGamNoFill(error.code)) {
                self.logAd(
                    SellwildFailureCode.AD_GAM_LOAD_EXCEPTION,
                    SellwildFailureSeverity.WARN,
                    message = "GAM load error ${error.code}: ${error.message}",
                )
            }
            self.recordHouseImpressionIfShowing()
            scheduleRefresh()
        }

        override fun onAdClicked() {
            val self = this@SellwildAdView
            self.listener?.onAdClicked(self)
            SellwildEventQueue.shared(self.context).track("click", label = self.zoneLabel)
        }
    }

    /** The Prebid rendering banner's events: one listener for every banner this view creates. */
    internal val prebidEvents: BannerViewListener = object : BannerViewListener {
        override fun onAdLoaded(bannerView: PrebidBannerView?) {
            val self = this@SellwildAdView
            // Cap prebidOnly auto-refresh at effectiveRefreshMax. Prebid's internal
            // auto-refresh is otherwise unbounded (unlike the counted GAM path).
            // Fires on the initial render + each refresh; stop once the budget is
            // spent. Fails safe: if this stops firing on refresh, behavior is today's.
            if (self.effectiveRefreshMax > 0) {
                self.prebidRefreshCount++
                if (AdDecisions.prebidRefreshSpent(self.prebidRefreshCount, self.effectiveRefreshMax)) bannerView?.stopRefresh()
            }
            SellwildLog.debug { "[prebidOnly] rendered — zone ${self.zoneId}" }
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
            val (w, h) = AdDecisions.renderedSize(
                bannerView?.creativeWidth ?: 0,
                bannerView?.creativeHeight ?: 0,
                self.adSize.width,
                self.adSize.height,
            )
            self.tightenPrebidSlot(w, h)
            self.listener?.onAdResize(self, w, h)
            self.listener?.onAdImpression(self, self.zoneLabel)
            self.emitAdRender()
        }

        override fun onAdDisplayed(bannerView: PrebidBannerView?) = Unit

        override fun onAdFailed(bannerView: PrebidBannerView?, exception: AdException?) {
            val self = this@SellwildAdView
            val message = exception?.message
            // Empty slot — surface the house backdrop (re-shown in case a prior fill
            // hid it) so the slot isn't blank, then record the house impression.
            self.setHouseVisible(true)
            self.listener?.onAdFailed(self, message ?: "Prebid ad failed")
            SellwildEventQueue.shared(self.context).track("adError", action = message, label = self.zoneLabel)
            // adError stays for every empty slot (A6). This is how we diagnose why
            // .prebidOnly renders blank: a failure other than no-fill is reported, and
            // a no-fill is trace output.
            if (AdDecisions.isPrebidNoFill(message)) {
                SellwildLog.debug { "[prebidOnly] no fill — zone ${self.zoneId}: $message" }
            } else {
                self.logAd(
                    SellwildFailureCode.AD_PREBID_RENDER_EXCEPTION,
                    SellwildFailureSeverity.WARN,
                    message = message ?: "no exception",
                    error = exception,
                )
            }
            self.recordHouseImpressionIfShowing()
        }

        override fun onAdClicked(bannerView: PrebidBannerView?) {
            val self = this@SellwildAdView
            self.listener?.onAdClicked(self)
            SellwildEventQueue.shared(self.context).track("click", label = self.zoneLabel)
        }

        override fun onAdClosed(bannerView: PrebidBannerView?) = Unit
    }

    private fun scheduleRefresh() {
        if (!AdDecisions.mayRefresh(refreshCount, effectiveRefreshMax)) return

        val handler = refreshHandler ?: Handler(Looper.getMainLooper()).also { refreshHandler = it }
        handler.removeCallbacksAndMessages(null) // never stack refresh callbacks (resume()/re-load)
        // Floored so a mis-scaled AD_REFRESH_INTERVAL (a seconds value read as ms)
        // can't fire a sub-second refresh storm.
        handler.postDelayed({
            refreshCount++
            load()
        }, AdDecisions.refreshIntervalMs(config.adRefreshIntervalMs))
    }

    companion object {
        // Google-provided test ad units. /6499/example/banner only fills 320x50;
        // mrec / leaderboard / etc. need their own test units or they no-fill.
        internal const val GAM_TEST_AD_UNIT_BANNER = AdDecisions.GAM_TEST_AD_UNIT_BANNER
        internal const val GAM_TEST_AD_UNIT_ADAPTIVE = AdDecisions.GAM_TEST_AD_UNIT_ADAPTIVE

        /**
         * Resolve the GAM ad unit ID. Order of preference:
         *   1. `config.gamTag` (the real GAM ad unit path provisioned by the CMS).
         *   2. `config.remoteJson["GAM"]` raw passthrough, if set.
         *   3. A size-appropriate Google test ad unit (320x50 → banner test
         *      unit, everything else → adaptive-banner test unit which fills
         *      MREC / leaderboard / large sizes).
         */
        internal fun resolveGAMAdUnitID(config: SellwildConfig, adSize: AdSize? = null): String {
            val remote = remoteObject(config.remoteJson)
            val resolved = if (adSize == null) {
                AdDecisions.gamAdUnit(config.gamTag, remote, 0, 0)
            } else {
                AdDecisions.gamAdUnit(config.gamTag, remote, adSize.width, adSize.height)
            }
            return resolved.value
        }

        /**
         * Forward bidder configs from the raw CDN payload as ext data on the
         * Prebid auction. Each new bidder added to the CMS becomes available
         * to every consuming app immediately, no SDK release. See
         * [AdDecisions.bidderParams] for which keys are bidders.
         */
        internal fun bidderParamsFromRemote(config: SellwildConfig): Map<String, Any?> =
            AdDecisions.bidderParams(remoteObject(config.remoteJson))
    }
}
