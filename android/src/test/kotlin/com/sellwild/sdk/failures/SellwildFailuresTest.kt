package com.sellwild.sdk.failures

import android.content.Context
import com.sellwild.sdk.SellwildSDK
import com.sellwild.sdk.support.ContractSchemas
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** The logFailure shell (FAILURES.md 3.4): context, hold-until-attached, echo, reentrancy, never throws. */
class SellwildFailuresTest {

    @get:Rule
    val failures = FailuresRule()

    private var now = 1_790_000_000_000L
    private val sink = FakeFailureSink()

    private fun attached(): FakeFailureSink {
        SellwildFailures.clock = { now }
        SellwildFailures.bind(sink)
        return sink
    }

    @Test
    fun `log sends one event with the android context and the sink uid`() {
        attached()
        SellwildFailures.setContext { it.copy(partnerCode = "weatherbug") }

        SellwildFailures.log(
            code = SellwildFailureCode.LISTINGS_FETCH_HTTP,
            component = SellwildFailureComponent.LISTINGS,
            message = "HTTP 503",
            httpStatus = 503,
            url = "https://cache.sellwild.com/listings-img-data-sm?v=2",
            zoneId = "43",
        )

        val event = sink.pushed.single()
        assertEquals("clientFailure", event.event)
        assertEquals("listings.fetch.http", event.action)
        assertEquals("listings", event.label)
        assertEquals(VECTOR_UID, event.uid)
        assertEquals(now, event.createdTime)
        assertEquals(
            linkedMapOf(
                "code" to "weatherbug",
                "client" to "android",
                "clientVersion" to SellwildSDK.SDK_VERSION,
                "severity" to "error",
                "fv" to "1",
                "msg" to "HTTP 503",
                "httpStatus" to "503",
                "host" to "cache.sellwild.com",
                "zoneId" to "43",
                "seq" to "1",
                "repeat" to "1",
            ),
            event.attributes,
        )
        assertEquals(listOf(true), sink.flushes)
        assertEquals(1, SellwildFailures.gateState.sessionCount)
        ContractSchemas.assertValid("client-failure-event", event.toJson())
    }

