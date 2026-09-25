package com.sellwild.sdk

import android.content.Context
import android.os.Looper
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.BannerAdUnit
import com.sellwild.prebid.NativeAdUnit
import com.sellwild.prebid.NativeDataAsset
import com.sellwild.prebid.NativeEventTracker
import com.sellwild.prebid.NativeImageAsset
import com.sellwild.prebid.NativeTitleAsset
import com.sellwild.prebid.Signals
import com.sellwild.prebid.api.data.AdUnitFormat
import com.sellwild.prebid.api.rendering.BannerView
import com.sellwild.sdk.SellwildAdSizes.Size
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.gateCalls
import com.sellwild.sdk.support.NetworkBlockRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.time.Duration
import java.util.EnumSet
import com.google.android.gms.ads.AdSize as GmaAdSize
import com.sellwild.prebid.AdSize as PrebidAdSize

/**
 * The thin adapters onto GMA, the Prebid fork and WebView, on Robolectric: the multi-size
 * setters, the native request and video parameters, and the audio guard's shim.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildAdAdaptersTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val sizes = listOf(Size(300, 250), Size(320, 50))
    private lateinit var events: CapturedEvents

    @Before
    fun capture() {
        events = CapturedEvents().install()
    }

    // ── SellwildAdSizes ──────────────────────────────────────────────────────

    @Test
    fun `GAM gets every size, and an empty list changes nothing`() {
        val view = AdManagerAdView(context)

        SellwildAdSizes.applyGam(sizes, view)
        SellwildAdSizes.applyGam(emptyList(), view)

        assertEquals(listOf(GmaAdSize(300, 250), GmaAdSize(320, 50)), view.adSizes!!.toList())
    }

    // AdUnitConfiguration.getSizes is deprecated in the fork, and BannerAdUnit.getSizes is
    // package-private: the configuration is the one public view of what the unit requests.
    @Suppress("DEPRECATION")
    @Test
    fun `a Prebid banner unit gets the sizes after the primary`() {
        val unit = BannerAdUnit("fixture-mobile-300x250", 300, 250)

        SellwildAdSizes.applyPrebid(sizes, unit)

        assertEquals(setOf(PrebidAdSize(300, 250), PrebidAdSize(320, 50)), unit.configuration.sizes)
    }

    @Test
    fun `a rendering banner gets the sizes after the primary, and none when there is only the primary`() {
        val banner = BannerView(context, "fixture-mobile-300x250", PrebidAdSize(300, 250))

        val before = banner.additionalSizes.toSet()

        SellwildAdSizes.applyRendering(sizes.take(1), banner)
        assertEquals(before, banner.additionalSizes)

        SellwildAdSizes.applyRendering(sizes, banner)
        assertEquals(before + PrebidAdSize(320, 50), banner.additionalSizes)
    }

    // ── SellwildNative / SellwildVideo ───────────────────────────────────────

    @Test
    fun `the native request asks for title, icon, main image, sponsor, body and CTA`() {
        val unit: NativeAdUnit = SellwildNative.makeRequest("native-zone")

        val native = unit.nativeConfiguration
        assertEquals(NativeAdUnit.CONTEXT_TYPE.CONTENT_CENTRIC, native.contextType)
        assertEquals(NativeAdUnit.PLACEMENTTYPE.CONTENT_FEED, native.placementType)
        assertEquals(NativeAdUnit.CONTEXTSUBTYPE.GENERAL, native.contextSubtype)
        val assets = native.assets
        assertEquals(6, assets.size)
        assertTrue((assets[0] as NativeTitleAsset).isRequired)
        assertEquals(NativeImageAsset.IMAGE_TYPE.ICON, (assets[1] as NativeImageAsset).imageType)
        assertEquals(NativeImageAsset.IMAGE_TYPE.MAIN, (assets[2] as NativeImageAsset).imageType)
        assertEquals(
            listOf(NativeDataAsset.DATA_TYPE.SPONSORED, NativeDataAsset.DATA_TYPE.DESC, NativeDataAsset.DATA_TYPE.CTATEXT),
            assets.drop(3).map { (it as NativeDataAsset).dataType },
        )
        assertEquals(NativeEventTracker.EVENT_TYPE.IMPRESSION, native.eventTrackers.single().event)
    }

    @Test
    fun `outstream video is click-to-play mp4 with VAST 2 to 4, in banner`() {
        val params = SellwildVideo.outstreamParameters()

        assertEquals(EnumSet.of(AdUnitFormat.BANNER, AdUnitFormat.VIDEO), SellwildVideo.bannerVideoFormats())
        assertEquals(listOf("video/mp4"), params.mimes)
        assertEquals(listOf(Signals.PlaybackMethod.ClickToPlay), params.playbackMethod)
        assertEquals(listOf(Signals.Protocols.VAST_2_0, Signals.Protocols.VAST_3_0, Signals.Protocols.VAST_4_0), params.protocols)
        assertEquals(listOf(Signals.Api.OMID_1, Signals.Api.MRAID_3), params.api)
        assertEquals(Signals.Placement.InBanner, params.placement)
        assertEquals(Signals.Plcmt.Standalone, params.plcmt)
        assertEquals(30, params.maxDuration)
        assertEquals(5, params.minDuration)
    }

    // ── SellwildAdAudioGuard ─────────────────────────────────────────────────

    private class ThrowingWebView(context: Context) : WebView(context) {
        override fun evaluateJavascript(script: String, resultCallback: android.webkit.ValueCallback<String>?) {
            throw IllegalStateException("WebView destroyed")
        }
    }

    private fun container(vararg children: android.view.View) = FrameLayout(context).apply { children.forEach(::addView) }

    @Test
    fun `the guard finds every WebView in the tree`() {
        val inner = WebView(context)
        val nested = container(inner)
        val top = WebView(context)
        val root = container(top, nested, FrameLayout(context), android.view.View(context))

        assertEquals(listOf(top, inner), SellwildAdAudioGuard.webViews(root))
        assertEquals(listOf(top), SellwildAdAudioGuard.webViews(top))
    }

    @Test
    fun `the shim runs now and on three retries, and a clean run reports nothing`() {
        val webView = WebView(context)

        SellwildAdAudioGuard.apply(container(webView), null)
        val shadow = shadowOf(webView)
        assertEquals(SellwildAdAudioGuard.MUTE_SCRIPT, shadow.lastEvaluatedJavascript)
        shadow.lastEvaluatedJavascriptCallback.onReceiveValue("0")
        shadow.lastEvaluatedJavascriptCallback.onReceiveValue("null")
        shadow.lastEvaluatedJavascriptCallback.onReceiveValue(null)
        // The retries run at 400, 1200 and 2500 ms: one new evaluation per step.
        var runs = 1
        for (step in listOf(400L, 800L, 1300L)) {
            val before = shadow.lastEvaluatedJavascriptCallback
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(step))
            if (shadow.lastEvaluatedJavascriptCallback !== before) runs++
        }

        assertEquals(4, runs)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `errors the shim counted in the page are reported`() {
        val webView = WebView(context)

        SellwildAdAudioGuard.apply(container(webView), null)
        shadowOf(webView).lastEvaluatedJavascriptCallback.onReceiveValue("2")

        val attributes = events.attributes(SellwildFailureCode.AD_AUDIO_GUARD_EXCEPTION)
        assertEquals("the mute shim threw in the page", attributes.getString("msg"))
        assertEquals("warn", attributes.getString("severity"))
        assertEquals("banner", events.single(SellwildFailureCode.AD_AUDIO_GUARD_EXCEPTION).getString("label"))
    }

    @Test
    fun `a WebView that throws is reported and the others still run`() {
        val ok = WebView(context)

        SellwildAdAudioGuard.apply(container(ThrowingWebView(context), ok), null)

        assertEquals(SellwildAdAudioGuard.MUTE_SCRIPT, shadowOf(ok).lastEvaluatedJavascript)
        assertEquals("IllegalStateException", events.attributes(SellwildFailureCode.AD_AUDIO_GUARD_EXCEPTION).getString("errName"))
    }

    @Test
    fun `a WebView that throws is reported once per apply, and not retried`() {
        val dead = ThrowingWebView(context)
        val ok = WebView(context)

        SellwildAdAudioGuard.apply(container(dead, ok), null)
        var okRuns = 1
        for (step in listOf(400L, 800L, 1300L)) {
            val before = shadowOf(ok).lastEvaluatedJavascriptCallback
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(step))
            if (shadowOf(ok).lastEvaluatedJavascriptCallback !== before) okRuns++
        }

        assertEquals("the live WebView still gets every retry", 4, okRuns)
        assertEquals("IllegalStateException", events.attributes(SellwildFailureCode.AD_AUDIO_GUARD_EXCEPTION).getString("errName"))
    }

    @Test
    fun `a shim that throws on every run is reported once per WebView per apply`() {
        val first = WebView(context)
        val second = WebView(context)

        SellwildAdAudioGuard.apply(container(first, second), null)
        shadowOf(first).lastEvaluatedJavascriptCallback.onReceiveValue("1")
        for (step in listOf(400L, 800L, 1300L)) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(step))
            shadowOf(first).lastEvaluatedJavascriptCallback.onReceiveValue("1")
        }

        assertEquals("the mute shim threw in the page", events.attributes(SellwildFailureCode.AD_AUDIO_GUARD_EXCEPTION).getString("msg"))
    }

    @Test
    fun `a later apply is a new ad load, so it reports its dead WebView again`() {
        failures.expectRepeats()
        val dead = container(ThrowingWebView(context))

        SellwildAdAudioGuard.apply(dead, null)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
        SellwildAdAudioGuard.apply(dead, null)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))

        assertEquals(2, gateCalls(SellwildFailureCode.AD_AUDIO_GUARD_EXCEPTION))
    }

    @Test
    fun `the guard does nothing when the config turns it off`() {
        val webView = WebView(context)

        SellwildAdAudioGuard.apply(container(webView), AppConfigFactory.checked(mapOf("MOBILE_AD_MUTE_AUTOPLAY" to "off")).toString())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))

        assertNull(shadowOf(webView).lastEvaluatedJavascript)
    }

    @Test
    fun `a retry after the container is gone does nothing`() {
        SellwildAdAudioGuard.muteIfAlive(java.lang.ref.WeakReference(null), SellwildAdAudioGuard.Run())

        assertEquals(emptyList<String>(), events.codes)
    }
}
