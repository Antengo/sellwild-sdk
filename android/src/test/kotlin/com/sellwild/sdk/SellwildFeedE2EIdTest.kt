package com.sellwild.sdk

import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.factories.ListingsResponseFactory
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.support.FixtureLoader
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * The feed's listing and ad rows report the e2e ids of contracts/e2e/ids.json as their
 * resource-id, which UI Automator (and so Maestro) reads. Every sample app's Maestro flows
 * find the feed's rows by them. (Its own file: SellwildFeedViewTest.kt is long.)
 */
@RunWith(RobolectricTestRunner::class)
class SellwildFeedE2EIdTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val listingsUrl = "https://cache.sellwild.com/listings-img-data-sm-fixture"

    @OptIn(ExperimentalCoroutinesApi::class)
    @Before
    fun setUp() {
        // The listings fetch and the photo loads run in place.
        val inPlace = UnconfinedTestDispatcher()
        SellwildFeedView.apiClient = { ctx -> SellwildAPIClient(ctx, inPlace) { } }
        FeedImages.io = inPlace
        FeedImages.fetch = { pixel() }
        FeedImages.decode = { pixel() }
    }

    private fun View.resourceId(): String? = createAccessibilityNodeInfo().viewIdResourceName

    @Test
    fun `listing and ad rows carry the e2e ids`() {
        val activity = newActivity()
        val config = configWith(
            "LISTINGS" to listingsUrl,
            "GAM" to "/1234/fixture",
            "AD_STACK" to "gamOnly",
            "COL1" to "LGLB",
            "MOBILE_ZID" to jsonArrayOf("z1"),
            "MOBILE_BANNER_ZID" to "b1",
        )
        val feed = SellwildFeedView(activity).apply {
            scrollEnabled = false
            setup(config)
        }
        val body = ListingsResponseFactory.withItems(
            ListingFactory.checked(mapOf("id" to "l1")),
            ListingFactory.checked(mapOf("id" to "l2")),
        ).toString()
        HttpStub.install { url -> if (url.toString().startsWith(listingsUrl)) StubResponse(200, body) else null }.use {
            feed.load()
            idle()
        }
        attach(activity, feed, 1080, 20_000, FrameLayout.LayoutParams(1080, ViewGroup.LayoutParams.WRAP_CONTENT))
        idleFor(50)

        val recycler = (feed.getChildAt(0) as SwipeRefreshLayout).getChildAt(0) as RecyclerView
        val rows = (0 until recycler.childCount).map(recycler::getChildAt)
        assertEquals(
            "header, L, G, L, B",
            listOf(null, "sw.listing.card", "sw.feed.ad", "sw.listing.card", "sw.feed.ad"),
            rows.map { it.resourceId() },
        )
        // An ad row's no-fill fallback card is a listing card, but not a listing row.
        assertNull((rows[2] as ViewGroup).getChildAt(0).resourceId())
        val listed = FixtureLoader.jsonObject("e2e/ids.json").getJSONObject("ids")
        assertTrue(listed.has(SellwildE2EIds.LISTING_CARD))
        assertTrue(listed.has(SellwildE2EIds.FEED_AD))
    }
}
