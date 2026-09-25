package com.sellwild.sdk

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresCore
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

/** The EVENTS_ENABLED kill switch read from the stored remote config JSON. */
class SellwildEventsTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun enabledFor(value: Any?): Boolean =
        SellwildEvents.isEnabled(AppConfigFactory.checked(mapOf("EVENTS_ENABLED" to value)).toString())

    @Test
    fun `events stay on unless the config turns them off`() {
        assertTrue("no config", SellwildEvents.isEnabled(null))
        assertTrue("key absent", enabledFor(null))
        assertTrue(enabledFor(true))
        assertTrue(enabledFor("yes"))
        assertTrue("an object is not a switch", SellwildEvents.isEnabled(AppConfigFactory.offSchema(mapOf("EVENTS_ENABLED" to JSONObject().put("on", false))).toString()))
        assertTrue("JSON null is unset", SellwildEvents.isEnabled(AppConfigFactory.offSchema(mapOf("EVENTS_ENABLED" to JSONObject.NULL)).toString()))

        assertFalse(enabledFor(false))
        assertFalse(enabledFor(0))
        assertFalse(enabledFor(" Off "))
        assertFalse(enabledFor("no"))
        assertTrue("nothing to report", sink.pushed.isEmpty())
    }

    // A9: the kill switch coerced numbers with toInt(), so 0.5 turned events off, while the
    // contract's coerceFlag (FAILURES.md 5.3, the failure core, core and iOS) reads it as on.
    @Test
    fun `a fraction is not 0, so it leaves events on, as coerceFlag says`() {
        val fraction = FixtureLoader.jsonObject("fixtures/app-config/valid/events-fraction.json")

        assertEquals(0.5, fraction.getDouble("EVENTS_ENABLED"), 0.0)
        assertTrue(SellwildEvents.isEnabled(fraction.toString()))
        assertTrue(enabledFor(-0.25))
        assertEquals(FailuresCore.coerceFlag(0.5), enabledFor(0.5))
    }

    @Test
    fun `text is trimmed and lower-cased as ASCII only, as coerceFlag says`() {
        assertFalse(enabledFor("\tOFF\n"))
        assertTrue("a no-break space is not ASCII whitespace", enabledFor("\u00A0off"))
        assertEquals(FailuresCore.coerceFlag("\u00A0off"), enabledFor("\u00A0off"))
    }

    @Test
    fun `config JSON that does not parse leaves events on and is reported once as a warning`() {
        assertTrue(SellwildEvents.isEnabled(FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml")))

        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE, event.action)
        assertEquals("remoteConfig", event.label)
        assertEquals("warn", event.attributes["severity"])
        assertEquals("JSONException", event.attributes["errName"])
    }
}
