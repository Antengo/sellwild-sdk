package com.sellwild.sdk

import android.content.Context
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.ResultCode
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.core.ListingsParser
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.support.NetworkBlockRule
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/**
 * SellwildAdView on its GAM paths (.both and .gamOnly), its lifecycle (pause, resume, detach,
 * self-heal, destroy) and its house backdrop, on Robolectric. The ad network is a fake, so every
 * GAM load and Prebid auction is recorded instead of sent.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildAdViewTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var events: CapturedEvents
    private val calls = AdEvents()

    private val gam = arrayOf<Pair<String, Any?>>("GAM" to "/1234/fixture")

    @Before
    fun capture() {
        events = CapturedEvents().install()
        // House images load in place, from bytes, never over the network.
        SellwildHouseAd.runner = { it.run() }
        SellwildHouseAd.download = { ByteArray(4) }
        SellwildHouseAd.decode = { pixel() }
    }

    private fun adView(
        config: SellwildConfig,
        size: AdSize = AdSize.MREC_300x250,
        zone: String? = "43",
        ctx: Context = context,
        configure: SellwildAdView.() -> Unit = {},
    ): SellwildAdView = SellwildAdView(ctx).apply {
        listener = calls
        configure()
        setup(config, size, zone)
    }

    private fun loadError(code: Int, message: String) = LoadAdError(code, message, "com.google.android.gms.ads", null, null)

    // ── Before setup ─────────────────────────────────────────────────────────

    @Test
    fun `load before setup is reported and heard, and does not crash`() {
        val view = SellwildAdView(context).apply { listener = calls }

        view.load()

        val attributes = events.attributes(SellwildFailureCode.AD_SETUP_MISSING)
        assertEquals("load() called before setup()", attributes.getString("msg"))
        assertEquals("error", attributes.getString("severity"))
        assertEquals(listOf("failed:SellwildAdView.load() called before setup()"), calls.calls)
        assertTrue(ads.network.gamLoads.isEmpty())
    }

    @Test
    fun `resume before setup is reported and does not crash`() {
        val view = SellwildAdView(context)

        view.resume()

        assertEquals("resume() called before setup()", events.attributes(SellwildFailureCode.AD_SETUP_MISSING).getString("msg"))
    }

    @Test
    fun `pause, detach and destroy before setup do nothing`() {
        val activity = newActivity()
        val view = SellwildAdView(activity)
        val parent = attach(activity, view)

        view.pause()
        parent.removeView(view)
        view.destroy()

        assertEquals(emptyList<String>(), events.codes)
    }

    // ── Setup ────────────────────────────────────────────────────────────────

    @Test
    fun `setup builds the GAM banner for every size, with the configured unit, and stamps the queue`() {
        val view = adView(configWith(*gam, "BANNER_SIZES" to jsonArrayOf("320x50", "728x90")))

        val banner = view.gam()
        assertEquals("/1234/fixture", banner.adUnitId)
        assertEquals(listOf("300x250", "320x50", "728x90"), banner.adSizes!!.map { "${it.width}x${it.height}" })
        val density = context.resources.displayMetrics.density
        assertEquals((728 * density).toInt(), banner.layoutParams.width)
        assertEquals((250 * density).toInt(), banner.layoutParams.height)
        assertEquals("minimal", SellwildEventQueue.shared(context).partnerCode)
        assertEquals(SellwildAdStack.BOTH, view.resolvedAdStack)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `setup honors the EVENTS_ENABLED kill switch`() {
        adView(configWith(*gam, "EVENTS_ENABLED" to false))

        assertEquals(false, SellwildEventQueue.shared(context).enabled)
    }

    @Test
    fun `no GAM unit falls back to the test unit and is reported once per config`() {
        val config = configWith()

        val first = adView(config, AdSize.BANNER_320x50)
        adView(config, AdSize.BANNER_320x50)

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_BANNER, first.gam().adUnitId)
        val attributes = events.attributes(SellwildFailureCode.AD_GAM_UNIT_MISSING)
        assertEquals("fatal", attributes.getString("severity"))
        assertEquals("no GAM ad unit configured; using the test unit /6499/example/banner", attributes.getString("msg"))
    }

    @Test
    fun `a JSON null GAM on a device is no unit, not the text null`() {
        val config = configFrom(AppConfigFactory.offSchema(mapOf("GAM" to JSONObject.NULL)))

        val view = adView(config)

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_ADAPTIVE, view.gam().adUnitId)
        events.single(SellwildFailureCode.AD_GAM_UNIT_MISSING)
    }

    @Test
    fun `the companion helper resolves the unit`() {
        val cdn = configWith("GAM" to "/99999/cdn/banner")

        assertEquals("/12345/typed", SellwildAdView.resolveGAMAdUnitID(cdn.copy(gamTag = "/12345/typed")))
        assertEquals("/99999/cdn/banner", SellwildAdView.resolveGAMAdUnitID(cdn))
        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_BANNER, SellwildAdView.resolveGAMAdUnitID(configWith(), AdSize.BANNER_320x50))
        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_ADAPTIVE, SellwildAdView.resolveGAMAdUnitID(configWith()))
        // The pure helper does not report: the view does, once, when it builds the banner.
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `remote config that does not parse resolves the test unit, and the parse is reported once`() {
        val config = SellwildConfig(partnerCode = "fixture", remoteJson = "{not json")

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_ADAPTIVE, SellwildAdView.resolveGAMAdUnitID(config))
        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_ADAPTIVE, SellwildAdView.resolveGAMAdUnitID(config))

        events.single(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE)
    }

    // ── Loading on .both and .gamOnly ────────────────────────────────────────

    @Test
    fun `gamOnly loads GAM at once, with no auction and no wait`() {
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly"))

        view.load()

        assertSame(view.gam(), ads.network.gamLoads.single())
        assertTrue(ads.network.bannerAuctions.isEmpty())
    }

    @Test
    fun `both without a zone loads GAM at once`() {
        val view = adView(configWith(*gam), zone = null)

        view.load()

        assertSame(view.gam(), ads.network.gamLoads.single())
    }

    @Test
    fun `both with Prebid ready runs the auction, and GAM loads when it finishes`() {
        ads.prebidReady(context)
        val view = adView(configWith(*gam, "MEDIANET" to JSONObject().put("cid", "c"), "GPID_BASE" to "/1/feed"))

        view.load()
        val auction = ads.network.bannerAuctions.single()
        auction.finish(ResultCode.SUCCESS)

        // Bidder params live server-side in the stored imp: no CMS key rides along as a
        // bidder (iOS parity), only the gpid.
        assertEquals(emptySet<String>() to "/1/feed", impExt(auction.unit.impOrtbConfig))
        assertSame(view.gam(), ads.network.gamLoads.single())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `both waits for Prebid init, and runs the auction when it comes up in time`() {
        val view = adView(configWith(*gam))

        view.load()
        idleFor(450)
        assertTrue(ads.network.bannerAuctions.isEmpty())
        ads.network.finishPrebidInit()
        idleFor(150)

        assertEquals(1, ads.network.bannerAuctions.size)
        assertTrue(ads.network.gamLoads.isEmpty())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `both loads GAM without Prebid after 8 waits, and reports the timeout once`() {
        val view = adView(configWith(*gam))

        view.load()
        idleFor(7 * 150)
        assertTrue(ads.network.gamLoads.isEmpty())
        idleFor(150)

        assertSame(view.gam(), ads.network.gamLoads.single())
        assertTrue(ads.network.bannerAuctions.isEmpty())
        val attributes = events.attributes(SellwildFailureCode.AD_PREBID_INIT_TIMEOUT)
        assertEquals("Prebid not ready after 8 waits; loading GAM without header bidding", attributes.getString("msg"))
        assertEquals("43", attributes.getString("zoneId"))
    }

    @Test
    fun `a pause during the cold-start wait makes resume load again`() {
        val view = adView(configWith(*gam))
        view.load()
        idleFor(150)

        view.pause()
        idleFor(2_000)
        assertTrue(ads.network.gamLoads.isEmpty())
        ads.network.finishPrebidInit()
        view.resume()

        assertEquals(1, ads.network.bannerAuctions.size)
    }

    // ── GAM events ───────────────────────────────────────────────────────────

    @Test
    fun `a GAM fill hides the house, reports the size, impression and render, and refreshes up to the cap`() {
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 2, "AD_REFRESH_INTERVAL" to 30_000))
        view.load()
        val listener = view.gam().adListener

        listener.onAdLoaded()

        assertEquals(listOf("loaded", "resize:300x250", "impression:43"), calls.calls)
        assertEquals(listOf("43"), events.named("adRenderSucceeded").map { it.getString("label") })
        assertEquals(1, events.named("firstAdViewed").size)

        idleFor(30_000)
        assertEquals(2, ads.network.gamLoads.size)
        listener.onAdLoaded()
        idleFor(30_000)
        assertEquals(3, ads.network.gamLoads.size)
        listener.onAdLoaded()
        idleFor(60_000)

        assertEquals(3, ads.network.gamLoads.size)
        assertEquals(1, events.named("firstAdViewed").size)
        assertEquals(3, events.named("adRenderSucceeded").size)
    }

    @Test
    fun `a sub-10-second interval is floored, and no refresh cap means no refresh`() {
        val capped = adView(configWith(*gam, "AD_STACK" to "gamOnly", "AD_REFRESH_MAX" to 1, "AD_REFRESH_INTERVAL" to 45))
        capped.load()
        capped.gam().adListener.onAdLoaded()
        idleFor(9_999)
        assertEquals(1, ads.network.gamLoads.size)
        idleFor(1)
        assertEquals(2, ads.network.gamLoads.size)

        val once = adView(configWith(*gam, "AD_STACK" to "gamOnly"), zone = "44")
        once.load()
        once.gam().adListener.onAdLoaded()
        idleFor(120_000)
        assertEquals(1, ads.network.gamLoads.count { it === once.gam() })
    }

    @Test
    fun `GAM no-fill is only adError and the house, never a failure`() {
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly", "MOBILE_HOUSE_AD_IMAGE" to IMAGE))
        view.load()

        view.gam().adListener.onAdFailedToLoad(loadError(3, "No fill."))

        assertEquals(listOf("failed:No fill.", "house:43"), calls.calls)
        assertEquals("No fill.", events.named("adError").single().getString("action"))
        assertEquals(View.VISIBLE, view.house()?.visibility)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a GAM load error other than no-fill is also reported, once`() {
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly"))
        view.load()

        view.gam().adListener.onAdFailedToLoad(loadError(2, "Network Error"))

        assertEquals(listOf("failed:Network Error"), calls.calls)
        assertEquals(1, events.named("adError").size)
        val attributes = events.attributes(SellwildFailureCode.AD_GAM_LOAD_EXCEPTION)
        assertEquals("GAM load error 2: Network Error", attributes.getString("msg"))
        assertEquals("warn", attributes.getString("severity"))
    }

    @Test
    fun `a GAM click reaches the listener and the click event`() {
        val view = adView(configWith(*gam))

        view.gam().adListener.onAdClicked()

        assertEquals(listOf("clicked"), calls.calls)
        assertEquals("43", events.named("click").single().getString("label"))
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    @Test
    fun `pause stops the refresh timer and resume restarts it`() {
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 3))
        view.load()
        view.gam().adListener.onAdLoaded()

        view.pause()
        idleFor(60_000)
        assertEquals(1, ads.network.gamLoads.size)

        view.resume()
        idleFor(30_000)
        assertEquals(2, ads.network.gamLoads.size)
    }

    @Test
    fun `a detached view pauses its refresh and resumes when attached again`() {
        val activity = newActivity()
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 3), ctx = activity)
        val parent = attach(activity, view)
        view.load()
        view.gam().adListener.onAdLoaded()

        parent.removeView(view)
        idleFor(60_000)
        assertEquals(1, ads.network.gamLoads.size)

        parent.addView(view)
        idleFor(30_000)
        assertEquals(2, ads.network.gamLoads.size)
    }

    @Test
    fun `a GAM load that lands after a detach does not re-arm refresh (origin 7a07be8)`() {
        val activity = newActivity()
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 3), ctx = activity)
        val parent = attach(activity, view)
        view.load()

        parent.removeView(view)
        view.gam().adListener.onAdLoaded()
        idleFor(60_000)
        assertEquals(1, ads.network.gamLoads.size)

        parent.addView(view)
        idleFor(30_000)
        assertEquals("the reattach restarts it", 2, ads.network.gamLoads.size)
    }

    @Test
    fun `with MOBILE_PAUSE_REFRESH_DETACHED off a detached view keeps refreshing`() {
        val activity = newActivity()
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 3, "MOBILE_PAUSE_REFRESH_DETACHED" to false), ctx = activity)
        val parent = attach(activity, view)
        view.load()
        view.gam().adListener.onAdLoaded()

        parent.removeView(view)
        idleFor(30_000)
        parent.addView(view)

        assertEquals(2, ads.network.gamLoads.size)
    }

    @Test
    fun `self-heal lays out a view its host left at 0x0, and stops when detached`() {
        val activity = newActivity()
        val view = adView(configWith(*gam), ctx = activity) { layoutSelfHeal = true }
        val parent = attach(activity, view, lp = FrameLayout.LayoutParams(0, 0))

        view.viewTreeObserver.dispatchOnGlobalLayout()

        assertEquals(parent.width, view.width)
        assertEquals(parent.height, view.height)
        parent.removeView(view)
        view.layout(0, 0, 0, 0)
        view.viewTreeObserver.dispatchOnGlobalLayout()
        assertEquals(0, view.width)
    }

    @Test
    fun `self-heal turns on from MOBILE_LAYOUT_SELF_HEAL, and a view already sized is left alone`() {
        val activity = newActivity()
        val view = adView(configWith(*gam, "MOBILE_LAYOUT_SELF_HEAL" to true), ctx = activity)
        attach(activity, view, lp = FrameLayout.LayoutParams(400, 300))

        view.viewTreeObserver.dispatchOnGlobalLayout()

        assertEquals(400, view.width)
        assertEquals(300, view.height)
    }

    @Test
    fun `self-heal waits for a parent with a size`() {
        val activity = newActivity()
        val view = adView(configWith(*gam), ctx = activity) { layoutSelfHeal = true }
        attach(activity, view, width = 0, height = 0, lp = FrameLayout.LayoutParams(0, 0))

        view.viewTreeObserver.dispatchOnGlobalLayout()

        assertEquals(0, view.width)
    }

    @Test
    fun `self-heal is off by default and off before setup`() {
        val activity = newActivity()
        val unset = SellwildAdView(activity)
        attach(activity, unset, lp = FrameLayout.LayoutParams(0, 0))
        unset.viewTreeObserver.dispatchOnGlobalLayout()
        assertEquals(0, unset.width)

        val view = adView(configWith(*gam), ctx = activity)
        attach(activity, view, lp = FrameLayout.LayoutParams(0, 0))
        view.viewTreeObserver.dispatchOnGlobalLayout()
        assertEquals(0, view.width)
    }

    @Test
    fun `destroy stops the refresh timer for good`() {
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 3))
        view.load()
        view.gam().adListener.onAdLoaded()

        view.destroy()
        idleFor(120_000)

        assertEquals(1, ads.network.gamLoads.size)
    }

    // ── House backdrop ───────────────────────────────────────────────────────

    private val IMAGE = "https://cdn.sellwild.com/house/mrec.png"

    @Test
    fun `a CMS house image sits behind the creative, and its tap opens the click URL`() {
        val activity = newActivity()
        val view = adView(configWith(*gam, "MOBILE_HOUSE_AD_IMAGE" to IMAGE, "MOBILE_HOUSE_AD_URL" to "https://sellwild.com/house"), ctx = activity)

        view.load()
        idle()
        val house = checkNotNull(view.house())
        house.performClick()

        assertSame(house, view.getChildAt(0))
        assertEquals(View.VISIBLE, house.visibility)
        assertEquals("https://sellwild.com/house", shadowOf(activity).nextStartedActivity.data.toString())
        view.gam().adListener.onAdLoaded()
        assertEquals(View.GONE, house.visibility)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a house click URL that is not http(s) is refused and reported`() {
        val activity = newActivity()
        val view = adView(configWith(*gam, "MOBILE_HOUSE_AD_IMAGE" to IMAGE, "MOBILE_HOUSE_AD_URL" to "market://details?id=com.x"), ctx = activity)
        view.load()

        checkNotNull(view.house()).performClick()

        assertNull(shadowOf(activity).nextStartedActivity)
        val attributes = events.attributes(SellwildFailureCode.HOUSE_OPEN_URL_INVALID)
        assertEquals("the house ad click URL is not http(s)", attributes.getString("msg"))
        assertEquals("43", attributes.getString("zoneId"))
    }

    @Test
    fun `a house image with no click URL does nothing on tap`() {
        val view = adView(configWith(*gam, "MOBILE_HOUSE_AD_IMAGE" to IMAGE))
        view.load()

        checkNotNull(view.house()).performClick()

        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a house tap with no browser is reported`() {
        val view = adView(
            configWith(*gam, "MOBILE_HOUSE_AD_IMAGE" to IMAGE, "MOBILE_HOUSE_AD_URL" to "https://sellwild.com/house"),
            ctx = NoBrowserContext(newActivity()),
        )
        view.load()

        checkNotNull(view.house()).performClick()

        val attributes = events.attributes(SellwildFailureCode.HOUSE_OPEN_URL_EXCEPTION)
        assertEquals("ActivityNotFoundException", attributes.getString("errName"))
        assertEquals("sellwild.com", attributes.getString("host"))
    }

    @Test
    fun `a house tap whose browser launch throws an Error is reported, not a crash`() {
        val view = adView(
            configWith(*gam, "MOBILE_HOUSE_AD_IMAGE" to IMAGE, "MOBILE_HOUSE_AD_URL" to "https://sellwild.com/house"),
            ctx = ErrorOnStartContext(newActivity(), NoClassDefFoundError("androidx/browser/customtabs/CustomTabsIntent")),
        )
        view.load()

        checkNotNull(view.house()).performClick()

        val attributes = events.attributes(SellwildFailureCode.HOUSE_OPEN_URL_EXCEPTION)
        assertEquals("NoClassDefFoundError", attributes.getString("errName"))
        assertEquals("sellwild.com", attributes.getString("host"))
    }

    @Test
    fun `an MREC with no house image backfills with the feed's listing, which opens its tap URL`() {
        val activity = newActivity()
        val listing = ListingsParser.parseListing(ListingFactory.checked())
        val view = adView(configWith(*gam), ctx = activity) { houseFallbackListing = listing }

        view.load()
        checkNotNull(view.house()).performClick()

        assertEquals(View.VISIBLE, view.house()?.visibility)
        assertEquals(listing.tapUrl("fixture", null), shadowOf(activity).nextStartedActivity.data.toString())
    }

    @Test
    fun `a banner gets no listing backfill, and house ads turned off hide an existing backdrop`() {
        val listing = ListingsParser.parseListing(ListingFactory.checked())
        val banner = adView(configWith(*gam), AdSize.BANNER_320x50) { houseFallbackListing = listing }
        banner.load()
        assertNull(banner.house())

        val view = adView(configWith(*gam, "MOBILE_HOUSE_AD_IMAGE" to IMAGE))
        view.load()
        assertNotNull(view.house())
        view.setup(configWith(*gam, "MOBILE_HOUSE_AD_IMAGE" to IMAGE, "MOBILE_HOUSE_AD_ENABLED" to false), AdSize.MREC_300x250, "43")
        view.load()

        assertEquals(View.GONE, view.house()?.visibility)
    }

    @Test
    fun `a no-fill with no house shows nothing and records no house impression`() {
        val view = adView(configWith(*gam, "AD_STACK" to "gamOnly"))
        view.load()

        view.gam().adListener.onAdFailedToLoad(loadError(3, "No fill."))

        assertEquals(listOf("failed:No fill."), calls.calls)
        assertNull(view.house())
    }

    @Test
    fun `a view that is a window's root has no parent view to heal to`() {
        val activity = newActivity()
        val view = adView(configWith(*gam), ctx = activity) { layoutSelfHeal = true }

        activity.windowManager.addView(view, WindowManager.LayoutParams(0, 0))
        idleFor(50)
        assertTrue(view.isAttachedToWindow)
        assertTrue(view.parent !is View)
        val laidOut = view.width to view.height
        view.viewTreeObserver.dispatchOnGlobalLayout()

        assertEquals(laidOut, view.width to view.height)
        activity.windowManager.removeView(view)
    }
}
