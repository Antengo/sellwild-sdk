package com.sellwild.sdk

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.util.Base64
import android.util.LruCache
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.browser.customtabs.CustomTabsIntent
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.sellwild.sdk.core.AdDecisions
import com.sellwild.sdk.core.AdFlags
import com.sellwild.sdk.core.FeedColors
import com.sellwild.sdk.core.FeedRow
import com.sellwild.sdk.core.FeedSchedule
import com.sellwild.sdk.core.FeedTheme
import com.sellwild.sdk.core.Format
import com.sellwild.sdk.core.HouseImages
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL

/**
 * All-in-one native feed surface. As of 1.4.0 this view renders a
 * single-column scroll of native listing cards interleaved with native
 * Prebid + GAM ads, according to the CDN-published `COL1` token string.
 *
 * COL1 grammar (one token = one row):
 *   - `L` = listing card
 *   - `G` = GAM 300x250 ad (zone ID drawn from `config.mobileZids` in order)
 *   - `D` = direct ad unit (300x250, currently identical to `G` until a
 *           direct-served path lands)
 *   - `B` = 320x50 banner (zone ID = `config.mobileBannerZid`)
 *
 * The renderer iterates the string left-to-right, emitting one row per
 * token, and stops when the string is exhausted. There is **no WebView**
 * anywhere in this surface — every row is native.
 *
 * Usage:
 * ```kotlin
 * val config = SellwildSDK.configure(context, "weatherbug", "weatherbug-weatherbug")
 * val feed = SellwildFeedView(context).apply { setup(config) }
 * parent.addView(feed)
 * feed.load()
 * ```
 */
open class SellwildFeedView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : LinearLayout(context, attrs, defStyleAttr) {

    interface Listener {
        /**
         * Called when a listing card is tapped. Return `true` to consume the
         * event; return `false` to let the SDK open `listing.url` in
         * Custom Tabs.
         */
        fun onListingTap(listing: SellwildListing): Boolean = false
        fun onAdImpression(zoneId: String) {}
        /**
         * A house ad backfilled an empty ad slot in the feed (a no-fill). NOT a
         * paid impression — report it separately. See [SellwildHouseAd].
         */
        fun onHouseAdImpression(zoneId: String) {}
        fun onAdClicked(zoneId: String) {}
        fun onLoad() {}
        /**
         * Fires after a successful fetch with the number of listings bound to the
         * feed adapter. `count == 0` means an empty / header-only render — the
         * fetch succeeded but returned no listings (e.g. a config that resolved to
         * the wrong/empty listings source). Unlike [onLoad] (a "fetch completed"
         * signal that also fires on empty), this reliably reflects whether listings
         * were attached. RecyclerView lays the item views out on the next frame;
         * this fires when the rows are bound to the adapter.
         */
        fun onFeedReady(listingCount: Int) {}
        fun onError(message: String) {}
        /**
         * Called whenever the feed's rendered content height changes (deduped
         * against the last reported value). Use this to size the feed's
         * container when embedding it inside a parent scroll view with
         * `scrollEnabled = false`. [heightDp] is in density-independent pixels.
         */
        fun onContentHeightChanged(feedView: SellwildFeedView, heightDp: Int) {}
    }

    var listener: Listener? = null

    /**
     * Opt in to defensive layout self-healing for hosts that don't lay out this
     * view's children — React Native (esp. New Architecture / Fabric interop) and
     * custom native wrappers. Those hosts size the view they manage but skip the
     * measure pass on natively-added children, so the feed (and its ad rows) can
     * end up 0-sized and fail the ad viewability check — no viewable impression,
     * no burl. When enabled, if this view is 0-sized while its parent has real
     * bounds, it re-measures + lays itself out to fill the parent. Guarded to that
     * broken case. Also enabled remotely via `MOBILE_LAYOUT_SELF_HEAL`.
     */
    var layoutSelfHeal: Boolean = false

    /**
     * Disable the feed's own scrolling so it can be embedded inside a parent
     * scroll view (single-scroll pages, e.g. alongside a Taboola feed). When
     * `false` the recycler switches to `WRAP_CONTENT` and renders every row
     * (no virtualization), and pull-to-refresh is disabled (it needs the
     * scroll gesture), so the host must drive refresh. Defaults to `true` —
     * existing full-screen integrations are unaffected.
     */
    var scrollEnabled: Boolean = true
        set(value) {
            field = value
            recycler.isNestedScrollingEnabled = value
            refreshLayout.isEnabled = value
            // A MATCH_PARENT recycler clips to the viewport and virtualizes
            // rows; when embedded we want it to wrap its content so the parent
            // can scroll it fully. A LinearLayoutManager recycler with
            // WRAP_CONTENT height measures and lays out all items.
            val h = if (value) {
                ViewGroup.LayoutParams.MATCH_PARENT
            } else {
                ViewGroup.LayoutParams.WRAP_CONTENT
            }
            recycler.layoutParams = recycler.layoutParams.also { it.height = h }
            refreshLayout.layoutParams = refreshLayout.layoutParams.also { it.height = h }
            recycler.requestLayout()
        }

