package com.sellwild.sdk.guards

import com.sellwild.sdk.failures.SellwildFailureCode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Which earlier process exits are reported (FAILURES.md 18.2), on recorded ApplicationExitInfo shapes. */
class ExitReasonsTest {

    // The head of a real ANR dump (traces.txt format): the main thread first, then others.
    private val anr = """
        ----- pid 4321 at 2026-10-30 10:00:00 -----
        Cmd line: com.aws.weatherbug

        "main" prio=5 tid=1 Blocked
          | group="main" sCount=1 ucsCount=0 flags=1 obj=0x72a3f6d8 self=0xb400007a1c210be0
          at com.sellwild.sdk.SellwildFeedView.load(SellwildFeedView.kt:262)
          - waiting to lock <0x0a1b2c3d> (a java.lang.Object) held by thread 12
          at com.sellwild.sdk.SellwildFeedView.refresh(SellwildFeedView.kt:318)
          at android.os.Handler.dispatchMessage(Handler.java:106)

        "OkHttp Dispatcher" prio=5 tid=12 Native
          at java.net.SocketInputStream.socketRead0(Native method)
    """.trimIndent()

    private fun record(reason: Int, at: Long, description: String? = null, trace: String? = null) =
        ExitRecord(reason, at, description, trace)

    @Test
    fun `the first launch with the SDK reports nothing and remembers the newest exit`() {
        val decision = ExitReasons.decide(
            listOf(record(ExitReasons.REASON_LOW_MEMORY, 10), record(ExitReasons.REASON_ANR, 20, trace = anr)),
            null
        )

        assertEquals(emptyList<ExitReport>(), decision.reports)
        assertEquals(20L, decision.lastSeen)
        assertEquals(ExitReasons.Decision(emptyList(), null), ExitReasons.decide(emptyList(), null))
    }

    @Test
    fun `only exits newer than the last one seen are reported, oldest first`() {
        val decision = ExitReasons.decide(
            listOf(
                record(ExitReasons.REASON_ANR, 300, "user request after error: Input dispatching timed out", anr),
                record(ExitReasons.REASON_LOW_MEMORY, 200),
                record(ExitReasons.REASON_LOW_MEMORY, 100),
            ),
            lastSeen = 150,
        )

        val codes = decision.reports.map { it.code }
        assertEquals(listOf(SellwildFailureCode.SDK_MEMORY_KILLED, SellwildFailureCode.SDK_HANG_TIMEOUT), codes)
        assertEquals(300L, decision.lastSeen)
        val hang = decision.reports[1]
        assertEquals("error", hang.severity)
        assertEquals("ANR: user request after error: Input dispatching timed out", hang.message)
        assertEquals(
            "com.sellwild.sdk.SellwildFeedView.load(SellwildFeedView.kt:262)\n" +
                "com.sellwild.sdk.SellwildFeedView.refresh(SellwildFeedView.kt:318)\n" +
                "android.os.Handler.dispatchMessage(Handler.java:106)",
            hang.stack,
        )
        assertEquals("killed for low memory", decision.reports[0].message)
        assertNull(decision.reports[0].stack)
    }

    @Test
    fun `crashes and ANRs count only when they mention Sellwild`() {
        val decision = ExitReasons.decide(
            listOf(
                record(
                    ExitReasons.REASON_CRASH,
                    2,
                    "java.lang.IllegalStateException at com.sellwild.sdk.SellwildAdView.load"
                ),
                record(ExitReasons.REASON_CRASH, 3, "java.lang.NullPointerException in com.example.Main"),
                record(ExitReasons.REASON_CRASH_NATIVE, 4, "signal 11 in libsellwild? no: com.sellwild.prebid"),
                record(ExitReasons.REASON_ANR, 5, "ANR", "\"main\" prio=5\n  at com.example.Main.run(Main.kt:1)"),
                record(ExitReasons.REASON_CRASH, 6, " "),
                record(13, 7, "com.sellwild user requested"),
            ),
            lastSeen = 1,
        )

        assertEquals(
            listOf(
                Triple(
                    SellwildFailureCode.SDK_CRASH_EXCEPTION,
                    "fatal",
                    "crash: java.lang.IllegalStateException at com.sellwild.sdk.SellwildAdView.load"
                ),
                Triple(
                    SellwildFailureCode.SDK_CRASH_EXCEPTION,
                    "fatal",
                    "native crash: signal 11 in libsellwild? no: com.sellwild.prebid"
                ),
            ),
            decision.reports.map { Triple(it.code, it.severity, it.message) },
        )
        assertNull("a crash has no trace text", decision.reports[0].stack)
        assertEquals(7L, decision.lastSeen)
    }

    @Test
    fun `sdkFrames takes the first thread with a Sellwild frame, at most 30 frames`() {
        assertNull(ExitReasons.sdkFrames(null))
        assertNull(ExitReasons.sdkFrames("\"main\"\n  at com.example.A.b(A.kt:1)"))
        assertNull("a Sellwild mention with no frames", ExitReasons.sdkFrames("com.sellwild only"))
        val deep = "\"main\"\n" + (1..40).joinToString("\n") { "  at com.sellwild.sdk.F.f$it(F.kt:$it)" }
        assertEquals(30, checkNotNull(ExitReasons.sdkFrames(deep)).lines().size)
    }
}
