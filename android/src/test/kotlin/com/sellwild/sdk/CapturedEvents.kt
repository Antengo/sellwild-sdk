package com.sellwild.sdk

import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.failures.gateCalls
import com.sellwild.sdk.support.ContractSchemas
import kotlinx.coroutines.Dispatchers
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The process-wide events queue for a test: its POSTs land in [bodies] instead of
 * events.sellwild.com, synchronously (Dispatchers.Unconfined runs track()'s flush in place).
 * [install] makes it the queue [SellwildEventQueue.shared] returns and attaches logFailure to
 * it, so every failure the SDK logs, including from code that attaches by itself (a listings
 * fetch, prewarm), arrives here in its real wire form. Use with FailuresRule, which forgets
 * the shared queue after the test.
 */
internal class CapturedEvents : SellwildEventSender {
    val bodies = CopyOnWriteArrayList<String>()

    val queue = SellwildEventQueue(
        uidProvider = { UID },
        sender = this,
        clock = { NOW },
        dispatcher = Dispatchers.Unconfined,
    )

    override fun post(url: String, body: String): Int {
        bodies += body
        return 200
    }

    fun install(): CapturedEvents = apply {
        SellwildEventQueue.setSharedForTests(queue)
        SellwildFailures.attachQueue(queue)
    }

    /** Every clientFailure sent so far, oldest first. Each POST body matches events-batch. */
    val failures: List<JSONObject>
        get() = bodies.flatMap { body ->
            ContractSchemas.assertValid("events-batch", body)
            val batch = JSONArray(body)
            (0 until batch.length()).map { batch.getJSONObject(it) }
        }.filter { it.getString("event") == "clientFailure" }

    /** The codes of [failures], in order. */
    val codes: List<String> get() = failures.map { it.getString("action") }

    /** Every event sent so far (analytics and clientFailure), oldest first. */
    val all: List<JSONObject>
        get() = bodies.flatMap { body ->
            val batch = JSONArray(body)
            (0 until batch.length()).map { batch.getJSONObject(it) }
        }

    /** The analytics events named [event] (adError, click, placementMismatch ...), oldest first. */
    fun named(event: String): List<JSONObject> = all.filter { it.getString("event") == event }

    /**
     * The one clientFailure sent, after checking it is [code], nothing else was sent, and
     * logFailure was called for it once: the gate's dedupe would hide a second call from
     * [bodies], so the calls are counted before it ([gateCalls]).
     */
    fun single(code: String): JSONObject {
        assertEquals("exactly one clientFailure", listOf(code), codes)
        assertEquals("logFailure calls for $code, counted before the gate", 1, gateCalls(code))
        return failures.single()
    }

    /** The attributes of [single]. */
    fun attributes(code: String): JSONObject = single(code).getJSONObject("attributes")

    companion object {
        const val UID = "2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11"
        const val NOW = 1_790_000_000_000L
    }
}