    /**
     * The feed's current rendered content height in dp, for imperative reads.
     * Also surfaced push-style via [Listener.onContentHeightChanged].
     */
    val contentHeightDp: Int
        get() = (recycler.measuredHeight / context.resources.displayMetrics.density).toInt()

    /** Last height reported to the listener, so we dedupe repeated values. */
    private var lastReportedHeightDp: Int = -1

    private var config: SellwildConfig? = null
    private var schedule: String = FeedSchedule.DEFAULT
    private var colors = FeedColors(FeedTheme.BACKGROUND, FeedTheme.TITLE, FeedTheme.POWERED_BY, FeedTheme.PRICE)
    private var listings: List<SellwildListing> = emptyList()
    // True once a fetch has succeeded (even with zero listings). Gates the
    // auto-reload on re-attach: a load cancelled by a detach (fast scroll) is
    // retried, but a legitimately-empty successful feed is not re-fetched on
    // every scroll-back.
    private var loadSucceeded = false

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var loadJob: Job? = null

    private val refreshLayout: SwipeRefreshLayout
    private val recycler: RecyclerView
    private val adapter = RowAdapter()

    /**
     * One `firstAdViewed` guard for the whole feed surface — the feed is one
     * "page", so every ad row shares it and only the first render across the feed
     * fires `firstAdViewed` (web parity). A new feed instance (screen mount) gets
     * a fresh guard and fires again. See [SellwildFirstAdViewedGuard].
     */
    private val firstAdViewedGuard = SellwildFirstAdViewedGuard()

    init {
        orientation = VERTICAL
        // A view has no layout params while it is being constructed (a parent sets them
        // when it adds the view), so this is the default until then.
        layoutParams = LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )

        refreshLayout = SwipeRefreshLayout(context).apply {
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setOnRefreshListener { refresh() }
        }

        recycler = RecyclerView(context).apply {
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            layoutManager = LinearLayoutManager(context)
            this.adapter = this@SellwildFeedView.adapter
            clipToPadding = false
        }

        // Report content-height changes to the host so it can size the feed's
        // container when embedded (scrollEnabled = false). Fires on any layout
        // pass where the measured height differs; the report itself dedupes.
        recycler.addOnLayoutChangeListener { _, _, top, _, bottom, _, oldTop, _, oldBottom ->
            if (bottom - top != oldBottom - oldTop) reportContentHeight()
        }

