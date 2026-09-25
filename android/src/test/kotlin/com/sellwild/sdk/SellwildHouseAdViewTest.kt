package com.sellwild.sdk

import android.content.Context
import android.graphics.drawable.BitmapDrawable
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.core.ListingsParser
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.support.NetworkBlockRule
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Locale

/** The house-ad backdrop view on Robolectric: image mode, listing-card mode and the stale-image guard. */
@RunWith(RobolectricTestRunner::class)
class SellwildHouseAdViewTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val pending = mutableListOf<Runnable>()
    private lateinit var events: CapturedEvents

    @Before
    fun images() {
        events = CapturedEvents().install()
        Locale.setDefault(Locale.US)
        SellwildHouseAd.runner = { pending += it }
        SellwildHouseAd.download = { ByteArray(4) }
        SellwildHouseAd.decode = { pixel() }
    }

    private fun runLoads() {
        pending.toList().also { pending.clear() }.forEach(Runnable::run)
        idle()
    }

    private fun image(view: SellwildHouseAdView): ImageView = (view.getChildAt(0) as LinearLayout).getChildAt(0) as ImageView

    private fun textArea(view: SellwildHouseAdView): LinearLayout = (view.getChildAt(0) as LinearLayout).getChildAt(1) as LinearLayout

    @Test
    fun `image mode fits the creative into the slot with no text`() {
        val view = SellwildHouseAdView(context)

        view.showImage(SellwildHouseAd.Creative("https://cdn.sellwild.com/house/mrec.png", null))
        runLoads()

        assertEquals(View.GONE, textArea(view).visibility)
        assertEquals(ImageView.ScaleType.FIT_CENTER, image(view).scaleType)
        assertTrue(image(view).drawable is BitmapDrawable)
    }

    @Test
    fun `listing mode shows the photo, title and price on a card`() {
        val view = SellwildHouseAdView(context)
        val listing = ListingsParser.parseListing(ListingFactory.checked(mapOf("price" to "12.5", "currency" to "EUR")))

        view.showListing(listing, configWith())
        runLoads()

        assertEquals(View.VISIBLE, textArea(view).visibility)
        val (title, price) = textArea(view).childrenList().map { (it as TextView).text.toString() }
        assertEquals("2021 Lexus UX UX 200", title)
        assertEquals("€12.50", price)
        assertEquals(ImageView.ScaleType.CENTER_CROP, image(view).scaleType)
        assertTrue(image(view).drawable is BitmapDrawable)
    }

    @Test
    fun `an image for content that was swapped out is dropped`() {
        val view = SellwildHouseAdView(context)
        val photoless = ListingsParser.parseListing(ListingFactory.checked(mapOf("photos" to JSONArray())))

        view.showImage(SellwildHouseAd.Creative("https://cdn.sellwild.com/house/a.png", null))
        view.showListing(photoless, configWith())
        runLoads()

        assertNull(image(view).drawable)
    }

    @Test
    fun `a failed image leaves the slot empty`() {
        SellwildHouseAd.decode = { null }
        val view = SellwildHouseAdView(context)

        view.showImage(SellwildHouseAd.Creative("https://cdn.sellwild.com/house/broken.png", null))
        runLoads()

        assertNull(image(view).drawable)
        assertEquals(listOf(com.sellwild.sdk.failures.SellwildFailureCode.HOUSE_IMAGE_INVALID), events.codes)
    }

    @Test
    fun `a tap goes to the owner`() {
        val view = SellwildHouseAdView(context)
        var taps = 0

        view.performClick()
        view.onTap = { taps++ }
        view.performClick()

        assertEquals(1, taps)
    }
}
