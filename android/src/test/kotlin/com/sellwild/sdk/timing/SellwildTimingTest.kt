package com.sellwild.sdk.timing

import com.sellwild.sdk.CapturedEvents
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.NetworkBlockRule
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The sdkTiming shell (FAILURES.md 18.1): held until a queue exists, sampled, and `*.slow`. */
@RunWith(RobolectricTestRunner::class)
class SellwildTimingTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private lateinit var events: CapturedEvents
    private val all = """{"TIMING_SAMPLE_RATE":1}"""

    @Before
    fun setUp() {
        events = CapturedEvents()
        // Through the real queue (FailuresRule installs a no-op sink).
        SellwildTiming.push = null
        SellwildTiming.remote = JSONObject(all)
        SellwildTiming.clock = { CapturedEvents.NOW }
    }

    @Test
    fun `timings before a queue are held and sent when one is attached`() {
        SellwildFailures.setContext { it.copy(partnerCode = "weatherbug", appId = "com.example", os = "Android 15") }
        SellwildTiming.record("config.fetch", 812)

        assertEquals(0, events.named("sdkTiming").size)
        events.install()
        events.install()

        val timing = events.named("sdkTiming").single()
        assertEquals("config.fetch", timing.getString("action"))
        assertEquals("timing", timing.getString("label"))
        val attributes = timing.getJSONObject("attributes")
        assertEquals("812", attributes.getString("ms"))
        assertEquals("weatherbug", attributes.getString("code"))
        assertEquals("com.example", attributes.getString("appId"))
        assertEquals("1", attributes.getString("seq"))
    }

    @Test
    fun `each slow step logs its code with ms and budget, sampled or not`() {
        events.install()
        SellwildTiming.remote = JSONObject("""{"TIMING_SAMPLE_RATE":0,"TIMING_BUDGET_CONFIG_MS":"100"}""")

        SellwildTiming.record("config.fetch", 101)
        SellwildTiming.record("listings.fetch", 4001)
        SellwildTiming.record("ad.firstLoad", 6001, "43")
        SellwildTiming.record("listings.decode", 99_999)

        assertEquals(
            listOf(
                SellwildFailureCode.CONFIG_FETCH_SLOW,
                SellwildFailureCode.LISTINGS_FETCH_SLOW,
                SellwildFailureCode.AD_LOAD_SLOW
            ),
            events.codes,
        )
        val labels = events.failures.map { it.getString("label") }
        assertEquals(listOf("remoteConfig", "listings", "banner"), labels)
        val ad = events.failures.last().getJSONObject("attributes")
        assertEquals("6001", ad.getString("ctx.ms"))
        assertEquals("6000", ad.getString("ctx.budgetMs"))
        assertEquals("43", ad.getString("zoneId"))
        assertEquals(0, events.named("sdkTiming").size)
    }

    @Test
    fun `start times with the monotonic clock`() {
        var t = 1_000L
        SellwildTiming.monotonic = { t }
        val pushed = mutableListOf<TimingEvent>()
        SellwildTiming.push = { pushed += it }

        val done = SellwildTiming.start("ad.firstLoad", "43")
        t = 1_250L

        assertEquals(250L, done())
        assertEquals(listOf("250" to "43"), pushed.map { it.attributes["ms"] to it.attributes["zoneId"] })
    }

    @Test
    fun `JSON null switches are unset, and no remote config is the defaults`() {
        val pushed = mutableListOf<TimingEvent>()
        SellwildTiming.push = { pushed += it }
        SellwildTiming.remote = JSONObject().put("TIMING_ENABLED", JSONObject.NULL).put("TIMING_SAMPLE_RATE", 1)
        SellwildTiming.record("config.fetch", 1)
        SellwildTiming.remote = null
        SellwildTiming.record("config.fetch", 1)

        // The second is sampled at the default 10% with no queue uid: "" is in it (fnv ≈ 0.049).
        assertEquals(2, pushed.size)
    }

    @Test
    fun `claimOnce is true once per key`() {
        assertTrue(SellwildTiming.claimOnce("feed.firstListing"))
        assertFalse(SellwildTiming.claimOnce("feed.firstListing"))
        assertTrue(SellwildTiming.claimOnce("ad.firstLoad:43"))
    }

    @Test
    fun `its own failures are counted, not thrown`() {
        SellwildTiming.push = { error("sink") }
        SellwildTiming.record("config.fetch", 1)
        SellwildTiming.clock = { error("clock") }
        SellwildTiming.record("config.fetch", 1)

        assertEquals(2, SellwildTiming.internalErrors)
    }

    @Test
    fun `held timings stop at the session cap`() {
        repeat(TimingCore.SESSION_TIMINGS + 5) { SellwildTiming.record("listings.decode", it.toLong()) }
        events.install()

        assertEquals(TimingCore.SESSION_TIMINGS, events.named("sdkTiming").size)
    }
}
