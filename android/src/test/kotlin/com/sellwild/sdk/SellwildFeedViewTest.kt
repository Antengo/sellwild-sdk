package com.sellwild.sdk

import android.app.Activity
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.sellwild.sdk.core.FeedTheme
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.factories.ListingsResponseFactory
import com.sellwild.sdk.factories.LocalizedListingsConfigFactory
import com.sellwild.sdk.factories.LocalizedListingsResponseFactory
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.gateCalls
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.Dispatchers
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.IOException
import java.util.Locale

/**
 * SellwildFeedView on Robolectric: setup, load and the listings client (answered in-process by
 * HttpStub), the COL1 rows, listing cards and their photos, ad rows and their no-fill fallback,
 * URL opening, and the layout hooks. Ad rows run SellwildAdView against the fake ad network.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildFeedViewTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private lateinit var events: CapturedEvents
    private lateinit var activity: Activity
    private val calls = FeedEvents()
    private val listingsUrl = "https://cache.sellwild.com/listings-img-data-sm-fixture"
    private val photo = "https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231.jpg"

    /** Every SellwildFeedView.Listener callback, as short text. */
    class FeedEvents : SellwildFeedView.Listener {
        val calls = mutableListOf<String>()
        var consumeTaps = false

        override fun onListingTap(listing: SellwildListing): Boolean {
            calls += "tap:${listing.id}"
            return consumeTaps
        }

        override fun onAdImpression(zoneId: String) {
            calls += "impression:$zoneId"
        }

        override fun onHouseAdImpression(zoneId: String) {
            calls += "house:$zoneId"
        }

        override fun onAdClicked(zoneId: String) {
            calls += "clicked:$zoneId"
        }

        override fun onLoad() {
            calls += "load"
        }

        override fun onFeedReady(listingCount: Int) {
            calls += "ready:$listingCount"
        }

        override fun onError(message: String) {
            calls += "error:$message"
        }

        override fun onContentHeightChanged(feedView: SellwildFeedView, heightDp: Int) {
            calls += "height"
        }
    }

    @Before
    fun setUp() {
        events = CapturedEvents().install()
        activity = newActivity()
        Locale.setDefault(Locale.US)
        SellwildFeedView.apiClient = { ctx -> SellwildAPIClient(ctx, Dispatchers.Unconfined) { } }
        FeedImages.io = Dispatchers.Unconfined
        FeedImages.fetch = { pixel() }
        FeedImages.decode = { pixel() }
        SellwildHouseAd.runner = { it.run() }
        SellwildHouseAd.download = { ByteArray(4) }
        SellwildHouseAd.decode = { pixel() }
    }

    private fun listing(id: String, vararg overrides: Pair<String, Any?>): JSONObject = ListingFactory.checked(mapOf("id" to id, *overrides))

    private fun body(vararg items: JSONObject): String = ListingsResponseFactory.withItems(*items).toString()

    private fun config(vararg overrides: Pair<String, Any?>): SellwildConfig =
        configWith("LISTINGS" to listingsUrl, "GAM" to "/1234/fixture", "AD_STACK" to "gamOnly", "COL1" to "L", *overrides)

    private fun feed(config: SellwildConfig? = config(), ctx: android.content.Context = activity, scroll: Boolean = false): SellwildFeedView =
        SellwildFeedView(ctx).apply {
            listener = calls
            scrollEnabled = scroll
            config?.let { setup(it) }
        }

    /** Loads [feed] with the listings cache answering [response] (and state caches [state]). */
    private fun load(feed: SellwildFeedView, response: StubResponse, state: StubResponse? = null) {
        HttpStub.install { url -> if (url.toString().startsWith(listingsUrl)) response else state }.use {
            feed.load()
            idle()
        }
        idleFor(50)
    }

    private fun show(feed: SellwildFeedView): FrameLayout = attach(activity, feed, 1080, 20_000, FrameLayout.LayoutParams(1080, ViewGroup.LayoutParams.WRAP_CONTENT)).also { idleFor(50) }

    private fun SellwildFeedView.recycler(): RecyclerView = (getChildAt(0) as SwipeRefreshLayout).getChildAt(0) as RecyclerView

    private fun SellwildFeedView.rows(): List<View> = recycler().let { r -> (0 until r.childCount).map(r::getChildAt) }

    private fun SellwildFeedView.types(): List<Int> = recycler().adapter!!.let { a -> (0 until a.itemCount).map(a::getItemViewType) }

    private fun View.texts(): List<String> = when (this) {
        is TextView -> listOf(text.toString())
        is ViewGroup -> childrenList().flatMap { it.texts() }
        else -> emptyList()
    }

    private fun View.adViews(): List<SellwildAdView> = when (this) {
        is SellwildAdView -> listOf(this)
        is ViewGroup -> childrenList().flatMap { it.adViews() }
        else -> emptyList()
    }

    private fun View.images(): List<ImageView> = when (this) {
        is ImageView -> listOf(this)
        is ViewGroup -> childrenList().flatMap { it.images() }
        else -> emptyList()
    }

    // ── Setup and load ───────────────────────────────────────────────────────

    @Test
    fun `load before setup is reported and heard`() {
        val feed = feed(config = null)

        feed.load()

        assertEquals(listOf("error:SellwildFeedView.load() called before setup()"), calls.calls)
        assertEquals("load() called before setup()", events.attributes(SellwildFailureCode.FEED_SETUP_MISSING).getString("msg"))
    }

    @Test
    fun `a load renders the header, listings and ad rows in COL1 order`() {
        val feed = feed(config("COL1" to "LGLB", "MOBILE_ZID" to jsonArrayOf("z1"), "MOBILE_BANNER_ZID" to "b1", "TITLE" to "Deals"))

        load(feed, StubResponse(200, body(listing("l1"), listing("l2"))))
        show(feed)

        assertEquals(listOf(0, 1, 2, 1, 4), feed.types())
        assertEquals(listOf("load", "ready:2"), calls.calls.filter { it != "height" })
        val header = feed.rows().first()
        assertEquals(listOf("Deals", "Powered by Sellwild"), header.texts())
        val card = feed.rows()[1]
        assertEquals(listOf("2021 Lexus UX UX 200", "$19315", "LOTLINX A.  |  sellwild.com"), card.texts())
        assertTrue(card.images().single().drawable is BitmapDrawable)
        // G is an MREC row, B a 320x50 banner row.
        assertEquals(listOf(300 to 250, 320 to 50), feed.rows().flatMap { it.adViews() }.map { it.gam().adSize!!.let { s -> s.width to s.height } })
        assertEquals(2, ads.network.gamLoads.size)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `an empty listings response renders the header only and is reported`() {
        val feed = feed()

        load(feed, StubResponse(200, ListingsResponseFactory.build().toString()))
        show(feed)

        assertEquals(listOf("load", "ready:0"), calls.calls.filter { it != "height" })
        val attributes = events.attributes(SellwildFailureCode.LISTINGS_RESULT_MISSING)
        assertEquals("the feed got no listings", attributes.getString("msg"))
        assertEquals("cache.sellwild.com", attributes.getString("host"))
    }

    @Test
    fun `a failed fetch reaches onError and is reported once, by the listings client`() {
        val feed = feed()

        load(feed, StubResponse(503))

        assertEquals(listOf("error:HTTP 503 from $listingsUrl"), calls.calls)
        assertEquals(listOf(SellwildFailureCode.LISTINGS_FETCH_HTTP), events.codes)
    }

    @Test
    fun `COL1 ad rows with no zone are dropped and reported once, not again on refresh`() {
        val feed = feed(config("COL1" to "LGB"))

        load(feed, StubResponse(200, body(listing("l1"))))
        load(feed, StubResponse(200, body(listing("l1"))))

        assertEquals(listOf(0, 1), feed.types())
        assertEquals(listOf(SellwildFailureCode.FEED_AD_ZONE_MISSING, SellwildFailureCode.FEED_AD_ZONE_MISSING), events.codes)
        assertEquals(
            setOf("COL1 G/D rows dropped: no MOBILE_ZID zone (1)", "COL1 B rows dropped: no banner zone (1)"),
            events.failures.map { it.getJSONObject("attributes").getString("msg") }.toSet(),
        )
        // Two logFailure calls before the gate, one per message: the refresh did not call again.
        assertEquals(2, gateCalls(SellwildFailureCode.FEED_AD_ZONE_MISSING))
    }

    @Test
    fun `the banner row falls back to BANNER_ZID, then BOTTOM_BANNER_ZID`() {
        val top = feed(config("COL1" to "B", "BANNER_ZID" to "top-1"))
        val bottom = feed(config("COL1" to "B", "BOTTOM_BANNER_ZID" to "bottom-1"))

        load(top, StubResponse(200, body(listing("l1"))))
        load(bottom, StubResponse(200, body(listing("l1"))))

        assertEquals(listOf(0, 4), top.types())
        assertEquals(listOf(0, 4), bottom.types())
    }

    @Test
    fun `colors that are not colors fall back and are reported once`() {
        val config = config("PRICE_COLOR" to "not-a-color", "LINK_COLOR" to "#12345")

        val feed = feed(config)
        feed.setup(config)

        assertEquals(FeedTheme.BACKGROUND, (feed.background as ColorDrawable).color)
        assertEquals(listOf(SellwildFailureCode.CONFIG_COLOR_INVALID, SellwildFailureCode.CONFIG_COLOR_INVALID), events.codes)
        // Each report carries Color.parseColor's exception: its name, and its text after the message.
        assertEquals(
            setOf(
                "PRICE_COLOR is not a color: not-a-color: Unknown color",
                "LINK_COLOR is not a color: #12345: Unknown color",
            ),
            events.failures.map { it.getJSONObject("attributes").getString("msg") }.toSet(),
        )
        assertEquals(
            listOf("IllegalArgumentException", "IllegalArgumentException"),
            events.failures.map { it.getJSONObject("attributes").getString("errName") },
        )
        // Two logFailure calls before the gate, one per color: the second setup() did not call again.
        assertEquals(2, gateCalls(SellwildFailureCode.CONFIG_COLOR_INVALID))
    }

    @Test
    fun `the default colors come from the config`() {
        val feed = feed(config("PRICE_COLOR" to "#112233"))

        assertEquals(0xFF112233.toInt(), (feed.background as ColorDrawable).color)
    }

    @Test
    fun `a localized cache is dispersed into the feed`() {
        SellwildGeoStore.current = null
        val localized = LocalizedListingsResponseFactory.build().toString()
        val feed = feed(config("COL1" to "LLLL", "LOCALIZED_LISTINGS" to LocalizedListingsConfigFactory.build(mapOf("frequency" to 50))))

        load(feed, StubResponse(200, body(listing("l1"), listing("l2"), listing("l3"), listing("l4"))), state = StubResponse(200, localized))
        show(feed)

        assertEquals(listOf("load", "ready:4"), calls.calls.filter { it != "height" })
        // Every 2nd slot is the state's listing.
        assertEquals("NCAA Tee", feed.rows()[2].texts().first())
        assertEquals("NCAA Tee", feed.rows()[4].texts().first())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a localized cache that is missing, off or has no state leaves the primary feed`() {
        val missing = feed(config("LOCALIZED_LISTINGS" to LocalizedListingsConfigFactory.build()))
        val off = feed(config("LOCALIZED_LISTINGS" to LocalizedListingsConfigFactory.build(mapOf("frequency" to 0))))
        val stateless = feed(config("LOCALIZED_LISTINGS" to LocalizedListingsConfigFactory.variant("no-force-state")))

        load(missing, StubResponse(200, body(listing("l1"))), state = StubResponse(404))
        load(off, StubResponse(200, body(listing("l1"))))
        load(stateless, StubResponse(200, body(listing("l1"))))

        assertEquals(listOf("load", "ready:1", "load", "ready:1", "load", "ready:1"), calls.calls)
        assertEquals(emptyList<String>(), events.codes)
    }

    // ── Opening URLs ─────────────────────────────────────────────────────────

    @Test
    fun `a listing tap goes to the host first, and opens the listing when the host does not take it`() {
        val feed = feed(config("COL1" to "L"))
        load(feed, StubResponse(200, body(listing("l1"))))
        show(feed)
        val card = feed.rows()[1]

        calls.consumeTaps = true
        card.performClick()
        assertNull(shadowOf(activity).nextStartedActivity)

        calls.consumeTaps = false
        card.performClick()

        assertEquals("https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1", shadowOf(activity).nextStartedActivity.data.toString())
        assertEquals(listOf("tap:l1", "tap:l1"), calls.calls.filter { it.startsWith("tap") })
    }

    @Test
    fun `a listing with nothing to open does nothing on tap and reports nothing`() {
        val feed = feed(config("COL1" to "L"))
        load(feed, StubResponse(200, body(listing("", "url" to null, "remote_url" to null, "dataSourceId" to null))))
        show(feed)

        feed.rows()[1].performClick()

        assertNull(shadowOf(activity).nextStartedActivity)
        assertEquals(listOf("tap:"), calls.calls.filter { it.startsWith("tap") })
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `the header opens the partner URL and sellwild_com`() {
        val feed = feed(config("PARTNER_URL" to "https://partner.example.com/"))
        load(feed, StubResponse(200, body(listing("l1"))))
        show(feed)
        val (title, powered) = (feed.rows().first() as ViewGroup).childrenList()

        title.performClick()
        assertEquals("https://partner.example.com/", shadowOf(activity).nextStartedActivity.data.toString())
        powered.performClick()
        assertEquals("https://sellwild.com", shadowOf(activity).nextStartedActivity.data.toString())
    }

    @Test
    fun `a header with no partner URL and no title is a plain Marketplace title`() {
        val feed = feed(SellwildConfig(partnerCode = "fixture", listingsUrl = listingsUrl, col1 = "L"))
        load(feed, StubResponse(200, body(listing("l1"))))
        show(feed)
        val title = (feed.rows().first() as ViewGroup).getChildAt(0)

        assertEquals("Marketplace", (title as TextView).text.toString())
        assertFalse(title.hasOnClickListeners())
    }

    @Test
    fun `a partner URL that is not http(s) is refused, reported and heard`() {
        val feed = feed(config("PARTNER_URL" to "market://details?id=com.partner"))
        load(feed, StubResponse(200, body(listing("l1"))))
        show(feed)

        (feed.rows().first() as ViewGroup).getChildAt(0).performClick()

        assertNull(shadowOf(activity).nextStartedActivity)
        assertEquals("error:Refused to open non-http(s) URL", calls.calls.last())
        assertEquals("the listing or partner URL is not http(s)", events.attributes(SellwildFailureCode.FEED_OPEN_URL_INVALID).getString("msg"))
    }

    @Test
    fun `a URL with no browser to open it is reported and heard`() {
        val feed = feed(config("COL1" to "L"), ctx = NoBrowserContext(activity))
        load(feed, StubResponse(200, body(listing("l1"))))
        show(feed)

        feed.rows()[1].performClick()

        assertEquals("error:Failed to open URL: No Activity found to handle Intent", calls.calls.last())
        val attributes = events.attributes(SellwildFailureCode.FEED_OPEN_URL_EXCEPTION)
        assertEquals("ActivityNotFoundException", attributes.getString("errName"))
        assertEquals("autos.lotlinx.com", attributes.getString("host"))
    }

    // ── Listing photos ───────────────────────────────────────────────────────

    private fun photoOf(vararg items: JSONObject): ImageView {
        val feed = feed(config("COL1" to "L".repeat(items.size)))
        load(feed, StubResponse(200, body(*items)))
        show(feed)
        return feed.rows()[1].images().single()
    }

    private fun photos(url: String): Pair<String, Any?> = "photos" to JSONArray().put(JSONObject().put("url", url))

    /** What reached the main thread's uncaught handler while [block] ran (the photo coroutines run there). */
    private fun uncaughtOnMain(block: () -> Unit): List<Throwable> {
        val main = Thread.currentThread()
        val previous = main.uncaughtExceptionHandler
        val caught = mutableListOf<Throwable>()
        main.setUncaughtExceptionHandler { _, e -> caught += e }
        try {
            block()
        } finally {
            main.uncaughtExceptionHandler = previous
        }
        return caught
    }

    @Test
    fun `a photo is fetched once, then served from memory`() {
        var fetches = 0
        FeedImages.fetch = { fetches++; pixel() }

        assertTrue(photoOf(listing("l1")).drawable is BitmapDrawable)
        assertTrue(photoOf(listing("l1")).drawable is BitmapDrawable)

        assertEquals(1, fetches)
    }

    @Test
    fun `a data URI photo decodes inline`() {
        assertTrue(photoOf(listing("l1", photos("data:image/png;base64,AAAA"))).drawable is BitmapDrawable)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a photo that fails to download is feed_image_network`() {
        FeedImages.fetch = { throw IOException("connection reset") }

        assertNull(photoOf(listing("l1")).drawable)

        val attributes = events.attributes(SellwildFailureCode.FEED_IMAGE_NETWORK)
        assertEquals("IOException", attributes.getString("errName"))
        assertEquals("antengo-listings.s3.us-west-2.amazonaws.com", attributes.getString("host"))
    }

    @Test
    fun `a photo that is not an image is feed_image_invalid`() {
        FeedImages.fetch = { null }

        assertNull(photoOf(listing("l1")).drawable)

        assertEquals("image could not be decoded", events.attributes(SellwildFailureCode.FEED_IMAGE_INVALID).getString("msg"))
    }

    @Test
    fun `inline photos that are not base64, too large or not images are feed_image_invalid`() {
        val refused = mutableListOf<String>()
        for ((url, decode) in listOf(
            "data:image/png;base64,=AAA" to { _: ByteArray -> pixel() },
            "data:image/png;base64," + "A".repeat(12 * 1024 * 1024) to { _: ByteArray -> pixel() },
            "data:image/png;base64,AAAA" to { _: ByteArray -> null },
            "data:image/png" to { _: ByteArray -> pixel() },
            "file:///sdcard/photo.jpg" to { _: ByteArray -> pixel() },
        )) {
            FeedImages.decode = decode
            assertNull(photoOf(listing("l-${url.length}", photos(url))).drawable)
            refused += events.failures.last().getJSONObject("attributes").getString("msg")
        }

        assertEquals(
            listOf("data URI is not base64: bad base-64", "image over 8 MiB", "image could not be decoded", "data URI without a comma", "not an http(s) URL"),
            refused,
        )
        assertTrue(events.codes.all { it == SellwildFailureCode.FEED_IMAGE_INVALID })
    }

    @Test
    fun `a photo too big to decode (an Error) keeps the placeholder and is feed_image_invalid, not a crash`() {
        FeedImages.fetch = { throw OutOfMemoryError("Failed to allocate a 268435468 byte allocation") }

        lateinit var photo: ImageView
        // On a device, an Error that reaches the main thread's handler kills the app.
        assertEquals(emptyList<Throwable>(), uncaughtOnMain { photo = photoOf(listing("l1")) })

        assertNull(photo.drawable)
        assertEquals(0xFFEEEEEE.toInt(), (photo.background as ColorDrawable).color)
        val attributes = events.attributes(SellwildFailureCode.FEED_IMAGE_INVALID)
        // The byte count is scrubbed to <n> by logFailure.
        assertEquals("image could not be decoded: Failed to allocate a <n> byte allocation", attributes.getString("msg"))
        assertEquals("OutOfMemoryError", attributes.getString("errName"))
        assertEquals("antengo-listings.s3.us-west-2.amazonaws.com", attributes.getString("host"))
    }

    @Test
    fun `an inline photo too big to decode (an Error) keeps the placeholder and is feed_image_invalid, not a crash`() {
        FeedImages.decode = { throw OutOfMemoryError("Failed to allocate a 268435468 byte allocation") }

        lateinit var photo: ImageView
        assertEquals(emptyList<Throwable>(), uncaughtOnMain { photo = photoOf(listing("l1", photos("data:image/png;base64,AAAA"))) })

        assertNull(photo.drawable)
        assertEquals(0xFFEEEEEE.toInt(), (photo.background as ColorDrawable).color)
        val attributes = events.attributes(SellwildFailureCode.FEED_IMAGE_INVALID)
        // The byte count is scrubbed to <n> by logFailure.
        assertEquals("image could not be decoded: Failed to allocate a <n> byte allocation", attributes.getString("msg"))
        assertEquals("OutOfMemoryError", attributes.getString("errName"))
    }

    @Test
    fun `a listing with no photo keeps the placeholder`() {
        assertNull(photoOf(listing("l1", "photos" to JSONArray())).drawable)
    }

    // ── Ad rows ──────────────────────────────────────────────────────────────

    private fun adFeed(vararg overrides: Pair<String, Any?>): SellwildFeedView {
        val feed = feed(config("COL1" to "LGG", "MOBILE_ZID" to jsonArrayOf("z1", "z2"), *overrides))
        load(feed, StubResponse(200, body(listing("l1"), listing("l2"), listing("l3"))))
        show(feed)
        return feed
    }

    @Test
    fun `an ad row forwards impressions and clicks, and resizes the feed`() {
        val feed = adFeed()
        val ad = feed.rows()[2].adViews().single()
        val adListener = checkNotNull(ad.listener)

        adListener.onAdLoaded(ad)
        adListener.onAdImpression(ad, "z1")
        adListener.onAdClicked(ad)
        adListener.onHouseAdImpression(ad, "z1")
        adListener.onAdResize(ad, 320, 50)
        idleFor(50)

        assertEquals(listOf("impression:z1", "clicked:z1", "house:z1"), calls.calls.filter { it.contains(":z") })
    }

    @Test
    fun `an MREC no-fill with no house image shows a full-width listing card, which the host can take`() {
        val feed = adFeed()
        val row = feed.rows()[2] as ViewGroup
        val ad = row.adViews().single()

        checkNotNull(ad.listener).onAdFailed(ad, "No fill.")
        idleFor(50)

        val card = row.getChildAt(0)
        assertEquals(View.VISIBLE, card.visibility)
        assertEquals(View.GONE, ad.visibility)
        assertEquals("house:z1", calls.calls.last { it.startsWith("house") })
        calls.consumeTaps = true
        card.performClick()
        assertTrue(calls.calls.last().startsWith("tap:"))

        checkNotNull(ad.listener).onAdLoaded(ad)
        assertEquals(View.GONE, card.visibility)
        assertEquals(View.VISIBLE, ad.visibility)
    }

    @Test
    fun `a no-fill with a CMS house image keeps the ad slot`() {
        val feed = adFeed("MOBILE_HOUSE_AD_IMAGE" to "https://cdn.sellwild.com/house/mrec.png")
        val row = feed.rows()[2] as ViewGroup
        val ad = row.adViews().single()

        checkNotNull(ad.listener).onAdFailed(ad, "No fill.")

        assertEquals(View.GONE, row.getChildAt(0).visibility)
        assertEquals(View.VISIBLE, ad.visibility)
    }

    @Test
    fun `a banner row has no listing fallback`() {
        val feed = feed(config("COL1" to "B", "MOBILE_BANNER_ZID" to "b1"))
        load(feed, StubResponse(200, body(listing("l1"))))
        show(feed)
        val row = feed.rows()[1] as ViewGroup
        val ad = row.adViews().single()

        checkNotNull(ad.listener).onAdFailed(ad, "No fill.")

        assertEquals(View.VISIBLE, ad.visibility)
        assertFalse(calls.calls.any { it.startsWith("house") })
    }

    @Test
    fun `rebinding a row keeps its ad for the same zone and replaces it for another`() {
        val feed = adFeed()
        val recycler = feed.recycler()
        val holder = checkNotNull(recycler.findViewHolderForAdapterPosition(2))
        val first = (holder.itemView as ViewGroup).adViews().single()
        val card = (holder.itemView as ViewGroup).getChildAt(0)

        // Before a no-fill the row keeps its ad slot when it is bound again.
        recycler.adapter!!.bindViewHolder(holder, 2)
        assertEquals(View.GONE, card.visibility)
        assertEquals(View.VISIBLE, first.visibility)

        checkNotNull(first.listener).onAdFailed(first, "No fill.")
        recycler.adapter!!.bindViewHolder(holder, 2)
        assertTrue((holder.itemView as ViewGroup).adViews().single() === first)
        assertEquals(View.VISIBLE, card.visibility)
        assertEquals(2, ads.network.gamLoads.size)
        // The refreshed fallback card still goes to the host on tap.
        calls.consumeTaps = true
        card.performClick()
        assertTrue(calls.calls.last().startsWith("tap:"))

        recycler.adapter!!.bindViewHolder(holder, 3)
        val second = (holder.itemView as ViewGroup).adViews().single()
        assertFalse(second === first)
        assertEquals(3, ads.network.gamLoads.size)
    }

    @Test
    fun `an unknown view type is reported and gets an empty row`() {
        val feed = feed()
        val recycler = feed.recycler()

        val holder = recycler.adapter!!.createViewHolder(recycler, 99)

        assertEquals(View::class.java, holder.itemView.javaClass)
        assertEquals("unknown view type 99", events.attributes(SellwildFailureCode.FEED_VIEW_TYPE_INVALID).getString("msg"))
    }

    // ── Layout hooks ─────────────────────────────────────────────────────────

    @Test
    fun `scrolling can be turned off for embedding and back on`() {
        val feed = feed(config(), scroll = true)
        val refresh = feed.getChildAt(0) as SwipeRefreshLayout

        feed.scrollEnabled = false
        assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, feed.recycler().layoutParams.height)
        assertFalse(refresh.isEnabled)

        feed.scrollEnabled = true
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, feed.recycler().layoutParams.height)
        assertTrue(refresh.isEnabled)
        assertTrue(feed.scrollEnabled)
    }

    @Test
    fun `the content height is reported when it changes, once per value`() {
        val feed = feed(config("COL1" to "LL"))

        load(feed, StubResponse(200, body(listing("l1"), listing("l2"))))
        show(feed)
        val reports = calls.calls.count { it == "height" }
        feed.recycler().requestLayout()
        idleFor(50)

        assertTrue(reports >= 1)
        assertEquals(reports, calls.calls.count { it == "height" })
        assertEquals((feed.recycler().measuredHeight / activity.resources.displayMetrics.density).toInt(), feed.contentHeightDp)
    }

    @Test
    fun `a feed attached before its load finished loads again, and one that loaded does not`() {
        val feed = feed(config("COL1" to "L"))
        HttpStub.install { StubResponse(200, body(listing("l1"))) }.use {
            val parent = show(feed)
            assertEquals(listOf("load", "ready:1"), calls.calls.filter { it != "height" })

            parent.removeView(feed)
            parent.addView(feed)
            idle()
        }

        assertEquals(listOf("load", "ready:1"), calls.calls.filter { it != "height" })
    }

    @Test
    fun `a detach cancels the load in flight, and the next attach retries it`() {
        val feed = feed(config = null)
        val parent = show(feed)
        feed.setup(config("COL1" to "L"))
        feed.load()

        parent.removeView(feed)
        idle()
        assertEquals(emptyList<String>(), calls.calls.filter { it != "height" })

        HttpStub.install { StubResponse(200, body(listing("l1"))) }.use {
            parent.addView(feed)
            idle()
        }
        assertEquals(listOf("load", "ready:1"), calls.calls.filter { it != "height" })
    }

    @Test
    fun `pull to refresh loads again`() {
        val feed = feed(config("COL1" to "L"))
        val refresh = feed.getChildAt(0) as SwipeRefreshLayout
        val listener = SwipeRefreshLayout::class.java.getDeclaredField("mListener").apply { isAccessible = true }.get(refresh) as SwipeRefreshLayout.OnRefreshListener

        HttpStub.install { StubResponse(200, body(listing("l1"))) }.use {
            listener.onRefresh()
            idle()
            feed.refresh()
            idle()
        }

        assertEquals(listOf("load", "ready:1", "load", "ready:1"), calls.calls)
    }

    @Test
    fun `self-heal lays out a feed its host left at 0x0`() {
        val feed = feed(config()).apply { layoutSelfHeal = true }
        load(feed, StubResponse(200, body(listing("l1"))))
        val parent = attach(activity, feed, lp = FrameLayout.LayoutParams(0, 0))

        feed.viewTreeObserver.dispatchOnGlobalLayout()

        assertEquals(parent.width, feed.width)
        parent.removeView(feed)
    }

    @Test
    fun `self-heal turns on from MOBILE_LAYOUT_SELF_HEAL, waits for a sized parent, and is off by default`() {
        val remote = feed(config("MOBILE_LAYOUT_SELF_HEAL" to "on"))
        load(remote, StubResponse(200, body(listing("l1"))))
        attach(activity, remote, width = 0, height = 0, lp = FrameLayout.LayoutParams(0, 0))
        remote.viewTreeObserver.dispatchOnGlobalLayout()
        assertEquals(0, remote.width)

        val sized = feed(config("MOBILE_LAYOUT_SELF_HEAL" to true))
        load(sized, StubResponse(200, body(listing("l1"))))
        attach(activity, sized, lp = FrameLayout.LayoutParams(300, 200))
        sized.viewTreeObserver.dispatchOnGlobalLayout()
        assertEquals(300, sized.width)

        val plain = feed(config = null)
        attach(activity, plain, lp = FrameLayout.LayoutParams(0, 0))
        plain.viewTreeObserver.dispatchOnGlobalLayout()
        assertEquals(0, plain.width)
    }

    @Test
    fun `a feed that is a window's root has no parent view to heal to`() {
        val feed = feed(config()).apply { layoutSelfHeal = true }
        load(feed, StubResponse(200, body(listing("l1"))))

        activity.windowManager.addView(feed, android.view.WindowManager.LayoutParams(0, 0))
        idleFor(50)
        assertTrue(feed.isAttachedToWindow)
        assertTrue(feed.parent !is View)
        val laidOut = feed.width to feed.height
        feed.viewTreeObserver.dispatchOnGlobalLayout()

        assertEquals(laidOut, feed.width to feed.height)
        activity.windowManager.removeView(feed)
    }

    @Test
    fun `a header laid out before setup stays empty`() {
        val feed = feed(config = null)

        show(feed)

        assertEquals(listOf(0), feed.types())
        assertEquals(listOf("", "Powered by Sellwild"), feed.rows().single().texts())
    }

    @Test
    fun `a config applied again redraws the header`() {
        val feed = feed(config("TITLE" to "One"))
        load(feed, StubResponse(200, body(listing("l1"))))
        show(feed)

        feed.setup(config("TITLE" to "Two"))
        idleFor(50)

        assertEquals("Two", feed.rows().first().texts().first())
    }

    // ── No listener, and a listener that overrides nothing ───────────────────

    @Test
    fun `a feed with no listener still loads, lays out, opens a listing and runs its ad rows`() {
        val feed = SellwildFeedView(activity).apply {
            scrollEnabled = false
            setup(config("COL1" to "LG", "MOBILE_ZID" to jsonArrayOf("z1"), "PARTNER_URL" to "market://details?id=com.partner"))
        }
        load(feed, StubResponse(200, body(listing("l1"), listing("l2"))))
        show(feed)
        val ad = feed.rows()[2].adViews().single()
        val adListener = checkNotNull(ad.listener)

        adListener.onAdImpression(ad, "z1")
        adListener.onAdClicked(ad)
        adListener.onHouseAdImpression(ad, "z1")
        feed.rows()[1].performClick()
        assertEquals("https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1", shadowOf(activity).nextStartedActivity.data.toString())
        (feed.rows().first() as ViewGroup).getChildAt(0).performClick()

        assertTrue(feed.contentHeightDp > 0)
        assertEquals(listOf(SellwildFailureCode.FEED_OPEN_URL_INVALID), events.codes)
    }

    @Test
    fun `a feed with no listener still reports a load before setup, a failed fetch and a URL with no browser`() {
        SellwildFeedView(activity).load()
        val failing = SellwildFeedView(activity).apply { setup(config()) }
        load(failing, StubResponse(503))
        val noBrowser = SellwildFeedView(NoBrowserContext(activity)).apply { setup(config("COL1" to "L", "LISTINGS" to "$listingsUrl-2")) }
        HttpStub.install { StubResponse(200, body(listing("l1"))) }.use {
            noBrowser.load()
            idle()
        }
        show(noBrowser)

        noBrowser.rows()[1].performClick()

        assertEquals(
            listOf(SellwildFailureCode.FEED_SETUP_MISSING, SellwildFailureCode.LISTINGS_FETCH_HTTP, SellwildFailureCode.FEED_OPEN_URL_EXCEPTION),
            events.codes,
        )
    }

    @Test
    fun `a fetch that fails with no message reaches onError with a default text`() {
        val feed = feed()

        HttpStub.install { throw java.net.SocketTimeoutException() }.use {
            feed.load()
            idle()
        }

        assertEquals(listOf("error:Failed to load listings"), calls.calls)
        assertEquals(listOf(SellwildFailureCode.LISTINGS_FETCH_TIMEOUT), events.codes)
    }

    @Test
    fun `a listener that overrides nothing takes every feed callback`() {
        val feed = feed(config("COL1" to "LG", "MOBILE_ZID" to jsonArrayOf("z1"), "PARTNER_URL" to "market://details?id=com.partner")).apply {
            listener = object : SellwildFeedView.Listener {}
        }
        load(feed, StubResponse(200, body(listing("l1"), listing("l2"))))
        show(feed)
        val ad = feed.rows()[2].adViews().single()
        val adListener = checkNotNull(ad.listener)

        adListener.onAdImpression(ad, "z1")
        adListener.onAdClicked(ad)
        adListener.onHouseAdImpression(ad, "z1")
        feed.rows()[1].performClick()
        (feed.rows().first() as ViewGroup).getChildAt(0).performClick()

        // The default onListingTap does not take the tap, so the SDK opens the listing.
        assertEquals("https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1", shadowOf(activity).nextStartedActivity.data.toString())
        assertEquals(listOf(SellwildFailureCode.FEED_OPEN_URL_INVALID), events.codes)
    }

    // ── More rows and layout cases ───────────────────────────────────────────

    @Test
    fun `a D token is a 300x250 ad row like G`() {
        val feed = feed(config("COL1" to "LDB", "MOBILE_ZID" to jsonArrayOf("z1"), "MOBILE_BANNER_ZID" to "b1"))

        load(feed, StubResponse(200, body(listing("l1"))))
        show(feed)

        assertEquals(listOf(0, 1, 3, 4), feed.types())
        assertEquals(listOf(300 to 250, 320 to 50), feed.rows().flatMap { it.adViews() }.map { it.gam().adSize!!.let { s -> s.width to s.height } })
    }

    @Test
    fun `the device geo's state picks the localized cache when none is forced`() {
        SellwildGeoStore.current = SellwildGeo(state = "GA")
        val localized = LocalizedListingsResponseFactory.build().toString()
        val feed = feed(config("COL1" to "LLLL", "LOCALIZED_LISTINGS" to LocalizedListingsConfigFactory.build(mapOf("forceState" to null, "frequency" to 50))))
        val asked = mutableListOf<String>()

        HttpStub.install { url ->
            if (url.toString().startsWith(listingsUrl)) {
                StubResponse(200, body(listing("l1"), listing("l2"), listing("l3"), listing("l4")))
            } else {
                asked += url.toString()
                StubResponse(200, localized)
            }
        }.use {
            feed.load()
            idle()
        }
        show(feed)

        assertEquals(1, asked.size)
        assertEquals("https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/sports-img-data-sm-webp-ga.json", asked.single())
        assertEquals("NCAA Tee", feed.rows()[2].texts().first())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a feed detached before it ever loaded has nothing to cancel`() {
        val feed = feed(config = null)
        val parent = show(feed)

        parent.removeView(feed)
        idle()

        assertEquals(emptyList<String>(), calls.calls.filter { it != "height" })
        assertEquals(emptyList<String>(), events.codes)
    }

    // ── Photo loaders ────────────────────────────────────────────────────────

    @Test
    fun `the default photo loaders decode a downloaded stream and inline bytes`() {
        FeedImages.resetForTests()
        val png = java.io.ByteArrayOutputStream().also { pixel().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        val file = java.io.File.createTempFile("photo", ".png").apply {
            deleteOnExit()
            writeBytes(png)
        }

        assertTrue(FeedImages.fetch(file.toURI().toURL()) != null)
        assertTrue(FeedImages.decode(png) != null)
    }
}
