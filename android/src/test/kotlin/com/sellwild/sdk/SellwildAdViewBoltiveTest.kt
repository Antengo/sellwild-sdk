package com.sellwild.sdk

import android.content.Context
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.sellwild.prebid.configuration.AdUnitConfiguration
import com.sellwild.prebid.rendering.bidding.data.bid.Bid
import com.sellwild.prebid.rendering.bidding.data.bid.BidResponse
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildLog
import com.sellwild.sdk.support.NetworkBlockRule
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * SellwildAdView with Boltive on: each rendered banner is captured, and a block hides the
 * paid creative, shows the house backdrop, tells the host, tracks adBlocked and re-auctions
 * within the refresh cap. On Robolectric with a fake ad network and fake Boltive monitors.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildAdViewBoltiveTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var events: CapturedEvents
    private val calls = AdEvents()

    private val boltive = arrayOf<Pair<String, Any?>>(
        "GAM" to "/1234/fixture",
        "MOBILE_BOLTIVE_ENABLED" to true,
        "MOBILE_BOLTIVE_CLIENT_ID" to "boltive-fixture",
        "MOBILE_HOUSE_AD_IMAGE" to "https://cdn.sellwild.com/house/mrec.png",
    )

    @Before
    fun capture() {
        events = CapturedEvents().install()
        SellwildHouseAd.runner = { it.run() }
        SellwildHouseAd.download = { ByteArray(4) }
        SellwildHouseAd.decode = { pixel() }
    }

    private fun adView(vararg overrides: Pair<String, Any?>, ctx: Context = context): SellwildAdView =
        SellwildAdView(ctx).apply {
            setup(configWith(*boltive, *overrides), AdSize.MREC_300x250, "43")
            listener = calls
        }

    private fun blockLast() {
        ads.network.boltiveSessions.last().block()
        idle()
    }

    @Test
    fun `a blocked GAM creative is hidden for the house ad, reported and re-auctioned`() {
        val view = adView("AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 2)
        view.load()
        view.gam().adListener.onAdLoaded()
        val session = ads.network.boltiveSessions.single()
        assertSame(view.gam(), session.captured)
        assertEquals("/1234/fixture", session.adView?.tagDetails?.adUnitId)

        blockLast()

        assertEquals(View.INVISIBLE, view.gam().visibility)
        assertEquals(View.VISIBLE, view.house()?.visibility)
        assertEquals("blocked:43", calls.calls.first { it.startsWith("blocked") })
        val blocked = events.named("adBlocked").single()
        assertEquals("gam", blocked.getString("action"))
        assertEquals("43", blocked.getString("label"))
        assertEquals("the block re-auctions at once", 2, ads.network.gamLoads.size)

        view.gam().adListener.onAdLoaded()
        assertEquals("the next fill shows the banner again", View.VISIBLE, view.gam().visibility)
    }

    @Test
    fun `a GAM block with no refresh budget left does not re-auction`() {
        val view = adView("AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 0, "AD_REFRESH_MAX" to 0)
        view.load()
        view.gam().adListener.onAdLoaded()

        blockLast()
        idleFor(120_000)

        assertEquals(1, events.named("adBlocked").size)
        assertEquals(1, ads.network.gamLoads.size)
    }

    @Test
    fun `a GAM block once the refresh cap is spent does not re-auction`() {
        val view = adView("AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 1)
        view.load()
        view.gam().adListener.onAdLoaded()
        blockLast()
        assertEquals(2, ads.network.gamLoads.size)
        view.gam().adListener.onAdLoaded()

        blockLast()
        idleFor(120_000)

        assertEquals(2, events.named("adBlocked").size)
        assertEquals(2, ads.network.gamLoads.size)
    }

    @Test
    fun `a blocked Prebid creative carries its bidder and re-auctions through Prebid`() {
        val view = adView("AD_STACK" to "prebidOnly", "AD_REFRESH_MAX_MOBILE" to 2)
        view.load()
        val banner = view.prebid()
        view.prebidEvents.onAdLoaded(banner)
        val session = ads.network.boltiveSessions.single()
        assertSame(banner, session.captured)
        assertEquals("43", session.adView?.tagDetails?.adUnitId)
        val loadsBefore = ads.network.renderingLoads.size

        blockLast()

        assertEquals(View.INVISIBLE, banner.visibility)
        assertEquals(View.VISIBLE, view.house()?.visibility)
        // No winning bid on this banner, so no bidder: the source is "prebid".
        assertEquals("prebid", events.named("adBlocked").single().getString("action"))
        assertEquals(listOf<View>(banner), ads.network.renderingLoads.drop(loadsBefore))

        view.prebidEvents.onAdLoaded(banner)
        assertEquals(View.VISIBLE, banner.visibility)
    }

    @Test
    fun `a Prebid block with no refresh budget does not re-auction`() {
        val view = adView("AD_STACK" to "prebidOnly", "AD_REFRESH_MAX_MOBILE" to 0, "AD_REFRESH_MAX" to 0)
        view.load()
        val banner = view.prebid()
        view.prebidEvents.onAdLoaded(banner)
        val loadsBefore = ads.network.renderingLoads.size

        blockLast()

        assertEquals(1, events.named("adBlocked").size)
        assertEquals(loadsBefore, ads.network.renderingLoads.size)
    }

    @Test
    fun `a block that lands while the view is detached does not re-auction`() {
        val activity = newActivity()
        val view = adView("AD_STACK" to "gamOnly", "AD_REFRESH_MAX_MOBILE" to 3, ctx = activity)
        val parent = attach(activity, view)
        view.load()
        view.gam().adListener.onAdLoaded()
        parent.removeView(view)

        blockLast()

        assertEquals(View.INVISIBLE, view.gam().visibility)
        assertEquals(1, events.named("adBlocked").size)
        assertEquals(1, ads.network.gamLoads.size)
    }

    @Test
    fun `a late block for a banner the view has torn down is ignored`() {
        val view = adView("AD_STACK" to "prebidOnly", "AD_REFRESH_MAX_MOBILE" to 2)
        view.prebidEvents.onAdLoaded(FakeBanner(context, wonWidth = 300, wonHeight = 250))

        blockLast()

        assertEquals(emptyList<Any>(), events.named("adBlocked"))
        assertEquals(emptyList<String>(), calls.calls.filter { it.startsWith("blocked") })
    }

    @Test
    fun `destroy ends the live monitor`() {
        val view = adView("AD_STACK" to "gamOnly")
        view.load()
        view.gam().adListener.onAdLoaded()

        view.destroy()

        assertEquals(1, ads.network.boltiveSessions.single().terminated)
    }

    /** A Prebid response whose winning bid names its advertiser, creative and campaign. */
    private class WinningBid(private val bid: Bid, private val bidder: String?) : BidResponse(
        "{}",
        AdUnitConfiguration()
    ) {
        override fun getWinningBid(): Bid = bid

        override fun getTargeting(): HashMap<String, String> = HashMap(
            bidder?.let { mapOf("hb_bidder" to it) }.orEmpty()
        )
    }

    private fun bid(vararg fields: Pair<String, Any>): Bid =
        Bid.fromJSONObject(JSONObject(mapOf("id" to "b1", "impid" to "i1", "price" to 1.5, *fields)))

    @Test
    fun `a Prebid render tags Boltive with the winning bid's advertiser, creative, campaign and bidder`() {
        val view = adView("AD_STACK" to "prebidOnly")
        val response = WinningBid(
            bid("crid" to "crid-1", "cid" to "cid-1", "adomain" to org.json.JSONArray(listOf("brand.example"))),
            bidder = "appnexus",
        )

        view.prebidEvents.onAdLoaded(FakeBanner(context, response, wonWidth = 300, wonHeight = 250))

        val details = checkNotNull(ads.network.boltiveSessions.single().adView?.tagDetails)
        assertEquals("43", details.adUnitId)
        assertEquals("brand.example", details.advertiserId)
        assertEquals("crid-1", details.creativeId)
        assertEquals("cid-1", details.campaignId)
        assertEquals("appnexus", details.sspRefreshCode)
        assertEquals("a sized bid is not reported", emptyList<Any>(), events.named("adSizeMissing"))
    }

    @Test
    fun `a Prebid bid with no size names its bidder in adSizeMissing, and one with no advertiser tags none`() {
        val view = adView("AD_STACK" to "prebidOnly")
        SellwildLog.enabled = true

        view.prebidEvents.onAdLoaded(FakeBanner(context, WinningBid(bid("adomain" to org.json.JSONArray()), "rubicon")))

        assertEquals(listOf("rubicon"), events.named("adSizeMissing").map { it.getString("action") })
        assertTrue(failures.lines.any { it.contains("bid has no size (reported 0x0) — bidder rubicon") })
        val details = checkNotNull(ads.network.boltiveSessions.single().adView?.tagDetails)
        assertEquals("", details.advertiserId)
        assertEquals("rubicon", details.sspRefreshCode)
    }

    @Test
    fun `a block reaches a listener that overrides nothing, and debug names the zone and source`() {
        val view = adView("AD_STACK" to "gamOnly")
        view.listener = object : SellwildAdView.Listener {}
        view.load()
        view.gam().adListener.onAdLoaded()
        SellwildLog.enabled = true

        blockLast()

        assertEquals(1, events.named("adBlocked").size)
        assertTrue(failures.lines.any { it.contains("[Boltive] creative blocked — zone 43, source gam") })
    }

    @Test
    fun `a GAM block on a view with no zone reports an empty zone`() {
        val view = SellwildAdView(context).apply {
            setup(
                configWith(*boltive, "AD_STACK" to "gamOnly", "MOBILE_BOLTIVE_ENABLED_BY_ZONE" to ""),
                AdSize.MREC_300x250,
                null
            )
            listener = calls
        }
        view.load()
        view.gam().adListener.onAdLoaded()

        blockLast()

        assertEquals(listOf("blocked:"), calls.calls.filter { it.startsWith("blocked") })
        assertEquals("", events.named("adBlocked").single().optString("label"))
    }

    @Test
    fun `the first render of a zone is timed once per process`() {
        val pushed = mutableListOf<com.sellwild.sdk.timing.TimingEvent>()
        com.sellwild.sdk.timing.SellwildTiming.push = { pushed += it }
        com.sellwild.sdk.timing.SellwildTiming.remote = JSONObject().put("TIMING_SAMPLE_RATE", 1)
        val first = adView("AD_STACK" to "gamOnly")
        first.load()
        idleFor(1_500)
        first.gam().adListener.onAdLoaded()
        first.gam().adListener.onAdLoaded()
        val second = adView("AD_STACK" to "gamOnly")
        second.load()
        second.gam().adListener.onAdLoaded()

        val timing = pushed.single()
        assertEquals("ad.firstLoad", timing.action)
        assertEquals("43", timing.attributes["zoneId"])
        assertEquals("1500", timing.attributes["ms"])
    }

    @Test
    fun `a first ad slower than its budget is reported as ad load slow`() {
        val first = adView("AD_STACK" to "gamOnly")
        first.load()
        idleFor(6_500)
        first.gam().adListener.onAdLoaded()

        val slow = events.attributes(com.sellwild.sdk.failures.SellwildFailureCode.AD_LOAD_SLOW)
        assertEquals("6500", slow.getString("ctx.ms"))
        assertEquals("43", slow.getString("zoneId"))
    }
}
