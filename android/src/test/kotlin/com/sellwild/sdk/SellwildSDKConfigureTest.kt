package com.sellwild.sdk

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.failures.SellwildLog
import com.sellwild.sdk.support.FixtureLoader
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.runBlocking
import org.json.JSONException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException

/**
 * configure() sets the failure context (partner before the fetch, remote flags after) and
 * reports a failed config fetch once, as config.fetch.*, then falls back to defaults.
 * [HttpStub] answers the CDN in-process; nothing leaves the JVM.
 */
class SellwildSDKConfigureTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()
    private val configUrl = "https://widget.sellwild.com/app/weatherbug/weatherbug-main.json"

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun configure(
        response: StubResponse?,
        overrides: ((SellwildConfig) -> SellwildConfig)? = null,
    ): SellwildConfig = HttpStub.install { url -> response.takeIf { url.toString() == configUrl } }.use {
        runBlocking { SellwildSDK.configure("weatherbug", "weatherbug-main", overrides = overrides) }
    }

    @Test
    fun `a good config sets the partner and the raw remote flags, and logs nothing`() {
        val body = FixtureLoader.text("fixtures/app-config/valid/failures-text-values.json")

        val config = configure(StubResponse(200, body))

        assertEquals("fixture", config.partnerCode)
        assertEquals(body, config.remoteJson)
        assertTrue(sink.pushed.isEmpty())
        val context = SellwildFailures.context
        assertEquals("fixture", context.partnerCode)
        assertEquals("yes", context.eventsEnabled)
        assertEquals(1, context.failuresEnabled)
        assertEquals("0.5", context.failuresSampleRate)
        assertEquals(false, context.debug)
    }

    @Test
    fun `absent or JSON null flags leave the context unset`() {
        val body = AppConfigFactory.build(mapOf("FAILURES_ENABLED" to JSONObject.NULL)).toString()

        configure(StubResponse(200, body)) { it.copy(debug = true) }

        val context = SellwildFailures.context
        assertNull(context.eventsEnabled)
        assertNull(context.failuresEnabled)
        assertNull(context.failuresSampleRate)
        assertTrue("overrides run before the context is set", context.debug)
        assertTrue(SellwildLog.enabled)
    }

    @Test
    fun `a missing config (S3 403) is logged as config fetch http with the partner`() {
        val xml = FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml")

        val config = configure(StubResponse(403, xml))

        assertEquals(SellwildConfig(partnerCode = "weatherbug"), config)
        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_FETCH_HTTP, event.action)
        assertEquals("remoteConfig", event.label)
        assertEquals("weatherbug", event.attributes["code"])
        assertEquals("403", event.attributes["httpStatus"])
        assertEquals("HTTP 403", event.attributes["msg"])
        assertEquals("widget.sellwild.com", event.attributes["host"])
        assertEquals("error", event.attributes["severity"])
        assertNull(SellwildFailures.context.eventsEnabled)
    }

    @Test
    fun `a body that is not JSON is logged as config fetch parse`() {
        val config = configure(StubResponse(200, "<html>maintenance</html>"))

        assertNull(config.remoteJson)
        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_FETCH_PARSE, event.action)
        assertEquals("JSONException", event.attributes["errName"])
    }

    @Test
    fun `a network failure is logged as config fetch network`() {
        network.expectAttempts()

        val config = configure(null)

        assertEquals(listOf(configUrl), network.attempts)
        assertNull(config.remoteJson)
        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_FETCH_NETWORK, event.action)
        assertEquals("NetworkBlockedException", event.attributes["errName"])
        assertEquals("widget.sellwild.com", event.attributes["host"])
    }

    @Test
    fun `a failure before any queue exists is held with the configure partner`() {
        SellwildFailures.bind(null)

        configure(StubResponse(404))
        SellwildFailures.setContext { it.copy(partnerCode = "someone-else") }
        assertTrue(sink.pushed.isEmpty())
        SellwildFailures.bind(sink)

        val event = sink.pushed.single()
        assertEquals("weatherbug", event.attributes["code"])
        assertEquals("404", event.attributes["httpStatus"])
    }

    @Test
    fun `a second configure clears the last remote flags before its fetch`() {
        val killed = AppConfigFactory.withFailureFlags(false, 0, eventsEnabled = false).toString()
        configure(StubResponse(200, killed))
        assertEquals(false, SellwildFailures.context.failuresEnabled)

        configure(StubResponse(403))

        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_FETCH_HTTP, event.action)
        assertEquals("weatherbug", event.attributes["code"])
    }

    @Test
    fun `thrown errors map to the registry reasons`() {
        assertEquals(SellwildFailureCode.CONFIG_FETCH_TIMEOUT, SellwildSDK.configFailureCode(SocketTimeoutException("read")))
        assertEquals(SellwildFailureCode.CONFIG_FETCH_PARSE, SellwildSDK.configFailureCode(JSONException("x")))
        assertEquals(SellwildFailureCode.CONFIG_FETCH_NETWORK, SellwildSDK.configFailureCode(IOException("reset")))
        assertEquals(SellwildFailureCode.CONFIG_FETCH_NETWORK, SellwildSDK.configFailureCode(SecurityException("INTERNET")))
    }

    @Test
    fun `the config URL is built from partner and slug`() {
        assertEquals(configUrl, SellwildSDK.configUrl("weatherbug", "weatherbug-main"))
    }
}
