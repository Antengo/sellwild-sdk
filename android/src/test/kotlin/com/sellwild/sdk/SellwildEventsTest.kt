package com.sellwild.sdk

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
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
        SellwildEvents.isEnabled(AppConfigFactory.build(mapOf("EVENTS_ENABLED" to value)).toString())

    @Test
    fun `events stay on unless the config turns them off`() {
        assertTrue("no config", SellwildEvents.isEnabled(null))
        assertTrue("key absent", enabledFor(null))
        assertTrue(enabledFor(true))
        assertTrue(enabledFor("yes"))
        assertTrue("an object is not a switch", enabledFor(JSONObject().put("on", false)))

        assertFalse(enabledFor(false))
        assertFalse(enabledFor(0))
        assertFalse(enabledFor(" Off "))
        assertFalse(enabledFor("no"))
        assertTrue("nothing to report", sink.pushed.isEmpty())
    }

    @Test
    fun `config JSON that does not parse leaves events on and is reported once as a warning`() {
        assertTrue(SellwildEvents.isEnabled("<html>maintenance</html>"))

        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE, event.action)
        assertEquals("remoteConfig", event.label)
        assertEquals("warn", event.attributes["severity"])
        assertEquals("JSONException", event.attributes["errName"])
    }
}
