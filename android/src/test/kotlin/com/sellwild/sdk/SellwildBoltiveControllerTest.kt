package com.sellwild.sdk

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.boltive.api.AdNetwork
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildLog
import com.sellwild.sdk.support.NetworkBlockRule
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * SellwildBoltiveController against a fake Boltive monitor (FakeAdNetwork): which renders get
 * a monitor, what it captures, the block callback, and the two Boltive calls that can throw
 * (capture and terminate), each reported once with its own code.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildBoltiveControllerTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var events: CapturedEvents
    private val zone = "43"

    @Before
    fun capture() {
        events = CapturedEvents().install()
    }

    private fun remote(vararg pairs: Pair<String, Any>): String =
        JSONObject().apply {
            put("MOBILE_BOLTIVE_ENABLED", true)
            put("MOBILE_BOLTIVE_CLIENT_ID", "boltive-fixture")
            pairs.forEach { (k, v) -> put(k, v) }
        }.toString()

    private val tag = SellwildBoltiveController.Tag(adUnitId = "/1234/fixture")

    @Suppress("LongParameterList") // the controller's own parameters, with test defaults
    private fun SellwildBoltiveController.render(
        view: View = FrameLayout(context),
        remoteJson: String? = remote(),
        network: SellwildBoltive.Network = SellwildBoltive.Network.GAM,
        tag: SellwildBoltiveController.Tag = this@SellwildBoltiveControllerTest.tag,
        debug: Boolean = false,
        roll: Double = 0.0,
        onBlocked: (View) -> Unit = {},
    ): Boolean = renderDidSucceed(view, 300, 250, network, remoteJson, zone, tag, debug, roll, onBlocked)

    @Test
    fun `a render Boltive is off for gets no monitor`() {
        val controller = SellwildBoltiveController()

        assertFalse(controller.render(remoteJson = null))
        assertFalse(controller.render(remoteJson = remote("MOBILE_BOLTIVE_SAMPLE_RATE" to 0)))

        assertEquals(emptyList<FakeBoltiveSession>(), ads.network.boltiveSessions)
        assertEquals(0, controller.slotCount)
        assertEquals(0, SellwildBoltive.sessionCount.get())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a GAM render is captured with its size, client id and ad unit, and counted`() {
        val controller = SellwildBoltiveController()
        val banner = FrameLayout(context)

        assertTrue(controller.render(view = banner))

        val session = ads.network.boltiveSessions.single()
        assertEquals("boltive-fixture", session.configuration.clientId)
        assertEquals(AdNetwork.GAM, session.configuration.adNetwork)
        assertSame(banner, session.captured)
        val adView = checkNotNull(session.adView)
        assertEquals(300, adView.width)
        assertEquals(250, adView.height)
        val details = checkNotNull(adView.tagDetails)
        assertEquals("/1234/fixture", details.adUnitId)
        assertEquals("unset details stay Boltive's empty default", "", details.advertiserId)
        assertEquals("", details.creativeId)
        assertEquals(1, controller.slotCount)
        assertEquals(1, controller.monitorsCreated)
        assertEquals(1, SellwildBoltive.sessionCount.get())
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a Prebid render names the custom network and carries the winning bid's details`() {
        val controller = SellwildBoltiveController()
        val bidTag = SellwildBoltiveController.Tag(
            adUnitId = zone,
            advertiserId = "brand.example",
            creativeId = "crid-1",
            campaignId = "cid-1",
            sspRefreshCode = "appnexus",
        )

        assertTrue(controller.render(network = SellwildBoltive.Network.PREBID, tag = bidTag))

        val session = ads.network.boltiveSessions.single()
        assertNotEquals(AdNetwork.GAM, session.configuration.adNetwork)
        val details = checkNotNull(session.adView?.tagDetails)
        assertEquals(zone, details.adUnitId)
        assertEquals("brand.example", details.advertiserId)
        assertEquals("crid-1", details.creativeId)
        assertEquals("cid-1", details.campaignId)
        assertEquals("appnexus", details.sspRefreshCode)
    }

    @Test
    fun `a block is delivered on the main thread with the captured view`() {
        val controller = SellwildBoltiveController()
        val banner = FrameLayout(context)
        val blocked = mutableListOf<View>()
        controller.render(view = banner) { blocked += it }

        ads.network.boltiveSessions.single().block()
        assertEquals("posted, not called inline", emptyList<View>(), blocked)
        idle()

        assertEquals(listOf<View>(banner), blocked)
    }

    @Test
    fun `each render ends the last monitor, and a render that is not monitored ends it too`() {
        val controller = SellwildBoltiveController()

        controller.render()
        controller.render()
        val (first, second) = ads.network.boltiveSessions
        assertEquals(1, first.terminated)
        assertEquals(0, second.terminated)

        assertFalse(controller.render(remoteJson = remote("MOBILE_BOLTIVE_ENABLED_ANDROID" to false)))
        assertEquals(1, second.terminated)
        assertEquals(2, controller.slotCount)

        controller.stop()
        assertEquals("nothing live, nothing to end", 1, second.terminated)
    }

    @Test
    fun `the per-slot cap stops monitoring this view only`() {
        val controller = SellwildBoltiveController()
        val capped = remote("MOBILE_BOLTIVE_MAX_PER_SLOT" to 1)

        assertTrue(controller.render(remoteJson = capped))
        assertFalse(controller.render(remoteJson = capped))
        assertTrue(SellwildBoltiveController().render(remoteJson = capped))

        assertEquals(2, ads.network.boltiveSessions.size)
        assertEquals(1, ads.network.boltiveSessions.first().terminated)
    }

    @Test
    fun `capture that throws is reported, ends that monitor and counts nothing`() {
        ads.network.boltiveCaptureError = IllegalStateException("no creative WebView")
        val controller = SellwildBoltiveController()

        assertFalse(controller.render())

        val attributes = events.attributes(SellwildFailureCode.AD_BOLTIVE_CAPTURE_EXCEPTION)
        assertEquals("banner", events.failures.single().getString("label"))
        assertEquals("warn", attributes.getString("severity"))
        assertEquals(zone, attributes.getString("zoneId"))
        assertEquals(1, ads.network.boltiveSessions.single().terminated)
        assertEquals(0, controller.slotCount)
        assertEquals(0, SellwildBoltive.sessionCount.get())
    }

    @Test
    fun `terminate that throws is reported once and the monitor is dropped all the same`() {
        ads.network.boltiveTerminateError = IllegalStateException("timer already cancelled")
        val controller = SellwildBoltiveController()
        controller.render()

        controller.stop()
        controller.stop()

        val attributes = events.attributes(SellwildFailureCode.AD_BOLTIVE_TERMINATE_EXCEPTION)
        assertEquals("banner", events.failures.single().getString("label"))
        assertEquals("warn", attributes.getString("severity"))
        assertEquals(zone, attributes.getString("zoneId"))
        assertEquals(1, ads.network.boltiveSessions.single().terminated)
    }

    @Test
    fun `debug prints one line per monitored render`() {
        val controller = SellwildBoltiveController()
        SellwildLog.enabled = true

        controller.render(debug = true)
        controller.render(debug = false)

        assertEquals(1, failures.lines.count { it.startsWith("[SellwildBoltive] monitoring render") })
        assertTrue(failures.lines.any { it.contains("zone 43, GAM, slot #1, session #1") })
    }

    @Test
    fun `without a roll the render rolls its own, and every roll is under a full sample rate`() {
        val controller = SellwildBoltiveController()

        assertTrue(
            controller.renderDidSucceed(
                FrameLayout(context),
                300,
                250,
                SellwildBoltive.Network.GAM,
                remote(),
                zone,
                tag
            ) {}
        )
    }

    @Test
    fun `JSON null or zero in the switches reads as off`() {
        val nullPlatform = JSONObject(remote()).put("MOBILE_BOLTIVE_ENABLED_ANDROID", JSONObject.NULL).toString()
        assertTrue("null platform override = unset", SellwildBoltive.isEnabled(nullPlatform, zone))
        assertFalse(SellwildBoltive.isEnabled(JSONObject().put("MOBILE_BOLTIVE_ENABLED", 0).toString(), zone))
    }

    @Test
    fun `config that does not parse leaves Boltive off and is reported`() {
        assertFalse(SellwildBoltive.isEnabled("{not json", zone))
        assertNull(SellwildBoltive.policy("{not json", zone))

        events.single(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE)
    }
}
