package com.sellwild.sdk.failures

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.SellwildAPIClient
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildEventQueue
import com.sellwild.sdk.SellwildPrebidMobile
import com.sellwild.sdk.SellwildSDK
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.factories.ListingsResponseFactory
import com.sellwild.sdk.support.CapturedRequest
import com.sellwild.sdk.support.ContractEmitter
import com.sellwild.sdk.support.ContractSchemas
import com.sellwild.sdk.support.FixtureLoader
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.concurrent.atomic.AtomicInteger

/**
 * End to end on Android: configure() fails before any Context exists, the failure is held,
 * and each production path that attaches the process-wide queue (attach, the first
 * [SellwildEventQueue.shared], prewarm, the first [SellwildAPIClient] fetch) sends it as a
 * clientFailure in the real events POST body. [HttpStub] answers the CDN, the listings cache
 * and the events endpoint in-process.
 */
@RunWith(RobolectricTestRunner::class)
class FailuresWiringTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val context: Context = ApplicationProvider.getApplicationContext()

    private val listingsUrl = "https://cache.sellwild.com/listings-img-data-sm"

    /** The CDN answers [configs] in turn (the last one repeats); the default is S3's 403 for a missing config. */
    private fun stub(configs: List<StubResponse> = listOf(missingConfig())): HttpStub {
        val fetches = AtomicInteger()
        return HttpStub.install { url ->
            when (url.host) {
                "widget.sellwild.com" -> configs[minOf(fetches.getAndIncrement(), configs.size - 1)]
                "cache.sellwild.com" -> StubResponse(200, ListingsResponseFactory.withItems(ListingFactory.build()).toString())
                "events.sellwild.com" -> StubResponse(200)
                else -> null
            }
        }
    }

    private fun missingConfig() = StubResponse(403, FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml"))

    /** track() posts from the queue's IO scope; wait for it before the stub closes. */
    private fun HttpStub.awaitEventsPost(): CapturedRequest {
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            requests.firstOrNull { it.url.host == "events.sellwild.com" }?.let { return it }
            Thread.sleep(10)
        }
        throw AssertionError("no events POST within 10 s; requests: ${requests.map { it.url }}")
    }

    @Test
    fun `a configure failure held before any Context goes out through the shared queue`() {
        val failedAt = 1_790_000_000_000L
        SellwildFailures.clock = { failedAt }
        val request = stub().use { stub ->
            runBlocking { SellwildSDK.configure("weatherbug", "weatherbug-main") }
            assertEquals(1, SellwildFailures.pendingCount)
            assertTrue(stub.requests.none { it.url.host == "events.sellwild.com" })

            SellwildFailures.attach(context)

            stub.awaitEventsPost()
        }

        assertEquals("POST", request.method)
        assertEquals("https://events.sellwild.com/events/queue", request.url.toString())
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals("keep-alive", request.headers["Connection"])
        val body = request.bodyText()
        ContractSchemas.assertValid("events-batch", body)
        val event = JSONArray(body).getJSONObject(0)
        assertEquals("clientFailure", event.getString("event"))
        assertEquals("config.fetch.http", event.getString("action"))
        assertEquals("remoteConfig", event.getString("label"))
        assertEquals(SellwildEventQueue.shared(context).uid, event.getString("uid"))
        assertEquals("the time of the failure, not of the attach", failedAt, event.getLong("createdTime"))
        val attributes = event.getJSONObject("attributes")
        assertEquals("weatherbug", attributes.getString("code"))
        assertEquals("android", attributes.getString("client"))
        assertEquals("android", attributes.getString("type"))
        assertEquals(SellwildSDK.SDK_VERSION, attributes.getString("clientVersion"))
        assertEquals("403", attributes.getString("httpStatus"))
        assertEquals("widget.sellwild.com", attributes.getString("host"))
        assertEquals(0, SellwildFailures.pendingCount)
        ContractEmitter.emitText("events-batch", "android-config-fetch-http", body)
    }

    /** Fails configure() while no queue exists, runs [attachBy], and returns the events POST. */
    private fun heldConfigFailureSentBy(attachBy: () -> Unit): CapturedRequest = stub().use { stub ->
        runBlocking { SellwildSDK.configure("weatherbug", "weatherbug-main") }
        assertEquals(1, SellwildFailures.pendingCount)

        attachBy()

        assertEquals(0, SellwildFailures.pendingCount)
        stub.awaitEventsPost()
    }

    @Test
    fun `creating the shared queue sends the failures held before it`() {
        val request = heldConfigFailureSentBy { SellwildEventQueue.shared(context) }

        val event = JSONArray(request.bodyText()).getJSONObject(0)
        assertEquals("clientFailure", event.getString("event"))
        assertEquals("config.fetch.http", event.getString("action"))
        assertEquals(SellwildEventQueue.shared(context).uid, event.getString("uid"))
    }

    @Test
    fun `prewarm sends the failures held since configure`() {
        // mockkObject cannot stub an object inside Robolectric's sandbox, so mark the ad
        // stack as already started: bootstrap() then returns true without touching
        // Prebid or GMA, and nothing else in prewarm creates the queue.
        val started = SellwildPrebidMobile::class.java.getDeclaredField("didBootstrap").apply { isAccessible = true }
        val before = started.getBoolean(null)
        started.setBoolean(null, true)
        try {
            val request = heldConfigFailureSentBy {
                assertTrue(SellwildSDK.prewarm(context, SellwildConfig(partnerCode = "weatherbug")))
            }

            val event = JSONArray(request.bodyText()).getJSONObject(0)
            assertEquals("config.fetch.http", event.getString("action"))
            assertEquals("weatherbug", event.getJSONObject("attributes").getString("code"))
        } finally {
            started.setBoolean(null, before)
        }
    }

    @Test
    fun `a feed-only app sends them on its first listings fetch`() {
        val client = SellwildAPIClient(context)

        val request = heldConfigFailureSentBy {
            runBlocking { client.fetchListings(SellwildConfig(partnerCode = "weatherbug", listingsUrl = listingsUrl)) }.getOrThrow()
        }

        val event = JSONArray(request.bodyText()).getJSONObject(0)
        assertEquals("config.fetch.http", event.getString("action"))
        assertEquals(SellwildEventQueue.shared(context).uid, event.getString("uid"))
    }

    @Test
    fun `a localized cache fetch attaches them too`() {
        val request = heldConfigFailureSentBy {
            runBlocking { SellwildAPIClient(context).fetchCacheListings("$listingsUrl-TX") }.getOrThrow()
        }

        assertEquals("config.fetch.http", JSONArray(request.bodyText()).getJSONObject(0).getString("action"))
    }

    @Test
    fun `held failures are dropped when the config loaded since turns events off`() {
        val eventsOff = StubResponse(200, AppConfigFactory.withFailureFlags(null, null, eventsEnabled = false).toString())
        stub(listOf(missingConfig(), eventsOff)).use { stub ->
            runBlocking { SellwildSDK.configure("weatherbug", "weatherbug-main") }
            assertEquals(1, SellwildFailures.pendingCount)
            runBlocking { SellwildSDK.configure("weatherbug", "weatherbug-main") }
            assertEquals(false, SellwildFailures.context.eventsEnabled)

            // What SellwildAdView does: create the queue (which attaches), then set its switch.
            SellwildEventQueue.shared(context).enabled = false

            assertEquals(0, SellwildFailures.pendingCount)
            assertEquals(0, SellwildFailures.gateState.sessionCount)
            // Nothing was pushed, so no POST was launched.
            assertTrue(stub.requests.none { it.url.host == "events.sellwild.com" })
        }
    }

    @Test
    fun `attaching again replays nothing and keeps the one shared queue`() {
        val queue = SellwildEventQueue.shared(context)
        // Attached: a failure is decided at once instead of held. The kill switch keeps
        // it off the wire.
        queue.enabled = false
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig")
        assertEquals(0, SellwildFailures.pendingCount)
        assertEquals(1, SellwildFailures.gateState.sessionCount)

        SellwildFailures.attach(context)
        SellwildFailures.attach(context)

        assertSame(queue, SellwildEventQueue.shared(context))
        assertEquals(1, SellwildFailures.gateState.sessionCount)
        assertEquals(0, SellwildFailures.internalErrorCount)
    }

    @Test
    fun `the queue uid persists in SharedPreferences`() {
        val first = SellwildEventQueue(context).uid

        val second = SellwildEventQueue(context).uid

        assertEquals(first, second)
        assertEquals(first, context.getSharedPreferences("sellwild_sdk", Context.MODE_PRIVATE).getString("_sw_uid", null))
    }
}