    @Test
    fun `the gate keeps its state between calls`() {
        attached()

        repeat(3) { SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", message = "HTTP 403") }
        now += FailuresCore.DEDUPE_WINDOW_MS
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", message = "HTTP 403")
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig")

        assertEquals(listOf("1", "2", "3"), sink.pushed.map { it.attributes["seq"] })
        assertEquals(listOf("1", "3", "1"), sink.pushed.map { it.attributes["repeat"] })
        assertEquals(listOf(true, false, false), sink.flushes)
    }

    @Test
    fun `an error gives errName, message and its first frames without a header`() {
        attached()
        val error = IOException("boom at https://cache.sellwild.com/x?q=1").apply {
            stackTrace = arrayOf(
                StackTraceElement("com.sellwild.sdk.SellwildAPIClient", "fetchListings", "SellwildAPI.kt", 122),
                StackTraceElement("com.sellwild.sdk.SellwildFeedView", "load", "SellwildFeedView.kt", -1),
                StackTraceElement("java.lang.Thread", "run", null, -1),
                StackTraceElement("a.B", "c", "B.kt", 1),
                StackTraceElement("a.B", "d", "B.kt", 2),
                StackTraceElement("a.B", "sixth", "B.kt", 6),
            )
        }

        SellwildFailures.log(code = "listings.fetch.network", component = "listings", error = error, message = "fetch failed")

        val attributes = sink.pushed.single().attributes
        assertEquals("IOException", attributes["errName"])
        assertEquals("fetch failed: boom at cache.sellwild.com", attributes["msg"])
        assertEquals(
            listOf(
                "com.sellwild.sdk.SellwildAPIClient.fetchListings(SellwildAPI.kt:122)",
                "com.sellwild.sdk.SellwildFeedView.load(SellwildFeedView.kt)",
                "java.lang.Thread.run(Unknown Source)",
                "a.B.c(B.kt:1)",
                "a.B.d(B.kt:2)",
            ).joinToString("\n"),
            attributes["stack"],
        )
    }

    @Test
    fun `an anonymous error class sends no errName`() {
        attached()

        SellwildFailures.log(code = "config.fetch.network", component = "remoteConfig", error = object : RuntimeException("x") {})

        assertFalse(sink.pushed.single().attributes.containsKey("errName"))
    }

    @Test
    fun `calls before a sink is attached are held, then decided with their own time and context`() {
        SellwildFailures.clock = { now }
        SellwildFailures.setContext { it.copy(partnerCode = "early") }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", httpStatus = 403)
        SellwildFailures.setContext { it.copy(partnerCode = "late", failuresEnabled = false) }
        now += 5_000

        assertEquals(1, SellwildFailures.pendingCount)
        assertTrue(sink.pushed.isEmpty())

        SellwildFailures.bind(sink)

        val event = sink.pushed.single()
        assertEquals("early", event.attributes["code"])
        assertEquals(now - 5_000, event.createdTime)
        assertEquals(VECTOR_UID, event.uid)
        assertEquals(listOf(true), sink.flushes)
        assertEquals(0, SellwildFailures.pendingCount)
    }

    @Test
    fun `held calls are dropped when the events switch set since is off`() {
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", httpStatus = 403)
        SellwildFailures.setContext { it.copy(eventsEnabled = " OFF ") }

        SellwildFailures.bind(sink)

        assertTrue(sink.pushed.isEmpty())
        assertEquals(0, SellwildFailures.pendingCount)
        assertEquals(FailureState(), SellwildFailures.gateState)
        SellwildFailures.setContext { it.copy(eventsEnabled = 1) }
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig")
        assertEquals("dropped, not held for later", listOf("config.fetch.parse"), sink.pushed.map { it.action })
    }

    @Test
    fun `the hold keeps one session of calls and drops the rest`() {
        SellwildFailures.setContext { it.copy(debug = true) }

        repeat(FailuresCore.SESSION_EMITS + 1) { i ->
            SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", message = "call $i")
        }

        assertEquals(FailuresCore.SESSION_EMITS, SellwildFailures.pendingCount)
        assertEquals(
            "[Sellwild] failure config.fetch.http remoteConfig error held call 0",
            failures.lines.first(),
        )
        assertEquals(
            "[Sellwild] failure config.fetch.http remoteConfig error held_full call 20",
            failures.lines.last(),
        )
        SellwildFailures.bind(sink)
        assertEquals((0 until FailuresCore.SESSION_EMITS).map { "call $it" }, sink.pushed.map { it.attributes["msg"] })
    }

    @Test
    fun `binding the same sink again replays nothing twice, and a null sink holds calls again`() {
        attached()
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        SellwildFailures.bind(sink)
        assertEquals(1, sink.pushed.size)

        SellwildFailures.bind(null)
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig")

        assertEquals(1, sink.pushed.size)
        assertEquals(1, SellwildFailures.pendingCount)
    }

    @Test
    fun `the debug echo prints one line per call, only when debug is on`() {
        attached()
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", message = "quiet")
        assertTrue(failures.lines.isEmpty())

        SellwildFailures.setContext { it.copy(debug = true) }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", message = "quiet")
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig", message = "jane@example.com")

        assertEquals(
            listOf(
                "[Sellwild] failure config.fetch.http remoteConfig error deduped quiet",
                "[Sellwild] failure config.fetch.parse remoteConfig error sent <email>",
            ),
            failures.lines,
        )
    }

    @Test
    fun `the local failures switch wins over the remote value`() {
        attached()
        SellwildFailures.setContext { it.copy(failuresEnabled = "true", failuresEnabledOverride = false) }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        assertTrue(sink.pushed.isEmpty())

        SellwildFailures.setContext { it.copy(failuresEnabled = "off", failuresEnabledOverride = true) }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        assertEquals(1, sink.pushed.size)
    }

    @Test
    fun `remote flags reach the gate raw`() {
        attached()
        SellwildFailures.setContext { it.copy(eventsEnabled = 0) }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", severity = SellwildFailureSeverity.FATAL)
        SellwildFailures.setContext { it.copy(eventsEnabled = null, failuresSampleRate = "0") }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        assertTrue(sink.pushed.isEmpty())

        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", severity = SellwildFailureSeverity.FATAL)
        assertEquals(listOf("fatal"), sink.pushed.map { it.attributes["severity"] })
    }

    @Test
    fun `setWrapper tags every later event`() {
        attached()
        SellwildFailures.setWrapper("react-native")

        SellwildFailures.log(code = "bridge.props.invalid", component = "bridge")

        assertEquals("react-native", SellwildFailures.context.wrapper)
        assertEquals("react-native", sink.pushed.single().attributes["wrapper"])
    }

    @Test
    fun `a nested call from inside log returns at once`() {
        attached()
        sink.onPush = { SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig") }

        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        sink.onPush = null
        SellwildFailures.log(code = "config.fetch.timeout", component = "remoteConfig")

        assertEquals(listOf("config.fetch.http", "config.fetch.timeout"), sink.pushed.map { it.action })
        assertEquals(0, SellwildFailures.internalErrorCount)
    }

    @Test
    fun `failures inside log are counted and echoed, never thrown`() {
        attached()
        SellwildFailures.setContext { it.copy(debug = true) }
        sink.onPush = { throw IllegalStateException("sink down") }

        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        SellwildFailures.clock = { throw ArithmeticException("clock down") }
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig")

        assertEquals(2, SellwildFailures.internalErrorCount)
        assertEquals(
            listOf(
                "[Sellwild] failure internal java.lang.IllegalStateException",
                "[Sellwild] failure internal java.lang.ArithmeticException",
            ),
            failures.lines,
        )
    }

    @Test
    fun `a printer that throws is counted for the echo and for the internal echo, and nothing escapes`() {
        attached()
        SellwildFailures.setContext { it.copy(debug = true) }
        SellwildLog.printer = { throw IllegalStateException("printer down") }

        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")

        assertEquals(2, SellwildFailures.internalErrorCount)
        // The event went out before the echo failed.
        assertEquals(listOf("config.fetch.http"), sink.pushed.map { it.action })
    }

    @Test
    fun `setContext and bind never throw, and one failed replay does not stop the rest`() {
        SellwildFailures.setContext { throw IllegalArgumentException("bad update") }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig")
        sink.onPush = { if (it.action == "config.fetch.http") throw IllegalStateException("sink down") }

        SellwildFailures.bind(sink)

        assertEquals(2, SellwildFailures.internalErrorCount)
        assertEquals(listOf("config.fetch.parse"), sink.pushed.map { it.action })
        assertNull(SellwildFailures.context.partnerCode)
    }

    @Test
    fun `held calls the gate drops are not sent`() {
        repeat(2) { SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", message = "same") }

        SellwildFailures.bind(sink)

        assertEquals(1, sink.pushed.size)
        assertEquals(1, SellwildFailures.gateState.keys.single().suppressed)
    }

    @Test
    fun `a sink whose uid fails is not bound, and the held calls wait for the next one`() {
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        val broken = object : FailureSink {
            override val uid: String get() = throw IllegalStateException("prefs unreadable")
            override fun push(event: FailureEvent, flushNow: Boolean) = Unit
        }

        SellwildFailures.bind(broken)

        assertEquals(1, SellwildFailures.internalErrorCount)
        assertEquals(1, SellwildFailures.pendingCount)
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig")
        assertEquals("still unbound: the next call is held too", 2, SellwildFailures.pendingCount)

        SellwildFailures.bind(sink)

        assertEquals(listOf("config.fetch.http", "config.fetch.parse"), sink.pushed.map { it.action })
        assertEquals(0, SellwildFailures.pendingCount)
    }

    @Test
    fun `the sink uid is read once, when it is bound`() {
        var reads = 0
        val counting = object : FailureSink {
            override val uid: String get() = VECTOR_UID.also { reads++ }
            override fun push(event: FailureEvent, flushNow: Boolean) = sink.push(event, flushNow)
        }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")

        SellwildFailures.bind(counting)
        SellwildFailures.log(code = "config.fetch.parse", component = "remoteConfig")
        SellwildFailures.log(code = "config.fetch.timeout", component = "remoteConfig")

        assertEquals(1, reads)
        assertEquals(listOf(VECTOR_UID, VECTOR_UID, VECTOR_UID), sink.pushed.map { it.uid })
    }

    @Test
    fun `attach with a Context that fails is counted, not thrown`() {
        val context = mockk<Context>()
        every { context.applicationContext } throws IllegalStateException("no app context")

        SellwildFailures.attach(context)

        assertEquals(1, SellwildFailures.internalErrorCount)
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        assertEquals("still held: nothing was attached", 1, SellwildFailures.pendingCount)
    }

    @Test
    fun `concurrent calls on other threads are all reported`() {
        attached()
        val pool = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        try {
            repeat(FailuresCore.SESSION_EMITS) { i ->
                pool.execute {
                    start.await()
                    SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig", message = "thread $i")
                }
            }
            start.countDown()
        } finally {
            pool.shutdown()
            assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS))
        }

        assertEquals(FailuresCore.SESSION_EMITS, sink.pushed.size)
        assertEquals((1..FailuresCore.SESSION_EMITS).map { "$it" }.toSet(), sink.pushed.map { it.attributes["seq"] }.toSet())
    }

    @Test
    fun `resetForTests clears state, context, hold and counters`() {
        SellwildFailures.setContext { it.copy(partnerCode = "p", debug = true) }
        SellwildFailures.log(code = "config.fetch.http", component = "remoteConfig")
        SellwildFailures.setContext { throw IllegalStateException() }
        SellwildFailures.clock = { 1L }

        SellwildFailures.resetForTests()

        assertEquals(SellwildFailureContext(), SellwildFailures.context)
        assertEquals(0, SellwildFailures.pendingCount)
        assertEquals(0, SellwildFailures.internalErrorCount)
        assertEquals(FailureState(), SellwildFailures.gateState)
        assertFalse(SellwildLog.enabled)
        assertTrue(SellwildFailures.clock() > 1L)
    }
}
