package com.sellwild.sdk

import android.content.Context
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.ads.LoadAdError
import com.sellwild.prebid.NativeAdUnit
import com.sellwild.prebid.ResultCode
import com.sellwild.prebid.api.exceptions.AdException
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.failures.SellwildLog
import com.sellwild.sdk.support.NetworkBlockRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * SellwildAdView with no listener, with a listener that overrides nothing, with the SDK debug
 * flag on, and with callbacks that arrive late (after destroy, after a stack switch, after a
 * detach), on Robolectric with a fake ad network.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildAdViewCallbacksTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var events: CapturedEvents
    private val calls = AdEvents()

    private val gamOnly = arrayOf<Pair<String, Any?>>("AD_STACK" to "gamOnly", "GAM" to "/1234/fixture")
    private val prebidOnly = arrayOf<Pair<String, Any?>>("AD_STACK" to "prebidOnly", "GAM" to "/1234/fixture")
    private val native = arrayOf<Pair<String, Any?>>("AD_STACK" to "prebidOnly", "NATIVE_ENABLED" to true, "GAM" to "/1234/fixture")
    private val image = "https://cdn.sellwild.com/house/mrec.png"

    @Before
    fun capture() {
        events = CapturedEvents().install()
        SellwildHouseAd.runner = { it.run() }
        SellwildHouseAd.download = { ByteArray(4) }
        SellwildHouseAd.decode = { pixel() }
    }

    /** A view set up with no listener. */
    private fun bare(config: SellwildConfig, zone: String? = "43", ctx: Context = context): SellwildAdView =
        SellwildAdView(ctx).apply { setup(config, AdSize.MREC_300x250, zone) }

    private fun loadError(code: Int, message: String) = LoadAdError(code, message, "com.google.android.gms.ads", null, null)

    private fun finishNative(result: ResultCode, cacheId: String? = null) {
        val fetch = ads.network.nativeFetches.last()
        cacheId?.let { fetch.adObject.putString(NativeAdUnit.BUNDLE_KEY_CACHE_ID, it) }
        fetch.finish(result)
        idle()
    }

    // ── No listener ──────────────────────────────────────────────────────────

    @Test
    fun `with no listener a GAM slot still tracks its fill, no-fill, house and click`() {
        val view = bare(configWith(*gamOnly, "MOBILE_HOUSE_AD_IMAGE" to image))
        view.load()
        val adListener = view.gam().adListener

        adListener.onAdLoaded()
        adListener.onAdFailedToLoad(loadError(0, "Internal error."))
        adListener.onAdClicked()

        assertEquals(1, events.named("adRenderSucceeded").size)
        assertEquals("Internal error.", events.named("adError").single().getString("action"))
        assertEquals(1, events.named("click").size)
        assertEquals(View.VISIBLE, view.house()?.visibility)
        assertEquals("GAM load error 0: Internal error.", events.attributes(SellwildFailureCode.AD_GAM_LOAD_EXCEPTION).getString("msg"))
    }

    @Test
    fun `with no listener a Prebid slot still tracks its render, failure and click`() {
        val view = bare(configWith(*prebidOnly))

        view.prebidEvents.onAdLoaded(FakeBanner(context, wonWidth = 320, wonHeight = 50))
        view.prebidEvents.onAdFailed(view.prebid(), AdException(AdException.SERVER_ERROR, "503"))
        view.prebidEvents.onAdClicked(view.prebid())

        assertEquals(1, events.named("adRenderSucceeded").size)
        assertEquals(1, events.named("adError").size)
        assertEquals(1, events.named("click").size)
        events.single(SellwildFailureCode.AD_PREBID_RENDER_EXCEPTION)
    }

    @Test
    fun `with no listener a native slot still tracks its fill, click and no-fill`() {
        ads.prebidReady(context)
        val view = bare(configWith(*native))
        val ad = FakeNativeContent()
        ads.network.nativeAds["cache-1"] = ad

        view.load()
        finishNative(ResultCode.SUCCESS, "cache-1")
        checkNotNull(ad.events).onAdClicked()
        finishNative(ResultCode.NO_BIDS)

        assertEquals(1, events.named("adRenderSucceeded").size)
        assertEquals(1, events.named("click").size)
        assertEquals(1, events.named("adError").size)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `with no listener a slot with no zone is still reported, on each stack`() {
        bare(configWith(*prebidOnly), zone = null).load()
        bare(configWith(*native), zone = null).load()

        assertEquals(listOf(SellwildFailureCode.AD_ZONE_MISSING, SellwildFailureCode.AD_ZONE_MISSING), events.codes)
        assertEquals(listOf("banner", "native"), events.failures.map { it.getString("label") })
    }

    // ── A listener that overrides nothing ────────────────────────────────────

    @Test
    fun `a listener that overrides nothing takes every callback and changes nothing`() {
        val view = bare(configWith(*gamOnly, "MOBILE_HOUSE_AD_IMAGE" to image)).apply {
            listener = object : SellwildAdView.Listener {}
        }
        view.load()
        val adListener = view.gam().adListener

        adListener.onAdLoaded()
        adListener.onAdFailedToLoad(loadError(3, "No fill."))
        adListener.onAdClicked()

        assertEquals(1, events.named("adRenderSucceeded").size)
        assertEquals(1, events.named("adError").size)
        assertEquals(1, events.named("click").size)
        assertEquals(emptyList<String>(), events.codes)
    }

    // ── Debug trace ──────────────────────────────────────────────────────────

    @Test
    fun `with debug on the first view, a Prebid render and a Prebid no-fill are traced`() {
        SellwildFailures.setContext { it.copy(debug = true) }
        val gam = bare(configWith(*gamOnly))
        val prebid = bare(configWith(*prebidOnly), zone = "44")

        gam.load()
        gam.gam().adListener.onAdLoaded()
        prebid.prebidEvents.onAdLoaded(FakeBanner(context))
        prebid.prebidEvents.onAdFailed(prebid.prebid(), AdException(AdException.NO_BIDS, "There are no bids"))

        assertTrue(SellwildLog.enabled)
        assertTrue(failures.lines.contains("[firstAdViewed] fired once for this ad surface (zone 43)"))
        assertTrue(failures.lines.contains("[prebidOnly] rendered — zone 44"))
        assertTrue(failures.lines.any { it.startsWith("[prebidOnly] no fill — zone 44: No bids") })
        assertEquals(emptyList<String>(), events.codes)
    }

    // ── Setup variants ───────────────────────────────────────────────────────

    @Test
    fun `setup without a zone id is a zone-less GAM slot whose events carry an empty zone`() {
        val view = SellwildAdView(context).apply {
            listener = calls
            setup(configWith("GAM" to "/1234/fixture"), AdSize.MREC_300x250)
        }

        view.load()
        view.gam().adListener.onAdLoaded()

        assertSame(view.gam(), ads.network.gamLoads.single())
        assertTrue(ads.network.bannerAuctions.isEmpty())
        assertEquals(listOf("loaded", "resize:300x250", "impression:"), calls.calls)
        assertEquals("", events.named("adRenderSucceeded").single().getString("label"))
    }

    @Test
    fun `a GPID override from the feed wins over the remote base on the both auction`() {
        ads.prebidReady(context)
        val view = SellwildAdView(context).apply {
            gpidOverride = "/1/feed#2"
            setup(configWith("GAM" to "/1234/fixture", "GPID_BASE" to "/1/feed"), AdSize.MREC_300x250, "43")
        }

        view.load()

        assertEquals("/1/feed#2", impExt(ads.network.bannerAuctions.single().unit.impOrtbConfig).second)
    }

    @Test
    fun `a second load keeps the one house backdrop`() {
        val view = bare(configWith(*gamOnly, "MOBILE_HOUSE_AD_IMAGE" to image))

        view.load()
        val house = view.house()
        view.load()

        assertSame(house, view.house())
        assertEquals(1, view.childrenList().count { it is SellwildHouseAdView })
    }

    // ── Late callbacks ───────────────────────────────────────────────────────

    @Test
    fun `a GAM fill that arrives after destroy reports no size`() {
        val view = bare(configWith(*gamOnly)).apply { listener = calls }
        view.load()
        val adListener = view.gam().adListener

        view.destroy()
        adListener.onAdLoaded()

        assertEquals(listOf("loaded", "impression:43"), calls.calls)
    }

    @Test
    fun `a Prebid render that arrives after destroy reports its size and resizes nothing`() {
        val view = bare(configWith(*prebidOnly)).apply { listener = calls }
        val banner = view.prebid()
        val reserved = banner.layoutParams.height

        view.destroy()
        view.prebidEvents.onAdLoaded(FakeBanner(context, wonWidth = 320, wonHeight = 50))

        assertEquals(listOf("loaded", "resize:320x50", "impression:43"), calls.calls)
        assertEquals(reserved, banner.layoutParams.height)
    }

    @Test
    fun `renders past the refresh cap with no banner to stop are still heard`() {
        val view = bare(configWith(*prebidOnly, "AD_REFRESH_MAX_MOBILE" to 1)).apply { listener = calls }

        view.prebidEvents.onAdLoaded(null)
        view.prebidEvents.onAdLoaded(null)

        assertEquals(2, calls.calls.count { it == "loaded" })
    }

    // ── Keep-creative refresh on .prebidOnly ─────────────────────────────────

    private val keep = arrayOf<Pair<String, Any?>>(
        *prebidOnly,
        "AD_REFRESH_MAX_MOBILE" to 3,
        "MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH" to true,
    )

    @Test
    fun `two resumes in a row leave one pending refresh`() {
        ads.prebidReady(context)
        val activity = newActivity()
        val view = bare(configWith(*keep), ctx = activity)
        attach(activity, view)
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.resume()
        view.resume()
        idleFor(30_000)

        assertEquals(2, ads.network.renderingLoads.size)
    }

    @Test
    fun `a pending refresh does not load a view that was detached without pausing`() {
        ads.prebidReady(context)
        val activity = newActivity()
        val view = bare(configWith(*keep, "MOBILE_PAUSE_REFRESH_DETACHED" to false), ctx = activity)
        val parent = attach(activity, view)
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.resume()
        parent.removeView(view)
        idleFor(30_000)

        assertEquals(1, ads.network.renderingLoads.size)
    }

    @Test
    fun `a pending refresh does nothing once the view switched to GAM`() {
        ads.prebidReady(context)
        val activity = newActivity()
        val view = bare(configWith(*keep), ctx = activity)
        attach(activity, view)
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.resume()
        view.setup(configWith(*gamOnly), AdSize.MREC_300x250, "43")
        idleFor(30_000)

        assertEquals(1, ads.network.renderingLoads.size)
        assertTrue(view.childrenList().none { it is com.sellwild.prebid.api.rendering.BannerView })
    }
}
