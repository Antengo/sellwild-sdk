package com.sellwild.sdk

import android.content.Context
import android.graphics.drawable.BitmapDrawable
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.sellwild.prebid.NativeAdUnit
import com.sellwild.prebid.ResultCode
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.NetworkBlockRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * SellwildNativeAdView on Robolectric: the native auction through the fake ad network, the
 * failures it reports, and the template it binds and registers.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildNativeAdViewTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var events: CapturedEvents
    private val calls = mutableListOf<String>()
    private val icon = "https://cdn.example.com/icon.png"
    private val media = "https://cdn.example.com/main.png"

    @Before
    fun capture() {
        events = CapturedEvents().install()
        SellwildHouseAd.runner = { it.run() }
        SellwildHouseAd.download = { ByteArray(4) }
        SellwildHouseAd.decode = { pixel() }
    }

    private fun nativeView(config: SellwildConfig = configWith("NATIVE_ZID_ANDROID" to "native-43")) =
        SellwildNativeAdView(context, config, "43", 280).apply {
            onLoaded = { calls += "loaded" }
            onImpression = { calls += "impression" }
            onClick = { calls += "click" }
            onFailed = { calls += "failed:$it" }
        }

    private fun finish(result: ResultCode, cacheId: String? = null) {
        val fetch = ads.network.nativeFetches.single()
        cacheId?.let { fetch.adObject.putString(NativeAdUnit.BUNDLE_KEY_CACHE_ID, it) }
        fetch.finish(result)
        idle()
    }

    private fun texts(view: SellwildNativeAdView): List<String> {
        val out = mutableListOf<String>()
        fun walk(v: android.view.View) {
            if (v is TextView) out += v.text.toString()
            if (v is android.view.ViewGroup) v.childrenList().forEach(::walk)
        }
        walk(view)
        return out
    }

    private fun images(view: SellwildNativeAdView): List<ImageView> {
        val out = mutableListOf<ImageView>()
        fun walk(v: android.view.View) {
            if (v is ImageView) out += v
            if (v is android.view.ViewGroup) v.childrenList().forEach(::walk)
        }
        walk(view)
        return out
    }

    @Test
    fun `load asks for native demand on the native placement id`() {
        nativeView().load()

        assertEquals("native-43", ads.network.nativeFetches.single().unit.configuration.configId)
    }

    @Test
    fun `a win binds the assets with fallbacks, loads the images and registers the trackers`() {
        val ad = FakeNativeContent(sponsoredBy = "", callToAction = null, iconUrl = icon, imageUrl = media)
        ads.network.nativeAds["cache-1"] = ad
        val view = nativeView()

        view.load()
        finish(ResultCode.SUCCESS, "cache-1")

        assertEquals(listOf("Fixture native title", "Sponsored", "Fixture native body", "Learn more"), texts(view))
        assertTrue(images(view).all { it.drawable is BitmapDrawable })
        assertSame(view, ad.container)
        assertEquals(3, ad.clickables.size)
        assertEquals(listOf("loaded"), calls)
        checkNotNull(ad.events).onAdImpression()
        checkNotNull(ad.events).onAdClicked()
        checkNotNull(ad.events).onAdExpired()
        (ad.clickables.first() as Button).performClick()
        assertEquals(listOf("loaded", "impression", "click", "click"), calls)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a win with a sponsor and a call to action shows them`() {
        ads.network.nativeAds["cache-1"] = FakeNativeContent()
        val view = nativeView()

        view.load()
        finish(ResultCode.SUCCESS, "cache-1")

        assertEquals(listOf("Fixture native title", "Sponsored · Fixture Brand", "Fixture native body", "Shop now"), texts(view))
        // No image URLs: the placeholders stay.
        assertTrue(images(view).all { it.drawable == null })
    }

    @Test
    fun `no bids is only a failed callback, never a failure`() {
        nativeView().load()

        finish(ResultCode.NO_BIDS)

        assertEquals(listOf("failed:Native demand request returned no fill (NO_BIDS)."), calls)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `an auction that fails for another reason is reported once as native`() {
        nativeView().load()

        finish(ResultCode.INVALID_CONFIG_ID)

        assertEquals(listOf("failed:Native demand request returned no fill (INVALID_CONFIG_ID)."), calls)
        val event = events.single(SellwildFailureCode.AD_PREBID_AUCTION_INVALID)
        assertEquals("native", event.getString("label"))
        assertEquals("43", event.getJSONObject("attributes").getString("zoneId"))
    }

    @Test
    fun `a win without a cache id is ad_native_create_invalid`() {
        nativeView().load()

        finish(ResultCode.SUCCESS)

        assertEquals(listOf("failed:Native demand won but no PrebidNativeAd could be created."), calls)
        val attributes = events.attributes(SellwildFailureCode.AD_NATIVE_CREATE_INVALID)
        assertEquals("native win without a cache id", attributes.getString("msg"))
        assertEquals("error", attributes.getString("severity"))
    }

    @Test
    fun `a win whose ad cannot be created is ad_native_create_invalid`() {
        nativeView().load()

        finish(ResultCode.SUCCESS, "cache-gone")

        assertEquals("native ad could not be created from the cache", events.attributes(SellwildFailureCode.AD_NATIVE_CREATE_INVALID).getString("msg"))
    }

    @Test
    fun `an image that arrives after destroy is dropped`() {
        val pending = mutableListOf<Runnable>()
        SellwildHouseAd.runner = { pending += it }
        ads.network.nativeAds["cache-1"] = FakeNativeContent(iconUrl = icon)
        val view = nativeView()
        view.load()
        finish(ResultCode.SUCCESS, "cache-1")

        view.destroy()
        pending.forEach(Runnable::run)
        idle()

        assertTrue(images(view).all { it.drawable == null })
    }

    @Test
    fun `an image that fails to load leaves the placeholder, reported by the image loader`() {
        SellwildHouseAd.decode = { null }
        ads.network.nativeAds["cache-1"] = FakeNativeContent(imageUrl = media)
        val view = nativeView()

        view.load()
        finish(ResultCode.SUCCESS, "cache-1")

        assertNull(images(view).last().drawable)
        assertEquals(listOf(SellwildFailureCode.HOUSE_IMAGE_INVALID), events.codes)
    }

    // ── No callbacks set, and debug trace ────────────────────────────────────

    /** A view with none of onLoaded, onImpression, onClick or onFailed set. */
    private fun bareView() = SellwildNativeAdView(context, configWith("NATIVE_ZID_ANDROID" to "native-43"), "43", 280)

    private fun finishLast(result: ResultCode, cacheId: String? = null) {
        val fetch = ads.network.nativeFetches.last()
        cacheId?.let { fetch.adObject.putString(NativeAdUnit.BUNDLE_KEY_CACHE_ID, it) }
        fetch.finish(result)
        idle()
    }

    @Test
    fun `a view with no callbacks set still binds, registers and takes taps`() {
        val ad = FakeNativeContent(iconUrl = "", imageUrl = media)
        ads.network.nativeAds["cache-1"] = ad
        val view = bareView()

        view.load()
        finishLast(ResultCode.SUCCESS, "cache-1")
        checkNotNull(ad.events).onAdImpression()
        checkNotNull(ad.events).onAdClicked()
        (ad.clickables.first() as Button).performClick()

        assertEquals(listOf("Fixture native title", "Sponsored · Fixture Brand", "Fixture native body", "Shop now"), texts(view))
        // An empty icon URL is no icon; the media image loads.
        assertNull(images(view).first().drawable)
        assertTrue(images(view).last().drawable is BitmapDrawable)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a view with no callbacks set still reports a win it cannot create, and a no-fill is nothing`() {
        bareView().load()
        finishLast(ResultCode.NO_BIDS)
        bareView().load()
        finishLast(ResultCode.SUCCESS)

        assertEquals("native win without a cache id", events.attributes(SellwildFailureCode.AD_NATIVE_CREATE_INVALID).getString("msg"))
    }

    @Test
    fun `with debug on a no-fill and an expired ad are traced`() {
        SellwildFailures.setContext { it.copy(debug = true) }
        val ad = FakeNativeContent()
        ads.network.nativeAds["cache-1"] = ad

        nativeView().load()
        finishLast(ResultCode.NO_BIDS)
        nativeView().load()
        finishLast(ResultCode.SUCCESS, "cache-1")
        checkNotNull(ad.events).onAdExpired()

        assertTrue(failures.lines.contains("[native] no fill — zone 43, result NO_BIDS"))
        assertTrue(failures.lines.contains("[native] ad expired — zone 43"))
        assertEquals(emptyList<String>(), events.codes)
    }
}
