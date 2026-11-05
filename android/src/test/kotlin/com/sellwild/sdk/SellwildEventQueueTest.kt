package com.sellwild.sdk

import com.sellwild.sdk.factories.ClientFailureEventFactory
import com.sellwild.sdk.factories.EventsBatchFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.ContractSchemas
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
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
@OptIn(ExperimentalCoroutinesApi::class)
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

    // A9 / FAILURES.md 6.1 item 4: the queue stamped its own partnerCode over the code
    // logFailure set (cleaned and cut to 64), so the two could disagree.
    @Test
    fun `buildBatchJson keeps the code logFailure set on a clientFailure`() {
        val failure = EventsBatchFactory.clientFailure(ClientFailureEventFactory.android(partnerCode = "weatherbug"))
        val bare = failure.copy(attributes = failure.attributes!! - "code")

        val body = buildBatchJson(listOf(failure, bare, EventsBatchFactory.adError()), "queue-partner", "9.9.9")

        ContractSchemas.assertValid("events-batch", body)
        val events = JSONArray(body)
        assertEquals("weatherbug", events.getJSONObject(0).getJSONObject("attributes").getString("code"))
        assertEquals("a clientFailure without a code still gets the partner", "queue-partner", events.getJSONObject(1).getJSONObject("attributes").getString("code"))
        assertEquals("other events keep today's stamping", "queue-partner", events.getJSONObject(2).getJSONObject("attributes").getString("code"))
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
        val body = EventsBatchFactory.android(EventsBatchFactory.adError()).toString()
        val statuses = mapOf("/queue" to 200, "/down" to 503, "/early" to 199)
        val (codes, requests, drained) = HttpStub.install { url -> StubResponse(statuses.getValue(url.path), "reply") }.use { stub ->
            Triple(
                listOf(
                    HttpEventSender.post("https://stub.invalid/queue", body),
                    HttpEventSender.post("https://stub.invalid/down", body),
                    HttpEventSender.post("https://stub.invalid/early", body),
                ),
                stub.requests,
                stub.drained.map { it.path },
            )
        }

        assertEquals(listOf(200, 503, 199), codes)
        // Reading the whole reply is what returns the socket to the keep-alive pool: the body
        // on 2xx, the error body otherwise (a 1xx has neither).
        assertEquals(listOf("/queue", "/down"), drained)
        val request = requests.first()
        assertEquals("POST", request.method)
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals("keep-alive", request.headers["Connection"])
        assertEquals(body, request.bodyText())
    }

    @Test
    fun `a batch rejected with a permanent 4xx is dropped, not retried`() {
        sender.status = 400
        queue.track("adError", label = "43")
        assertEquals(1, queue.failedPosts.get())
        sender.status = 200

        runBlocking { queue.flush() }

        assertEquals("nothing was left to send again", 1, sender.posts.size)
        assertEquals(1, queue.failedPosts.get())
    }

    // ── Retry (origin 81e762d, 1847555) ──────────────────────────────────────

    private val scheduler = TestCoroutineScheduler()

    /** A queue on virtual time, so the 10 s re-flush runs only when the test says. */
    private fun timedQueue(): SellwildEventQueue = SellwildEventQueue(
        uidProvider = { "2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11" },
        sender = sender,
        clock = { now },
        dispatcher = StandardTestDispatcher(scheduler),
    )

    /** The labels of the events in POST [i]. */
    private fun labels(i: Int): List<String> {
        val batch = sender.batch(i)
        return (0 until batch.length()).map { batch.getJSONObject(it).getString("label") }
    }

    private fun runFor(ms: Long) {
        scheduler.advanceTimeBy(ms)
        scheduler.runCurrent()
    }

    @Test
    fun `a 5xx puts the batch back, and one re-flush 10 s later sends it again`() {
        val timed = timedQueue()
        sender.status = 503
        timed.track("adError", label = "43")
        timed.track("adError", label = "44")
        scheduler.runCurrent()
        assertEquals("both tracks failed", 2, sender.posts.size)
        sender.status = 200

        runFor(9_999)
        assertEquals(2, sender.posts.size)
        runFor(1)

        assertEquals("one retry, not one per failure", 3, sender.posts.size)
        assertEquals(listOf("43", "44"), labels(2))
        runFor(60_000)
        assertEquals("nothing is left to send", 3, sender.posts.size)
    }

    @Test
    fun `a network error and a 408 or 429 are retried too, a 413 is not`() {
        val timed = timedQueue()
        sender.error = IOException("events.sellwild.com unreachable")
        timed.track("adError", label = "net")
        scheduler.runCurrent()
        sender.error = null
        sender.status = 429
        runFor(10_000)
        sender.status = 408
        runFor(10_000)
        sender.status = 413
        runFor(10_000)
        assertEquals(4, sender.posts.size)

        sender.status = 200
        runFor(60_000)
        assertEquals("the 413 batch was dropped", 4, sender.posts.size)
        assertEquals(4, timed.failedPosts.get())
    }

    @Test
    fun `a flush sends at most 100 events per POST and drains the rest in follow-ups`() {
        repeat(250) { queue.push("adError", label = "$it") }

        runBlocking { queue.flush() }

        assertEquals(listOf(100, 100, 50), (0 until sender.posts.size).map { sender.batch(it).length() })
        assertEquals("0", sender.batch(0).getJSONObject(0).getString("label"))
        assertEquals("249", sender.batch(2).getJSONObject(49).getString("label"))
    }

    @Test
    fun `the queue keeps the newest 1000 events, dropping the oldest`() {
        repeat(1005) { queue.push("adError", label = "$it") }

        runBlocking { queue.flush() }

        val labels = sender.posts.indices.flatMap(::labels)
        assertEquals(1000, labels.size)
        assertEquals("5", labels.first())
        assertEquals("1004", labels.last())
    }

    @Test
    fun `isRetryableStatus retries 5xx, 408, 429 and anything else outside 2xx and 4xx`() {
        assertEquals(
            listOf(false, false, true, true, true, false, false, true),
            listOf(200, 299, 199, 408, 429, 400, 499, 500).map(SellwildEventQueue::isRetryableStatus),
        )
    }
}