        refreshLayout.addView(recycler)
        addView(refreshLayout)
    }

    private fun reportContentHeight() {
        val heightDp = contentHeightDp
        if (heightDp == lastReportedHeightDp) return
        lastReportedHeightDp = heightDp
        listener?.onContentHeightChanged(this, heightDp)
    }

    /**
     * Attach a [SellwildConfig] without kicking off a fetch. A CMS color that is not a color
     * falls back and is reported once (config.color.invalid).
     */
    fun setup(config: SellwildConfig) {
        this.config = config
        config.claimFailurePartner()
        schedule = FeedSchedule.normalize(config.col1)
        colors = FeedTheme.resolve(config.priceColor, config.titleColor, config.linkColor, Color::parseColor)
            .reportedOncePer(config.remoteJson)
        setBackgroundColor(colors.background)
        refreshLayout.setProgressBackgroundColorSchemeColor(colors.background)
        adapter.notifyDataSetChanged()
    }

    /**
     * Fetch listings and render the feed. A failed fetch was reported by the API client, so
     * it only reaches [Listener.onError] here (FAILURES.md 9); a feed with no listings to show
     * is reported (listings.result.missing).
     */
    fun load() {
        val cfg = config ?: run {
            SellwildFailures.log(
                code = SellwildFailureCode.FEED_SETUP_MISSING,
                component = SellwildFailureComponent.FEED,
                severity = SellwildFailureSeverity.ERROR,
                message = "load() called before setup()",
            )
            listener?.onError("SellwildFeedView.load() called before setup()")
            return
        }
        loadJob?.cancel()
        loadJob = scope.launch {
            refreshLayout.isRefreshing = true
            val client = apiClient(context)
            val result = client.fetchListings(cfg)
            result.onSuccess { response ->
                // After the primary fetch, optionally disperse geo-based
                // secondary listings into the feed before rendering. When the
                // integration is off, no state resolves, or the secondary fetch
                // fails/404s, the primary feed renders unchanged.
                listings = applyLocalizedDispersion(cfg, client, response.listings)
                refreshLayout.isRefreshing = false
                loadSucceeded = true
                if (listings.isEmpty()) {
                    SellwildFailures.log(
                        code = SellwildFailureCode.LISTINGS_RESULT_MISSING,
                        component = SellwildFailureComponent.FEED,
                        severity = SellwildFailureSeverity.WARN,
                        message = "the feed got no listings",
                        url = cfg.effectiveListingsUrl,
                    )
                }
                adapter.rebuild(cfg)
                listener?.onLoad()
                // Reliable "listings bound" signal (count == 0 ⇒ empty/header-only).
                listener?.onFeedReady(listings.size)
            }.onFailure { t ->
                refreshLayout.isRefreshing = false
                listener?.onError(t.message ?: "Failed to load listings")
            }
        }
    }

    /**
     * Resolve the localized-listings integration and, when active with a
     * resolvable state, fetch the state-keyed secondary cache and merge it into
     * [primary] (every Nth slot). Returns [primary] unchanged on skip/failure.
     */
    private suspend fun applyLocalizedDispersion(
        config: SellwildConfig,
        client: SellwildAPIClient,
        primary: List<SellwildListing>,
    ): List<SellwildListing> {
        val integration = SellwildLocalizedListings.resolve(config) ?: return primary
        val everyN = SellwildLocalizedListings.everyN(integration.frequency)
        if (everyN <= 0) return primary
        val state = SellwildLocalizedListings.resolveState(integration, SellwildGeoStore.current?.state)
            ?: return primary
        val url = SellwildLocalizedListings.buildCacheUrl(integration, state)
        return client.fetchCacheListings(url).fold(
            onSuccess = { secondary -> SellwildLocalizedListings.merge(primary, secondary, everyN) },
            // SellwildAPIClient.fetchCacheListings already logged it (localized.*): log once.
            onFailure = { primary },
        )
    }

    /** Force a re-fetch. Wired to SwipeRefreshLayout. */
    fun refresh() = load()

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startLayoutSelfHealIfEnabled()
        // Self-heal the "config arrived late / detached mid-load during a fast
        // scroll" race: if we have a config but no successful load yet (and none
        // in flight), (re)start the load on re-attach. Deduped by load()'s own
        // loadJob cancel, so a normal setup()+load() isn't double-fetched.
        if (config != null && !loadSucceeded && loadJob?.isActive != true) {
            load()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopLayoutSelfHeal()
        // Cancel only the in-flight fetch — NOT the whole scope. `scope.cancel()`
        // is terminal (the scope is a val, never recreated), so cancelling it on a
        // transient detach during fast scroll permanently killed the loader: the
        // in-flight load was dropped with no onLoad/onError, and every later
        // load()/refresh() no-op'd on the dead scope. onAttachedToWindow re-drives
        // an incomplete load instead.
        loadJob?.cancel()
    }

    /**
     * Tear the feed down: destroy every child [SellwildAdView] — including rows
     * parked in the RecyclerView cache / pool, not just attached ones — so their
     * refresh loops stop and stop holding the Activity, then cancel loading and
     * drop references. Call from the host's `onDestroy` / `onDestroyView`. With
     * `MOBILE_PAUSE_REFRESH_DETACHED=false`, detaching alone does NOT stop the
     * ad rows' refresh. Terminal: the feed can't be reused afterwards.
     */
    fun destroy() {
        stopLayoutSelfHeal()
        loadJob?.cancel()
        loadJob = null
        scope.cancel()
        adapter.destroyAdRows()
        recycler.adapter = null
        listener = null
        config = null
        listings = emptyList()
    }

    // ── Layout self-heal (default OFF; see [layoutSelfHeal]) ──────────────────
    private var selfHealListener: android.view.ViewTreeObserver.OnGlobalLayoutListener? = null

    private fun isLayoutSelfHealEnabled(): Boolean =
        layoutSelfHeal || AdFlags.layoutSelfHeal(remoteObject(config?.remoteJson))

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
     * measure + layout to fill the parent. Converges once sized.
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

    // -----------------------------------------------------------------
    // Row scheduler (FeedSchedule)
    // -----------------------------------------------------------------

    /**
     * The rows for the loaded listings. COL1 ad tokens with no zone are dropped and reported
     * once per schedule and zones (feed.ad_zone.missing), not again on every refresh.
     */
    private fun buildRows(cfg: SellwildConfig): List<FeedRow> {
        val bannerZone = FeedSchedule.bannerZone(cfg.mobileBannerZid, cfg.bannerZid, cfg.bottomBannerZid)
        return FeedSchedule.build(schedule, listings, cfg.mobileZids, bannerZone) { SellwildGpid.resolveBase(cfg.remoteJson, it) }
            .reportedOncePer("feed|$schedule|${cfg.mobileZids.joinToString(",")}|$bannerZone")
    }

    // -----------------------------------------------------------------
    // Adapter
    // -----------------------------------------------------------------

    private inner class RowAdapter : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        private var rows: List<FeedRow> = listOf(FeedRow.Header)

        // Every ad row this adapter created, attached or not (RecyclerView's
        // cache / pool hold detached ones), so destroy() can reach them all.
        private val adRows = mutableSetOf<AdRowView>()

        fun rebuild(cfg: SellwildConfig) {
            rows = buildRows(cfg)
            notifyDataSetChanged()
        }

        override fun getItemCount(): Int = rows.size

        override fun getItemViewType(position: Int): Int = when (rows[position]) {
            is FeedRow.Header -> TYPE_HEADER
            is FeedRow.Listing -> TYPE_LISTING
            is FeedRow.GamAd -> TYPE_GAM
            is FeedRow.DirectAd -> TYPE_DIRECT
            is FeedRow.Banner -> TYPE_BANNER
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            return when (viewType) {
                TYPE_HEADER -> HeaderHolder(HeaderView(parent.context))
                TYPE_LISTING -> ListingHolder(ListingCardView(parent.context, SellwildE2EIds.LISTING_CARD))
                TYPE_GAM, TYPE_DIRECT -> AdHolder(AdRowView(parent.context, AdSize.MREC_300x250).also { adRows += it })
                TYPE_BANNER -> AdHolder(AdRowView(parent.context, AdSize.BANNER_320x50).also { adRows += it })
                else -> {
                    // Unreachable by construction (getItemViewType maps every row). It used to
                    // throw and crash the host; an empty row is reported instead.
                    SellwildFailures.log(
                        code = SellwildFailureCode.FEED_VIEW_TYPE_INVALID,
                        component = SellwildFailureComponent.FEED,
                        severity = SellwildFailureSeverity.ERROR,
                        message = "unknown view type $viewType",
                    )
                    EmptyHolder(View(parent.context))
                }
            }
        }

        fun destroyAdRows() {
            adRows.forEach { it.destroyAd() }
            adRows.clear()
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            val cfg = config ?: return
            bindRow(holder, rows[position], position, cfg)
        }

        private fun bindRow(holder: RecyclerView.ViewHolder, row: FeedRow, position: Int, cfg: SellwildConfig) = when (row) {
            is FeedRow.Header -> (holder as HeaderHolder).view.bind(cfg, colors, ::openUrl)
            is FeedRow.Listing -> (holder as ListingHolder).view.bind(row.listing, colors.price) { handleFeedListingTap(cfg, it) }
            // MREC can house-backfill with a full-width listing card (same as
            // organic listings) when no CMS image is set; a 320x50 banner is
            // too small for a card, so it gets none.
            is FeedRow.Ad -> {
                val house = if (row is FeedRow.Banner) null else FeedSchedule.houseListing(listings, rows, position)
                (holder as AdHolder).view.bind(
                    config = cfg,
                    zoneId = row.zoneId,
                    gpid = row.gpid,
                    priceColor = colors.price,
                    onImpression = ::onAdImpression,
                    onHouseImpression = ::onHouseAdImpression,
                    onClick = ::onAdClick,
                    houseListing = house,
                    onListingTap = { handleFeedListingTap(cfg, it) },
                    onRowResize = ::onAdRowResize,
                    surfaceGuard = firstAdViewedGuard,
                )
            }
        }
    }

    private class HeaderHolder(val view: HeaderView) : RecyclerView.ViewHolder(view)
    private class ListingHolder(val view: ListingCardView) : RecyclerView.ViewHolder(view)
    private class AdHolder(val view: AdRowView) : RecyclerView.ViewHolder(view)
    private class EmptyHolder(view: View) : RecyclerView.ViewHolder(view)

    private fun onAdImpression(zoneId: String) {
        listener?.onAdImpression(zoneId)
    }

    private fun onHouseAdImpression(zoneId: String) {
        listener?.onHouseAdImpression(zoneId)
    }

    private fun onAdClick(zoneId: String) {
        listener?.onAdClicked(zoneId)
    }

    /** Route a listing tap (organic card OR an ad-row full-width fallback card)
     *  through the host hook, falling back to opening the listing URL. */
    private fun handleFeedListingTap(cfg: SellwildConfig, listing: SellwildListing) {
        val handled = listener?.onListingTap(listing) ?: false
        if (!handled) openUrl(listing.tapUrl(cfg.partnerCode, cfg.bhTag))
    }

    /**
     * An ad row settled to a new height after the initial layout — a paid fill,
     * a no-fill, or the no-fill full-width fallback card morph. A child's own
     * requestLayout() doesn't make a WRAP_CONTENT RecyclerView re-measure its
     * total height, so in embedded mode (scrollEnabled = false) the height we
     * emitted at first layout goes stale and the host under-sizes the container
     * (last item clipped) until a full re-layout — e.g. detach/re-attach when the
     * user opens a listing and returns. Force the recycler to re-measure, then
     * re-emit the settled height on the next frame (reportContentHeight dedupes).
     */
    private fun onAdRowResize() {
        recycler.requestLayout()
        recycler.post { reportContentHeight() }
    }

    private fun openUrl(url: String?) {
        // http/https only — listing/CMS URLs are untrusted; don't launch an
        // arbitrary scheme via ACTION_VIEW.
        val uri = SellwildSafeUrl.external(url)
        if (uri == null) {
            if (!url.isNullOrEmpty()) {
                logOpenUrl(SellwildFailureCode.FEED_OPEN_URL_INVALID, message = "the listing or partner URL is not http(s)")
                listener?.onError("Refused to open non-http(s) URL")
            }
            return
        }
        try {
            CustomTabsIntent.Builder().build().launchUrl(context, uri)
        } catch (t: Throwable) {
            logOpenUrl(SellwildFailureCode.FEED_OPEN_URL_EXCEPTION, error = t, url = url)
            listener?.onError("Failed to open URL: ${t.message}")
        }
    }

    private fun logOpenUrl(code: String, message: String? = null, error: Throwable? = null, url: String? = null) {
        SellwildFailures.log(
            code = code,
            component = SellwildFailureComponent.FEED,
            severity = SellwildFailureSeverity.WARN,
            error = error,
            message = message,
            url = url,
        )
    }

    // -----------------------------------------------------------------
    // Header (title + Powered by Sellwild)
    // -----------------------------------------------------------------

    private class HeaderView(context: Context) : LinearLayout(context) {
        private val titleView: TextView
        private val poweredByView: TextView

        init {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val pad = dp(context, 16)
            setPadding(pad, pad, pad, pad)
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )

            titleView = TextView(context).apply {
                layoutParams = LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                textSize = 18f
                setTypeface(typeface, Typeface.BOLD)
                isSingleLine = true
            }
            poweredByView = TextView(context).apply {
                layoutParams = LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                )
                textSize = 11f
                isSingleLine = true
                text = "Powered by Sellwild"
            }
            addView(titleView)
            addView(poweredByView)
        }

        fun bind(config: SellwildConfig, colors: FeedColors, openUrl: (String?) -> Unit) {
            titleView.text = config.title ?: "Marketplace"
            titleView.setTextColor(colors.title)
            poweredByView.setTextColor(colors.poweredBy)
            val partnerUrl = config.partnerUrl
            titleView.setOnClickListener(
                if (!partnerUrl.isNullOrEmpty()) View.OnClickListener { openUrl(partnerUrl) } else null
            )
            poweredByView.setOnClickListener { openUrl("https://sellwild.com") }
        }
    }

    // -----------------------------------------------------------------
    // Listing card (full-bleed photo, title, price, seller line)
    // -----------------------------------------------------------------

    /** A listing card. [e2eId]: its resource-id for UI tests ([SellwildE2EIds]); none in an ad row. */
    private class ListingCardView(context: Context, private val e2eId: String? = null) : LinearLayout(context) {
        private val photoView: ImageView
        private val titleView: TextView
        private val priceView: TextView
        private val sellerView: TextView
        private var imageJob: Job? = null

        init {
            orientation = VERTICAL
            val sidePad = dp(context, 16)
            val vertPad = dp(context, 8)
            setPadding(sidePad, vertPad, sidePad, vertPad)
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )

            val cardContainer = LinearLayout(context).apply {
                orientation = VERTICAL
                background = GradientDrawable().apply {
                    cornerRadius = dp(context, 12).toFloat()
                    setColor(Color.WHITE)
                }
                // Clip children (the full-bleed photo) to the rounded background
                // outline so the top corners round too — matches the iOS card
                // (cornerRadius + clipsToBounds). Without this the photo overpaints
                // the top corners and only the bottom (white bg) looks rounded.
                clipToOutline = true
                layoutParams = LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                )
            }

            photoView = ImageView(context).apply {
                layoutParams = LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(context, 200),
                )
                scaleType = ImageView.ScaleType.CENTER_CROP
                setBackgroundColor(Color.parseColor("#EEEEEE"))
            }

            val textPad = dp(context, 12)
            val textContainer = LinearLayout(context).apply {
                orientation = VERTICAL
                setPadding(textPad, textPad, textPad, textPad)
                layoutParams = LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                )
            }

            titleView = TextView(context).apply {
                textSize = 15f
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
                setTypeface(typeface, Typeface.BOLD)
                setTextColor(Color.parseColor("#111827"))
            }
            priceView = TextView(context).apply {
                textSize = 18f
                setTypeface(typeface, Typeface.BOLD)
                setPadding(0, dp(context, 4), 0, 0)
            }
            sellerView = TextView(context).apply {
                textSize = 11f
                setTextColor(Color.parseColor("#6B7280"))
                setPadding(0, dp(context, 6), 0, 0)
            }

            textContainer.addView(titleView)
            textContainer.addView(priceView)
            textContainer.addView(sellerView)

            cardContainer.addView(photoView)
            cardContainer.addView(textContainer)

            addView(cardContainer)
        }

        fun bind(listing: SellwildListing, priceColor: Int, onTap: (SellwildListing) -> Unit) {
            titleView.text = listing.title
            priceView.text = Format.price(listing.currency, listing.price)
            priceView.setTextColor(priceColor)
            sellerView.text = Format.seller(listing.user)
            setOnClickListener { onTap(listing) }
            isClickable = true
            isFocusable = true
            loadImage(listing.photos.firstOrNull()?.url)
        }

        override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
            super.onInitializeAccessibilityNodeInfo(info)
            SellwildE2EIds.apply(info, e2eId)
        }

        private fun loadImage(url: String?) {
            imageJob?.cancel()
            photoView.setImageDrawable(null)
            photoView.setBackgroundColor(Color.parseColor("#EEEEEE"))
            if (url.isNullOrEmpty()) return
            val cached = FeedImages.cached(url)
            if (cached != null) {
                photoView.setImageBitmap(cached)
                return
            }
            imageJob = imageScope.launch {
                val bmp = withContext(FeedImages.io) { FeedImages.load(url) }
                if (bmp != null) {
                    FeedImages.remember(url, bmp)
                    photoView.setImageBitmap(bmp)
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // Ad row (wraps SellwildAdView)
    // -----------------------------------------------------------------

    private class AdRowView(context: Context, private val size: AdSize) : FrameLayout(context) {
        private var adView: SellwildAdView? = null
        // Full-width listing fallback shown when the ad no-fills and no CMS house
        // IMAGE is configured — the SAME card as organic listings, so it's
        // pixel-identical, and it grows the row to its natural height.
        private val fallbackCard = ListingCardView(context)
        private var boundZoneId: String? = null
        private var houseListing: SellwildListing? = null
        // A CMS house IMAGE renders in-slot via the ad view (MREC), so when one is
        // configured we keep the fixed slot instead of the full-width card.
        private var hasHouseImage = false
        // Set by every bind() before the row's ad view exists, so they are always set
        // when an ad callback fires.
        private lateinit var onHouseImpression: (String) -> Unit
        private lateinit var onListingTap: (SellwildListing) -> Unit
        // Notifies the feed that this row's height changed so it can force the
        // recycler to re-measure and re-emit content height (embedded mode).
        private lateinit var onRowResize: () -> Unit
        private val slotPad = dp(context, 8)

        init {
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            setPadding(slotPad, slotPad, slotPad, slotPad)
            fallbackCard.visibility = GONE
            addView(
                fallbackCard,
                LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
            )
        }

        override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
            super.onInitializeAccessibilityNodeInfo(info)
            SellwildE2EIds.apply(info, SellwildE2EIds.FEED_AD)
        }

        private var priceColor = FeedTheme.PRICE

        fun bind(
            config: SellwildConfig,
            zoneId: String,
            gpid: String?,
            priceColor: Int,
            onImpression: (String) -> Unit,
            onHouseImpression: (String) -> Unit,
            onClick: (String) -> Unit,
            houseListing: SellwildListing?,
            onListingTap: (SellwildListing) -> Unit,
            onRowResize: () -> Unit,
            surfaceGuard: SellwildFirstAdViewedGuard,
        ) {
            this.houseListing = houseListing
            this.onHouseImpression = onHouseImpression
            this.onListingTap = onListingTap
            this.onRowResize = onRowResize
            this.priceColor = priceColor
            this.hasHouseImage =
                SellwildHouseAd.resolve(config.remoteJson, zoneId, size.width, size.height) != null

            val current = adView
            if (current != null && boundZoneId == zoneId) {
                // Reused for the same zone: keep the ad view (and its refresh
                // cadence). Keep gpidOverride current — the same zone can carry a
                // different occurrence suffix at a different feed position (the
                // in-flight creative's imp-ext is not rebuilt on reuse). Refresh
                // the fallback content if it's currently showing.
                current.gpidOverride = gpid
                if (fallbackCard.visibility == VISIBLE && houseListing != null) {
                    fallbackCard.bind(houseListing, priceColor, onListingTap)
                }
                return
            }
            boundZoneId = zoneId
            // Destroy the outgoing ad view before replacing it. This holder is
            // being rebound to a DIFFERENT zone, so the old view is finished —
            // without destroy() its refresh Handler keeps auctioning/impressing
            // for the old zone on a detached view (a leak + invalid traffic).
            current?.let {
                it.destroy()
                removeView(it)
            }
            val ad = SellwildAdView(context).apply {
                // Share the feed's surface guard so firstAdViewed fires once for
                // the whole feed, not once per ad row (web parity).
                firstAdViewedGuard = surfaceGuard
                layoutParams = LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER_HORIZONTAL,
                )
                // The feed owns the LISTING fallback (rendered full-width below);
                // the ad view only handles a house IMAGE backdrop in-slot.
                houseFallbackListing = null
                // Inherit ad-stack from CDN config so feed ads respect AD_STACK / AD_STACK_BY_ZONE
                adStackOverride = SellwildAdStack.resolve(config.remoteJson, zoneId, null)
                // Inject the feed-computed GPID (base, or base#n for a shared
                // base) before setup() so the prebidOnly imp-ext picks it up.
                gpidOverride = gpid
                listener = object : SellwildAdView.Listener {
                    override fun onAdLoaded(adView: SellwildAdView) {
                        // Paid creative filled — show the ad slot (shrink the row
                        // back if a fallback card had grown it).
                        showAdSlot(adView)
                    }
                    override fun onAdResize(adView: SellwildAdView, width: Int, height: Int) {
                        // The creative resized the slot (multi-size shrink to the
                        // won size, outstream video, or the capped native template).
                        // Re-measure the row so the feed height tracks the actual
                        // ad height instead of the reserved bounding box.
                        this@AdRowView.onRowResize()
                    }
                    override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                        onImpression(zoneId)
                    }
                    override fun onHouseAdImpression(adView: SellwildAdView, zoneId: String) {
                        // Fired when the ad view's own house IMAGE backdrop shows.
                        this@AdRowView.onHouseImpression(zoneId)
                    }
                    override fun onAdClicked(adView: SellwildAdView) { onClick(zoneId) }
                    override fun onAdFailed(adView: SellwildAdView, message: String) {
                        // No-fill. A CMS house image (if any) renders in-slot via the
                        // ad view; otherwise show the full-width listing fallback.
                        val house = this@AdRowView.houseListing
                        if (this@AdRowView.hasHouseImage || house == null) {
                            showAdSlot(adView)
                        } else {
                            showFallbackCard(adView, house, zoneId)
                        }
                    }
                }
                setup(config, size, zoneId)
            }
            adView = ad
            addView(ad)
            showAdSlot(ad)   // start on the fixed ad slot; swap to the card only on no-fill
            ad.load()
        }

        /** Destroy + detach the ad view; the next [bind] builds a fresh one. */
        fun destroyAd() {
            adView?.let {
                it.listener = null
                it.destroy()
                removeView(it)
            }
            adView = null
            boundZoneId = null
        }

        /** Show the fixed MREC ad slot (paid creative or in-slot house image). */
        private fun showAdSlot(ad: SellwildAdView) {
            setPadding(slotPad, slotPad, slotPad, slotPad)
            fallbackCard.visibility = GONE
            ad.visibility = VISIBLE
            requestLayout()
            onRowResize()
        }

        /** Swap to the full-width listing fallback and grow the row to fit it. The
         *  card carries its own 16dp/8dp insets, so zero the slot padding to match
         *  the organic listing rows exactly. */
        private fun showFallbackCard(ad: SellwildAdView, listing: SellwildListing, zoneId: String) {
            setPadding(0, 0, 0, 0)
            ad.visibility = GONE
            fallbackCard.bind(listing, priceColor, onListingTap)
            fallbackCard.visibility = VISIBLE
            onHouseImpression(zoneId)
            requestLayout()
            onRowResize()
        }
    }

    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_LISTING = 1
        private const val TYPE_GAM = 2
        private const val TYPE_DIRECT = 3
        private const val TYPE_BANNER = 4

        private val imageScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

        /** Builds the listings client for each load. Tests install one that answers in-process. */
        @Volatile
        internal var apiClient: (Context) -> SellwildAPIClient = ::SellwildAPIClient

        private fun dp(context: Context, value: Int): Int = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            context.resources.displayMetrics,
        ).toInt()
    }
}

