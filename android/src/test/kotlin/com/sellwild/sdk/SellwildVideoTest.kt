package com.sellwild.sdk

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** [SellwildVideo]'s remote toggles. The fork builders run in SellwildAdAdaptersTest. */
class SellwildVideoTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun config(vararg entries: Pair<String, Any?>): String = AppConfigFactory.checked(mapOf(*entries)).toString()

    @Test
    fun `video is off by default, on globally, or per zone`() {
        assertFalse(SellwildVideo.isEnabled(null, "43"))
        assertFalse(SellwildVideo.isEnabled(config(), "43"))
        assertTrue(SellwildVideo.isEnabled(FixtureLoader.text("fixtures/app-config/valid/flags-mixed-types.json"), null))
        // A CMS-emitted VIDEO_ENABLED:false must not dead-letter the per-zone map.
        val byZone = config("VIDEO_ENABLED" to false, "VIDEO_ENABLED_BY_ZONE" to JSONObject().put("43", "yes").put("280", "no"))
        assertTrue(SellwildVideo.isEnabled(byZone, "43"))
        assertFalse(SellwildVideo.isEnabled(byZone, "280"))
        assertFalse(SellwildVideo.isEnabled(byZone, "999"))
    }

    @Test
    fun `sound is off by default, on globally, or per zone`() {
        assertFalse(SellwildVideo.soundEnabled(null, "43"))
        assertTrue(SellwildVideo.soundEnabled(config("VIDEO_SOUND_ENABLED" to "on"), "43"))
        val byZone = config("VIDEO_SOUND_ENABLED_BY_ZONE" to JSONObject().put("43", true))
        assertTrue(SellwildVideo.soundEnabled(byZone, "43"))
        assertFalse(SellwildVideo.soundEnabled(byZone, null))
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `config that does not parse keeps video off and is reported`() {
        val bad = FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml")

        assertFalse(SellwildVideo.isEnabled(bad, "43"))
        assertFalse(SellwildVideo.soundEnabled(bad, "43"))

        assertEquals(listOf(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE), sink.pushed.map { it.action })
    }
}
