package com.sellwild.sdk

import android.content.Context
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.NativeAdUnit
import com.sellwild.prebid.ResultCode
import com.sellwild.prebid.api.exceptions.AdException
import com.sellwild.prebid.api.rendering.BannerView
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.support.NetworkBlockRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * SellwildAdView on .prebidOnly: the Prebid-rendered banner, native, outstream video checks,
 * resume and the teardown between stacks, on Robolectric with a fake ad network.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildAdViewPrebidTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var events: CapturedEvents
    private val calls = AdEvents()

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

    private fun adView(config: SellwildConfig, size: AdSize = AdSize.MREC_300x250, zone: String? = "43", ctx: Context = context): SellwildAdView =
        SellwildAdView(ctx).apply {
            listener = calls
            setup(config, size, zone)
        }

    // ── The Prebid-rendered banner ───────────────────────────────────────────

    @Test
    fun `setup builds the rendering banner with its refresh delay, sizes and GPID`() {
        val view = adView(
            configWith(*prebidOnly, "AD_REFRESH_MAX_MOBILE" to 3, "AD_REFRESH_INTERVAL" to 45_000, "BANNER_SIZES" to jsonArrayOf("320x50"), "GPID_BASE" to "/1/feed"),
        )

        val banner = view.prebid()
        assertEquals(45_000, banner.autoRefreshDelayInMs)
        assertTrue(com.sellwild.prebid.AdSize(320, 50) in banner.additionalSizes)
        assertTrue(com.sellwild.prebid.AdSize(728, 90) !in banner.additionalSizes)
        assertEquals("/1/feed", impExt(banner.impOrtbConfig).second)
        assertEquals(SellwildAdStack.PREBID_ONLY, view.resolvedAdStack)
    }

    @Test
    fun `prebidOnly with Prebid ready loads the banner at once`() {
        ads.prebidReady(context)
        val view = adView(configWith(*prebidOnly))

        view.load()

        assertSame(view.prebid(), ads.network.renderingLoads.single())
        assertTrue(ads.network.gamLoads.isEmpty())
    }

    @Test
    fun `prebidOnly loads anyway after the cold-start wait, and reports the timeout`() {
        val view = adView(configWith(*prebidOnly))

        view.load()
        idleFor(7 * 150)
        assertTrue(ads.network.renderingLoads.isEmpty())
        idleFor(150)

        assertEquals(1, ads.network.renderingLoads.size)
        assertEquals(
            "Prebid not ready after 8 waits; loading the Prebid banner anyway",
            events.attributes(SellwildFailureCode.AD_PREBID_INIT_TIMEOUT).getString("msg"),
        )
    }

    @Test
    fun `prebidOnly without a zone is reported and heard, and builds nothing`() {
        val view = adView(configWith(*prebidOnly), zone = null)

        view.load()

        assertTrue(view.childrenList().none { it is BannerView || it is AdManagerAdView })
        assertEquals(listOf("failed:SellwildAdView resolved to PREBID_ONLY but has no zoneId; Prebid rendering requires a configId."), calls.calls)
        val event = events.single(SellwildFailureCode.AD_ZONE_MISSING)
        assertEquals("banner", event.getString("label"))
        assertEquals("PREBID_ONLY needs a zone id (the Prebid configId)", event.getJSONObject("attributes").getString("msg"))
    }

    @Test
    fun `a Prebid render tightens the slot to the won size and reports it`() {
        val view = adView(configWith(*prebidOnly, "MOBILE_HOUSE_AD_IMAGE" to image))
        view.load()

        view.prebidEvents.onAdLoaded(FakeBanner(context, wonWidth = 320, wonHeight = 50))

        val density = context.resources.displayMetrics.density
        assertEquals((320 * density).toInt(), view.prebid().layoutParams.width)
        assertEquals((50 * density).toInt(), view.prebid().layoutParams.height)
        assertEquals(listOf("loaded", "resize:320x50", "impression:43"), calls.calls)
        assertEquals(View.GONE, view.house()?.visibility)
        assertEquals(1, events.named("adRenderSucceeded").size)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a render with no size reported falls back to the primary, and a null banner is tolerated`() {
        val view = adView(configWith(*prebidOnly))

        view.prebidEvents.onAdLoaded(null)

        assertEquals(listOf("loaded", "resize:300x250", "impression:43"), calls.calls)
    }

    @Test
    fun `Prebid's own refresh stops once its renders pass the cap`() {
        val view = adView(configWith(*prebidOnly, "AD_REFRESH_MAX_MOBILE" to 2))
        view.load()
        val banner = FakeBanner(context)

        repeat(2) { view.prebidEvents.onAdLoaded(banner) }
        assertEquals(0, banner.stopped)
        view.prebidEvents.onAdLoaded(banner)

        assertEquals(1, banner.stopped)
    }

    @Test
    fun `a Prebid no-fill is adError and the house, not a failure`() {
        val view = adView(configWith(*prebidOnly, "MOBILE_HOUSE_AD_IMAGE" to image))
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.prebidEvents.onAdFailed(view.prebid(), AdException(AdException.NO_BIDS, "There are no bids"))

        assertEquals("failed:No bids: There are no bids", calls.calls[calls.calls.size - 2])
        assertEquals("house:43", calls.calls.last())
        assertEquals(View.VISIBLE, view.house()?.visibility)
        assertEquals("No bids: There are no bids", events.named("adError").single().getString("action"))
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a Prebid render failure other than no-fill is also reported, once`() {
        val view = adView(configWith(*prebidOnly))

        view.prebidEvents.onAdFailed(view.prebid(), AdException(AdException.SERVER_ERROR, "503"))

        assertEquals(listOf("failed:Server error: 503"), calls.calls)
        val attributes = events.attributes(SellwildFailureCode.AD_PREBID_RENDER_EXCEPTION)
        assertEquals("Server error: 503", attributes.getString("msg"))
        assertEquals("AdException", attributes.getString("errName"))
        assertEquals(1, events.named("adError").size)
    }

    @Test
    fun `a Prebid failure with no exception is reported as such`() {
        val view = adView(configWith(*prebidOnly))

        view.prebidEvents.onAdFailed(null, null)

        assertEquals(listOf("failed:Prebid ad failed"), calls.calls)
        assertEquals("no exception", events.attributes(SellwildFailureCode.AD_PREBID_RENDER_EXCEPTION).getString("msg"))
    }

    @Test
    fun `a Prebid click reaches the listener, and display and close change nothing`() {
        val view = adView(configWith(*prebidOnly))

        view.prebidEvents.onAdDisplayed(null)
        view.prebidEvents.onAdClicked(null)
        view.prebidEvents.onAdClosed(null)

        assertEquals(listOf("clicked"), calls.calls)
        assertEquals(1, events.named("click").size)
    }

    // ── Outstream video checks ───────────────────────────────────────────────

    @Test
    fun `video winning a banner-only zone keeps placementMismatch, is reported, and is muted`() {
        val view = adView(configWith(*prebidOnly))
        val banner = FakeBanner(context, response = FakeBid(video = true))
        val player = FakeVideo(context)
        banner.addView(android.widget.FrameLayout(context).apply { addView(player) })
        banner.addView(View(context))

        view.prebidEvents.onAdLoaded(banner)

        assertEquals("43", events.named("placementMismatch").single().getString("label"))
        assertEquals("a video creative won a banner-only zone", events.attributes(SellwildFailureCode.AD_PLACEMENT_INVALID).getString("msg"))
        assertEquals(listOf(true), player.mutes)
    }

    @Test
    fun `video on a video zone plays with sound only when the zone enables it`() {
        val loud = adView(configWith(*prebidOnly, "VIDEO_ENABLED" to true, "VIDEO_SOUND_ENABLED" to true))
        val quiet = adView(configWith(*prebidOnly, "VIDEO_ENABLED" to true), zone = "44")
        val loudPlayer = FakeVideo(context)
        val quietPlayer = FakeVideo(context)

        loud.prebidEvents.onAdLoaded(FakeBanner(context, response = FakeBid(video = true)).apply { addView(loudPlayer) })
        quiet.prebidEvents.onAdLoaded(FakeBanner(context, response = FakeBid(video = true)).apply { addView(quietPlayer) })

        assertEquals(listOf(false), loudPlayer.mutes)
        assertEquals(listOf(true), quietPlayer.mutes)
        assertTrue(events.named("placementMismatch").isEmpty())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a bid that cannot be read is reported and treated as not video`() {
        val view = adView(configWith(*prebidOnly))
        val player = FakeVideo(context)

        view.prebidEvents.onAdLoaded(FakeBanner(context, response = FakeBid(error = IllegalStateException("no winning bid"))).apply { addView(player) })

        assertEquals("IllegalStateException", events.attributes(SellwildFailureCode.AD_BID_INSPECT_EXCEPTION).getString("errName"))
        assertEquals(emptyList<Boolean>(), player.mutes)
        assertEquals(listOf("loaded", "resize:300x250", "impression:43"), calls.calls)
    }

    @Test
    fun `a bid reader that throws an Error is reported and treated as not video, not a crash`() {
        val view = adView(configWith(*prebidOnly))
        val player = FakeVideo(context)

        // A fork built without isVideo() fails with NoSuchMethodError, an Error, not an exception.
        view.prebidEvents.onAdLoaded(FakeBanner(context, response = FakeBid(error = NoSuchMethodError("isVideo"))).apply { addView(player) })

        assertEquals("NoSuchMethodError", events.attributes(SellwildFailureCode.AD_BID_INSPECT_EXCEPTION).getString("errName"))
        assertEquals(emptyList<Boolean>(), player.mutes)
        assertEquals(listOf("loaded", "resize:300x250", "impression:43"), calls.calls)
    }

    @Test
    fun `a banner bid is left alone`() {
        val view = adView(configWith(*prebidOnly))
        val player = FakeVideo(context)

        view.prebidEvents.onAdLoaded(FakeBanner(context, response = FakeBid(video = false)).apply { addView(player) })

        assertEquals(emptyList<Boolean>(), player.mutes)
    }

    // ── Resume on .prebidOnly ────────────────────────────────────────────────

    @Test
    fun `resume re-issues the Prebid load by default`() {
        ads.prebidReady(context)
        val view = adView(configWith(*prebidOnly, "AD_REFRESH_MAX_MOBILE" to 3))
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.pause()
        view.resume()

        assertEquals(2, ads.network.renderingLoads.size)
    }

    @Test
    fun `resume keeps a rendered creative with the flag on and refreshes it later, only while attached`() {
        ads.prebidReady(context)
        val activity = newActivity()
        val view = adView(configWith(*prebidOnly, "AD_REFRESH_MAX_MOBILE" to 3, "MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH" to true), ctx = activity)
        val parent = attach(activity, view)
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.pause()
        view.resume()
        assertEquals(1, ads.network.renderingLoads.size)
        idleFor(30_000)
        assertEquals(2, ads.network.renderingLoads.size)

        view.pause()
        view.resume()
        parent.removeView(view)
        idleFor(30_000)
        assertEquals(2, ads.network.renderingLoads.size)
    }

    @Test
    fun `resume keeps the creative but does not refresh past the cap`() {
        ads.prebidReady(context)
        val view = adView(configWith(*prebidOnly, "AD_REFRESH_MAX_MOBILE" to 1, "MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH" to "yes"))
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.pause()
        view.resume()
        idleFor(60_000)

        assertEquals(1, ads.network.renderingLoads.size)
    }

    @Test
    fun `a reattach starts no new auction once the refresh cap is spent (origin d218ba2)`() {
        ads.prebidReady(context)
        val view = adView(configWith(*prebidOnly, "AD_REFRESH_MAX_MOBILE" to 1))
        view.load()
        repeat(2) { view.prebidEvents.onAdLoaded(FakeBanner(context)) }

        view.pause()
        view.resume()

        assertEquals("the first render and its one refresh spent the cap", 1, ads.network.renderingLoads.size)
    }

    @Test
    fun `with a cap of 1 a kept creative still gets its one refresh (origin d8c2d96)`() {
        ads.prebidReady(context)
        val activity = newActivity()
        val config = configWith(
            *prebidOnly,
            "AD_REFRESH_MAX_MOBILE" to 1,
            "MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH" to true,
        )
        val view = adView(config, ctx = activity)
        attach(activity, view)
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.pause()
        view.resume()
        idleFor(30_000)

        assertEquals(2, ads.network.renderingLoads.size)
    }

    @Test
    fun `resume with no refresh does nothing on prebidOnly`() {
        ads.prebidReady(context)
        val view = adView(configWith(*prebidOnly))
        view.load()

        view.pause()
        view.resume()

        assertEquals(1, ads.network.renderingLoads.size)
    }

    // ── Native ───────────────────────────────────────────────────────────────

    private fun finishNative(result: ResultCode, cacheId: String? = null) {
        val fetch = ads.network.nativeFetches.last()
        cacheId?.let { fetch.adObject.putString(NativeAdUnit.BUNDLE_KEY_CACHE_ID, it) }
        fetch.finish(result)
        idle()
    }

    @Test
    fun `native fills the slot at its capped height, hides the house and reports the render`() {
        ads.prebidReady(context)
        val view = adView(configWith(*native, "NATIVE_MAX_HEIGHT" to 280, "MOBILE_HOUSE_AD_IMAGE" to image))
        val ad = FakeNativeContent()
        ads.network.nativeAds["cache-1"] = ad

        view.load()
        finishNative(ResultCode.SUCCESS, "cache-1")

        assertEquals(listOf("loaded", "resize:300x280", "impression:43"), calls.calls)
        assertEquals(View.GONE, view.house()?.visibility)
        assertEquals(1, events.named("adRenderSucceeded").size)
        checkNotNull(ad.events).onAdClicked()
        assertEquals("clicked", calls.calls.last())
        assertEquals(1, events.named("click").size)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `native no-fill is adError and a house impression`() {
        ads.prebidReady(context)
        val view = adView(configWith(*native, "MOBILE_HOUSE_AD_IMAGE" to image))

        view.load()
        finishNative(ResultCode.NO_BIDS)

        assertEquals(listOf("failed:Native demand request returned no fill (NO_BIDS).", "house:43"), calls.calls)
        assertEquals(1, events.named("adError").size)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a native failure after the house was hidden records no house impression`() {
        ads.prebidReady(context)
        val view = adView(configWith(*native, "MOBILE_HOUSE_AD_IMAGE" to image))
        ads.network.nativeAds["cache-1"] = FakeNativeContent()
        view.load()
        finishNative(ResultCode.SUCCESS, "cache-1")

        finishNative(ResultCode.NO_BIDS)

        assertFalse(calls.calls.any { it.startsWith("house:") })
    }

    @Test
    fun `native waits for Prebid and loads anyway after the wait, reporting the timeout`() {
        val view = adView(configWith(*native))

        view.load()
        idleFor(8 * 150)

        assertEquals(1, ads.network.nativeFetches.size)
        val event = events.single(SellwildFailureCode.AD_PREBID_INIT_TIMEOUT)
        assertEquals("native", event.getString("label"))
        assertEquals("Prebid not ready after 8 waits; loading the native ad anyway", event.getJSONObject("attributes").getString("msg"))
    }

    @Test
    fun `native without a zone is reported and heard`() {
        val view = adView(configWith(*native), zone = null)

        view.load()

        assertEquals(listOf("failed:SellwildAdView resolved to native but has no zoneId; Prebid native rendering requires a configId."), calls.calls)
        assertEquals("native", events.single(SellwildFailureCode.AD_ZONE_MISSING).getString("label"))
        assertTrue(ads.network.nativeFetches.isEmpty())
    }

    // ── Switching stacks and teardown ────────────────────────────────────────

    @Test
    fun `each stack tears down the others when the view is set up again, and reuses its own`() {
        val view = adView(configWith(*native))
        val nativeView = view.native()

        view.setup(configWith(*native), AdSize.MREC_300x250, "43")
        assertSame(nativeView, view.native())

        view.setup(configWith("AD_STACK" to "gamOnly", "GAM" to "/1234/fixture"), AdSize.MREC_300x250, "43")
        val gam = view.gam()
        assertTrue(view.childrenList().none { it is SellwildNativeAdView })
        view.setup(configWith("AD_STACK" to "gamOnly", "GAM" to "/1234/fixture"), AdSize.MREC_300x250, "43")
        assertSame(gam, view.gam())

        view.setup(configWith(*prebidOnly), AdSize.MREC_300x250, "43")
        val banner = view.prebid()
        assertTrue(view.childrenList().none { it is AdManagerAdView })
        view.setup(configWith(*prebidOnly), AdSize.MREC_300x250, "43")
        assertSame(banner, view.prebid())

        view.setup(configWith("AD_STACK" to "gamOnly", "GAM" to "/1234/fixture"), AdSize.MREC_300x250, "43")
        assertTrue(view.childrenList().none { it is BannerView })

        view.setup(configWith(*native), AdSize.MREC_300x250, "43")
        assertTrue(view.childrenList().none { it is AdManagerAdView || it is BannerView })
        view.setup(configWith(*prebidOnly), AdSize.MREC_300x250, "43")
        assertTrue(view.childrenList().none { it is SellwildNativeAdView })
        view.setup(configWith(*native), AdSize.MREC_300x250, "43")

        view.destroy()
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a destroyed view does not reload its Prebid banner`() {
        ads.prebidReady(context)
        val view = adView(configWith(*prebidOnly, "AD_REFRESH_MAX_MOBILE" to 3))
        view.load()
        view.prebidEvents.onAdLoaded(FakeBanner(context))

        view.destroy()
        view.resume()

        assertEquals(1, ads.network.renderingLoads.size)
    }

}

/** A Prebid video player that records mute() instead of driving a real player. */
internal class FakeVideo(context: Context) : com.sellwild.prebid.api.rendering.VideoView(context) {
    val mutes = mutableListOf<Boolean>()

    override fun mute(mute: Boolean) {
        mutes += mute
    }
}