/**
 * Listing photos for the feed's cards: a memory cache, and a loader that runs off the main
 * thread. A photo that cannot be had leaves the grey placeholder and is reported once per
 * load: feed.image.network when the download fails, feed.image.invalid when the URL is refused
 * (not http(s), or a data: URI without a payload), too large, or not an image. An Error from
 * the decoder (OutOfMemoryError on a huge photo) is feed.image.invalid too: the loads run in a
 * coroutine on the main thread, where an uncaught Error would kill the host app.
 */
internal object FeedImages {
    private val memory = LruCache<String, Bitmap>(32)

    private val streamDecoder: (URL) -> Bitmap? = { url -> url.openStream().use { BitmapFactory.decodeStream(it) } }
    private val bytesDecoder: (ByteArray) -> Bitmap? = { bytes -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }

    /** Where loads run. Tests run them in place. */
    @Volatile
    internal var io: CoroutineDispatcher = Dispatchers.IO

    /** Downloads and decodes a remote photo; null when the bytes are not an image. Tests replace it. */
    @Volatile
    internal var fetch: (URL) -> Bitmap? = streamDecoder

    /** Decodes inline (data: URI) bytes; null when they are not an image. Tests replace it. */
    @Volatile
    internal var decode: (ByteArray) -> Bitmap? = bytesDecoder

