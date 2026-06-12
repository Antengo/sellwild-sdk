package com.sellwild.sdk

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.LruCache
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.browser.customtabs.CustomTabsIntent
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
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
class SellwildFeedView @JvmOverloads constructor(
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
        fun onAdClicked(zoneId: String) {}
        fun onLoad() {}
        fun onError(message: String) {}
    }

    var listener: Listener? = null

    private var config: SellwildConfig? = null
    private var schedule: String = DEFAULT_SCHEDULE
    private var listings: List<SellwildListing> = emptyList()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var loadJob: Job? = null

    private val refreshLayout: SwipeRefreshLayout
    private val recycler: RecyclerView
    private val adapter = RowAdapter()

    init {
        orientation = VERTICAL
        layoutParams = layoutParams ?: LayoutParams(
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

        refreshLayout.addView(recycler)
        addView(refreshLayout)
    }

    /** Attach a [SellwildConfig] without kicking off a fetch. */
    fun setup(config: SellwildConfig) {
        this.config = config
        this.schedule = (config.col1?.takeIf { it.isNotBlank() }
            ?: DEFAULT_SCHEDULE).uppercase()
        applyBackground(config)
        adapter.notifyDataSetChanged()
    }

    /** Fetch listings and render the feed. */
    fun load() {
        val cfg = config ?: run {
            listener?.onError("SellwildFeedView.load() called before setup()")
            return
        }
        loadJob?.cancel()
        loadJob = scope.launch {
            refreshLayout.isRefreshing = true
            val client = SellwildAPIClient(context)
            val result = client.fetchListings(cfg)
            refreshLayout.isRefreshing = false
            result.onSuccess { response ->
                listings = response.listings
                adapter.rebuild()
                listener?.onLoad()
            }.onFailure { t ->
                listener?.onError(t.message ?: "Failed to load listings")
            }
        }
    }

    /** Force a re-fetch. Wired to SwipeRefreshLayout. */
    fun refresh() = load()

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        scope.cancel()
    }

    private fun applyBackground(config: SellwildConfig) {
        val bg = parseColor(config.priceColor, fallback = Color.parseColor("#0A1F3D"))
        setBackgroundColor(bg)
        refreshLayout.setProgressBackgroundColorSchemeColor(bg)
    }

    // -----------------------------------------------------------------
    // Row scheduler
    // -----------------------------------------------------------------

    private sealed class Row {
        object Header : Row()
        data class Listing(val listing: SellwildListing) : Row()
        data class GamAd(val zoneId: String) : Row()
        data class DirectAd(val zoneId: String) : Row()
        data class Banner(val zoneId: String) : Row()
    }

    private fun buildRows(): List<Row> {
        val cfg = config ?: return listOf(Row.Header)
        val rows = mutableListOf<Row>(Row.Header)
        val listingsIterator = listings.iterator()
        val gamZones = cfg.mobileZids.toMutableList()
        val bannerZone = cfg.mobileBannerZid
            ?: cfg.bannerZid
            ?: cfg.bottomBannerZid
        var gamIdx = 0

        for (token in schedule) {
            when (token) {
                'L' -> if (listingsIterator.hasNext()) {
                    rows.add(Row.Listing(listingsIterator.next()))
                }
                'G' -> {
                    val zone = pickZone(gamZones, gamIdx++)
                    if (zone != null) rows.add(Row.GamAd(zone))
                }
                'D' -> {
                    val zone = pickZone(gamZones, gamIdx++)
                    if (zone != null) rows.add(Row.DirectAd(zone))
                }
                'B' -> {
                    if (!bannerZone.isNullOrEmpty()) rows.add(Row.Banner(bannerZone))
                }
                else -> { /* ignore unknown tokens for forward compat */ }
            }
        }
        return rows
    }

    private fun pickZone(zones: List<String>, idx: Int): String? {
        if (zones.isEmpty()) return null
        val z = zones[idx % zones.size]
        return z.takeIf { it.isNotEmpty() }
    }

    // -----------------------------------------------------------------
    // Adapter
    // -----------------------------------------------------------------

    private inner class RowAdapter : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        private var rows: List<Row> = listOf(Row.Header)

        fun rebuild() {
            rows = buildRows()
            notifyDataSetChanged()
        }

        override fun getItemCount(): Int = rows.size

        override fun getItemViewType(position: Int): Int = when (rows[position]) {
            is Row.Header -> TYPE_HEADER
            is Row.Listing -> TYPE_LISTING
            is Row.GamAd -> TYPE_GAM
            is Row.DirectAd -> TYPE_DIRECT
            is Row.Banner -> TYPE_BANNER
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            return when (viewType) {
                TYPE_HEADER -> HeaderHolder(HeaderView(parent.context))
                TYPE_LISTING -> ListingHolder(ListingCardView(parent.context))
                TYPE_GAM, TYPE_DIRECT -> AdHolder(AdRowView(parent.context, AdSize.MREC_300x250))
                TYPE_BANNER -> AdHolder(AdRowView(parent.context, AdSize.BANNER_320x50))
                else -> throw IllegalArgumentException("Unknown viewType=$viewType")
            }
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            val cfg = config ?: return
            when (val row = rows[position]) {
                is Row.Header -> (holder as HeaderHolder).view.bind(cfg, ::openUrl)
                is Row.Listing -> (holder as ListingHolder).view.bind(cfg, row.listing) { listing ->
                    val handled = listener?.onListingTap(listing) ?: false
                    if (!handled) openUrl(listing.tapUrl(cfg.partnerCode, cfg.bhTag))
                }
                is Row.GamAd -> (holder as AdHolder).view.bind(cfg, row.zoneId, ::onAdImpression, ::onAdClick)
                is Row.DirectAd -> (holder as AdHolder).view.bind(cfg, row.zoneId, ::onAdImpression, ::onAdClick)
                is Row.Banner -> (holder as AdHolder).view.bind(cfg, row.zoneId, ::onAdImpression, ::onAdClick)
            }
        }
    }

    private class HeaderHolder(val view: HeaderView) : RecyclerView.ViewHolder(view)
    private class ListingHolder(val view: ListingCardView) : RecyclerView.ViewHolder(view)
    private class AdHolder(val view: AdRowView) : RecyclerView.ViewHolder(view)

    private fun onAdImpression(zoneId: String) {
        listener?.onAdImpression(zoneId)
    }

    private fun onAdClick(zoneId: String) {
        listener?.onAdClicked(zoneId)
    }

    private fun openUrl(url: String?) {
        if (url.isNullOrEmpty()) return
        try {
            CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url))
        } catch (t: Throwable) {
            listener?.onError("Failed to open URL: ${t.message}")
        }
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

        fun bind(config: SellwildConfig, openUrl: (String?) -> Unit) {
            titleView.text = config.title ?: "Marketplace"
            titleView.setTextColor(parseColor(config.titleColor, fallback = Color.WHITE))
            poweredByView.setTextColor(
                parseColor(config.linkColor, fallback = Color.parseColor("#9CA3AF"))
            )
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

    private class ListingCardView(context: Context) : LinearLayout(context) {
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

        fun bind(config: SellwildConfig, listing: SellwildListing, onTap: (SellwildListing) -> Unit) {
            titleView.text = listing.title
            priceView.text = formatPrice(listing.currency, listing.price)
            priceView.setTextColor(parseColor(config.linkColor, fallback = Color.parseColor("#2563EB")))
            sellerView.text = formatSeller(listing.user)
            setOnClickListener { onTap(listing) }
            isClickable = true
            isFocusable = true
            loadImage(listing.photos.firstOrNull()?.url)
        }

        private fun loadImage(url: String?) {
            imageJob?.cancel()
            photoView.setImageDrawable(null)
            photoView.setBackgroundColor(Color.parseColor("#EEEEEE"))
            if (url.isNullOrEmpty()) return
            val cached = imageCache.get(url)
            if (cached != null) {
                photoView.setImageBitmap(cached)
                return
            }
            imageJob = imageScope.launch {
                val bmp = withContext(Dispatchers.IO) {
                    runCatching { decodeImage(url) }.getOrNull()
                }
                if (bmp != null) {
                    imageCache.put(url, bmp)
                    photoView.setImageBitmap(bmp)
                }
            }
        }

        private fun decodeImage(url: String): Bitmap? {
            if (url.startsWith("data:")) {
                val comma = url.indexOf(',')
                if (comma < 0) return null
                val payload = url.substring(comma + 1)
                val bytes = android.util.Base64.decode(payload, android.util.Base64.DEFAULT)
                return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
            return URL(url).openStream().use { BitmapFactory.decodeStream(it) }
        }

        private fun formatPrice(currency: String?, price: String?): String {
            val value = price?.toDoubleOrNull() ?: return ""
            val sym = when (currency?.uppercase()) {
                "USD", null -> "$"
                "EUR" -> "€"
                "GBP" -> "£"
                else -> "$"
            }
            return if (value % 1.0 == 0.0) "$sym${value.toInt()}" else "$sym${"%.2f".format(value)}"
        }

        private fun formatSeller(user: SellwildUser?): String {
            if (user == null) return "sellwild.com"
            val first = user.firstName.takeIf { it.isNotBlank() }?.uppercase() ?: "SELLER"
            val lastInit = user.lastName.takeIf { it.isNotBlank() }?.uppercase()?.firstOrNull()
            val name = if (lastInit != null) "$first $lastInit." else first
            return "$name  |  sellwild.com"
        }
    }

    // -----------------------------------------------------------------
    // Ad row (wraps SellwildAdView)
    // -----------------------------------------------------------------

    private class AdRowView(context: Context, private val size: AdSize) : FrameLayout(context) {
        private var adView: SellwildAdView? = null
        private var boundZoneId: String? = null

        init {
            layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            val pad = dp(context, 8)
            setPadding(pad, pad, pad, pad)
        }

        fun bind(
            config: SellwildConfig,
            zoneId: String,
            onImpression: (String) -> Unit,
            onClick: (String) -> Unit,
        ) {
            if (boundZoneId == zoneId && adView != null) return
            boundZoneId = zoneId
            removeAllViews()
            val ad = SellwildAdView(context).apply {
                layoutParams = LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER_HORIZONTAL,
                )
                listener = object : SellwildAdView.Listener {
                    override fun onAdLoaded(adView: SellwildAdView) {}
                    override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                        onImpression(zoneId)
                    }
                    override fun onAdClicked(adView: SellwildAdView) { onClick(zoneId) }
                    override fun onAdFailed(adView: SellwildAdView, message: String) {}
                }
                setup(config, size, zoneId)
            }
            adView = ad
            addView(ad)
            ad.load()
        }
    }

    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_LISTING = 1
        private const val TYPE_GAM = 2
        private const val TYPE_DIRECT = 3
        private const val TYPE_BANNER = 4

        private const val DEFAULT_SCHEDULE = "LLGLLGLLG"

        private val imageScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        private val imageCache = LruCache<String, Bitmap>(32)

        private fun dp(context: Context, value: Int): Int = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            context.resources.displayMetrics,
        ).toInt()

        private fun parseColor(value: String?, fallback: Int): Int {
            if (value.isNullOrEmpty()) return fallback
            return runCatching { Color.parseColor(value) }.getOrDefault(fallback)
        }
    }
}
