package com.sellwild.sdk

import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.ContractSchemas
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The events queue with an injected sender, uid, clock and dispatcher. Dispatchers.Unconfined
 * runs track()'s flush in place, so every POST has happened when the call returns.
 */
class SellwildEventQueueTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private class FakeSender : SellwildEventSender {
        val posts = CopyOnWriteArrayList<Pair<String, String>>()
        var status = 200
        var error: Throwable? = null

        override fun post(url: String, body: String): Int {
            posts += url to body
            error?.let { throw it }
            return status
        }

        fun batch(i: Int): JSONArray = JSONArray(posts[i].second)
    }

    private val sender = FakeSender()
    private var now = 1_790_000_000_000L
    private var uidReads = 0
    private val queue = SellwildEventQueue(
        uidProvider = { uidReads++; "2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11" },
        sender = sender,
        clock = { now },
        dispatcher = Dispatchers.Unconfined,
    ).apply { partnerCode = "weatherbug" }

    @Test
    fun `push with attributes sends them in the bag with the stamped keys`() {
        queue.push("adError", action = "Request Error", label = "43", attributes = mapOf("reason" to "timeout", "tries" to 2))

        runBlocking { queue.flush() }

        assertEquals(SellwildEventQueue.EVENTS_URL, sender.posts.single().first)
        val event = sender.batch(0).getJSONObject(0)
        assertEquals("adError", event.getString("event"))
        assertEquals("Request Error", event.getString("action"))
        assertEquals("43", event.getString("label"))
        assertEquals("2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11", event.getString("uid"))
        assertEquals(now, event.getLong("createdTime"))
        val attributes = event.getJSONObject("attributes")
        assertEquals(setOf("reason", "tries", "type", "sdkVersion", "code"), attributes.keys().asSequence().toSet())
        assertEquals("timeout", attributes.getString("reason"))
        assertEquals(2, attributes.getInt("tries"))
        assertEquals("android", attributes.getString("type"))
        assertEquals(SellwildSDK.SDK_VERSION, attributes.getString("sdkVersion"))
        assertEquals("weatherbug", attributes.getString("code"))
        ContractSchemas.assertValid("events-batch", sender.posts.single().second)
    }

    @Test
    fun `Android does not batch - every track is its own POST`() {
        queue.track("adRenderSucceeded", label = "43")
        queue.track("firstAdViewed")

        assertEquals(2, sender.posts.size)
        assertEquals(listOf(1, 1), (0..1).map { sender.batch(it).length() })
        assertEquals("firstAdViewed", sender.batch(1).getJSONObject(0).getString("event"))
        assertFalse(sender.batch(1).getJSONObject(0).has("label"))
    }

    @Test
    fun `flush sends everything pushed as one batch, then nothing`() {
        queue.push("click", label = "43")
        queue.push("click", label = "280")

        runBlocking {
            queue.flush()
            queue.flush()
        }

        assertEquals(1, sender.posts.size)
        assertEquals(2, sender.batch(0).length())
    }

    @Test
    fun `track is a no-op while the kill switch is off`() {
        queue.enabled = false

        queue.track("click")
        queue.track(SellwildEvent(event = "clientFailure", uid = "u", createdTime = now))
        runBlocking { queue.flush() }

        assertTrue(sender.posts.isEmpty())
    }

    @Test
    fun `an event built elsewhere keeps its uid and createdTime`() {
        queue.track(SellwildEvent(event = "clientFailure", action = "a.b.c", uid = "core-uid", createdTime = 1_800_000_000_000L))

        val event = sender.batch(0).getJSONObject(0)
        assertEquals("core-uid", event.getString("uid"))
        assertEquals(1_800_000_000_000L, event.getLong("createdTime"))
    }

    @Test
    fun `the uid is read once, lazily`() {
        assertEquals(0, uidReads)

        queue.push("a")
        queue.push("b")

        assertEquals(1, uidReads)
        assertEquals(queue.uid, "2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11")
    }

    @Test
    fun `buildBatchJson stamps type, sdkVersion and a non-empty partner over caller keys`() {
        val batch = listOf(
            SellwildEvent(event = "e", attributes = mapOf("type" to "ios", "code" to "caller", "keep" to true), uid = "u", createdTime = now),
        )

        val stamped = JSONArray(buildBatchJson(batch, "partner", "9.9.9")).getJSONObject(0).getJSONObject("attributes")
        val noPartner = JSONArray(buildBatchJson(batch, "", "9.9.9")).getJSONObject(0).getJSONObject("attributes")
        val nullPartner = JSONArray(buildBatchJson(batch, null, "9.9.9")).getJSONObject(0)

        assertEquals("android", stamped.getString("type"))
        assertEquals("9.9.9", stamped.getString("sdkVersion"))
        assertEquals("partner", stamped.getString("code"))
        assertTrue(stamped.getBoolean("keep"))
        assertEquals("caller", noPartner.getString("code"))
        assertEquals("caller", nullPartner.getJSONObject("attributes").getString("code"))
        assertFalse(nullPartner.has("action"))
        assertFalse(nullPartner.has("label"))
    }

    @Test
    fun `transport never reports itself - failed POSTs are counted, not logged or printed`() {
        val sink = FakeFailureSink()
        SellwildFailures.bind(sink)
        SellwildFailures.setContext { it.copy(debug = true) }

        sender.error = IOException("events.sellwild.com unreachable")
        queue.track("adError", label = "43")
        sender.error = RuntimeException("sender bug")
        queue.track("adError", label = "43")
        sender.error = null
        sender.status = 503
        queue.track("adError", label = "43")

        assertEquals(3, sender.posts.size)
        assertEquals(3, queue.failedPosts.get())
        assertTrue("no clientFailure was pushed", sink.pushed.isEmpty())
        assertEquals(0, SellwildFailures.gateState.sessionCount)
        assertEquals(0, SellwildFailures.pendingCount)
        assertEquals(0, SellwildFailures.internalErrorCount)
        assertEquals(emptyList<String>(), failures.lines)
    }

    @Test
    fun `the production sender POSTs JSON on a kept-alive socket and returns the status`() {
        val (codes, requests) = HttpStub.install { url -> StubResponse(if (url.path == "/down") 503 else 200, "reply") }.use { stub ->
            listOf(
                HttpEventSender.post("https://stub.invalid/queue", """[{"event":"click"}]"""),
                HttpEventSender.post("https://stub.invalid/down", "[]"),
            ) to stub.requests
        }

        assertEquals(listOf(200, 503), codes)
        val request = requests.first()
        assertEquals("POST", request.method)
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals("keep-alive", request.headers["Connection"])
        assertEquals("""[{"event":"click"}]""", request.bodyText())
    }

    @Test
    fun `a failed batch is dropped, not retried`() {
        sender.status = 500
        queue.track("adError", label = "43")
        sender.status = 200

        runBlocking { queue.flush() }

        assertEquals(1, sender.posts.size)
        assertEquals(1, queue.failedPosts.get())
    }
}