    fun cached(url: String): Bitmap? = memory.get(url)

    fun remember(url: String, bitmap: Bitmap) {
        memory.put(url, bitmap)
    }

    /** One photo, on [io]: a data: URI decodes inline (size-capped), an http(s) URL downloads. */
    fun load(url: String): Bitmap? = when (val source = HouseImages.source(url)) {
        is HouseImages.Source.Refused -> invalid(source.reason, url = source.url)
        is HouseImages.Source.Inline -> decodeInline(source.base64)
        is HouseImages.Source.Remote -> loadRemote(source.url, url)
    }

    private fun decodeInline(base64: String): Bitmap? {
        val bytes = try {
            Base64.decode(base64, Base64.DEFAULT)
        } catch (e: IllegalArgumentException) {
            return invalid("data URI is not base64", error = e)
        }
        if (bytes.size > SellwildSafeUrl.MAX_IMAGE_BYTES) return invalid("image over 8 MiB")
        val bitmap = try {
            decode(bytes)
        } catch (e: Throwable) {
            // Bytes under 8 MiB can still decode to a bitmap too big for memory (OutOfMemoryError).
            return invalid(NOT_DECODED, error = e)
        }
        return bitmap ?: invalid(NOT_DECODED)
    }

    private fun loadRemote(url: URL, text: String): Bitmap? {
        val bitmap = try {
            fetch(url)
        } catch (e: Exception) {
            SellwildFailures.log(
                code = SellwildFailureCode.FEED_IMAGE_NETWORK,
                component = SellwildFailureComponent.FEED,
                severity = SellwildFailureSeverity.WARN,
                error = e,
                url = text,
            )
            return null
        } catch (e: Error) {
            // The download finished but the photo decodes to a bitmap too big for memory
            // (OutOfMemoryError): the photo is the problem, not the network.
            return invalid(NOT_DECODED, url = text, error = e)
        }
        return bitmap ?: invalid(NOT_DECODED, url = text)
    }

    private fun invalid(message: String, url: String? = null, error: Throwable? = null): Bitmap? {
        SellwildFailures.log(
            code = SellwildFailureCode.FEED_IMAGE_INVALID,
            component = SellwildFailureComponent.FEED,
            severity = SellwildFailureSeverity.WARN,
            error = error,
            message = message,
            url = url,
        )
        return null
    }

    private const val NOT_DECODED = "image could not be decoded"

    /** Restores the seams and empties the cache. Tests only. */
    internal fun resetForTests() {
        io = Dispatchers.IO
        fetch = streamDecoder
        decode = bytesDecoder
        memory.evictAll()
    }
}

/**
 * Element ids on the feed's rows, so UI tests (the sample apps' Maestro flows, a partner's
 * UI Automator or Appium tests) can find them. They are listed in contracts/e2e/ids.json;
 * never rename one.
 *
 * UI Automator reads a view's id from its accessibility node (resource-id). An Android
 * resource name cannot hold a dot, so the row sets the node's id itself, as Compose's
 * testTagsAsResourceId does. Screen readers do not read it.
 */
internal object SellwildE2EIds {
    /** Each listing row of [SellwildFeedView]. */
    const val LISTING_CARD = "sw.listing.card"

    /** Each ad row of [SellwildFeedView]. */
    const val FEED_AD = "sw.feed.ad"

    /** Reports [id] as the resource-id of [info]. A null [id] leaves the node as it is. */
    fun apply(info: AccessibilityNodeInfo, id: String?) {
        if (id != null) info.viewIdResourceName = id
    }
}
