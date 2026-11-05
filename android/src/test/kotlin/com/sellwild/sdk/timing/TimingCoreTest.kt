package com.sellwild.sdk.timing

import com.sellwild.sdk.failures.plain
import com.sellwild.sdk.failures.value
import com.sellwild.sdk.support.ContractSchemas
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/** The timing core reproduces contracts/golden/sdk-timing.vectors.json (FAILURES.md 18.1). */
class TimingCoreTest {

    private val golden = FixtureLoader.jsonObject("golden/sdk-timing.vectors.json")

    private fun TimingEvent.toPlain(): Map<String, Any?> = mapOf(
        "event" to event,
        "action" to action,
        "label" to label,
        "attributes" to attributes,
        "uid" to uid,
        "createdTime" to createdTime,
    )

    @Test
    fun `every vector`() {
        val vectors = golden.getJSONArray("vectors")
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            val name = v.getString("name")
            val c = v.getJSONObject("context")
            val input = v.getJSONObject("input")
            val expected = v.getJSONObject("expected")
            val decision = TimingCore.decideTiming(
                TimingState(v.getJSONObject("stateBefore").getInt("sessionCount")),
                TimingInput(input.value("step"), input.value("ms"), input.value("zoneId")),
                TimingContext(
                    partnerCode = c.value("partnerCode"),
                    client = c.value("client"),
                    clientVersion = c.value("clientVersion"),
                    appId = c.value("appId"),
                    appVersion = c.value("appVersion"),
                    os = c.value("os"),
                    device = c.value("device"),
                    net = c.value("net"),
                    eventsEnabled = c.value("eventsEnabled"),
                    timingEnabled = c.value("timingEnabled"),
                    timingSampleRate = c.value("timingSampleRate"),
                ),
                c.value("uid") as String?,
                c.getLong("now"),
            )
            assertEquals("$name event", plain(expected.get("event")), decision.event?.toPlain())
            assertEquals("$name reason", expected.value("reason"), decision.reason)
            assertEquals(
                "$name state",
                expected.getJSONObject("stateAfter").getInt("sessionCount"),
                decision.state.sessionCount
            )
            decision.event?.let {
                assertEquals(
                    "$name wire order",
                    TimingCore.ATTRIBUTE_KEYS.filter { k -> k in it.attributes },
                    it.attributes.keys.toList()
                )
                ContractSchemas.assertValid(
                    "sdk-timing-event",
                    JSONObject(it.toPlain().mapValues { (_, x) -> if (x is Map<*, *>) JSONObject(x) else x })
                )
            }
        }
    }

    private fun rows(table: String): List<JSONObject> {
        val list = golden.getJSONObject("units").getJSONArray(table)
        return (0 until list.length()).map { list.getJSONObject(it) }
    }

    private fun JSONArray.arg(i: Int): Any? = opt(i)?.takeIf { it != JSONObject.NULL }

    @Test
    fun `unit tables`() {
        for (row in rows("budgetFor")) {
            val args = row.getJSONArray("input")
            assertEquals("$args", plain(row.opt("expected")), TimingCore.budgetFor(args.arg(0), args.arg(1)))
        }
        for (row in rows("isSlow")) {
            val args = row.getJSONArray("input")
            assertEquals("$args", row.getBoolean("expected"), TimingCore.isSlow(args.arg(0), args.arg(1), args.arg(2)))
        }
        for (row in rows("timingRate")) {
            assertEquals(
                "${row.opt("input")}",
                row.getDouble("expected"),
                TimingCore.timingRate(row.value("input")),
                0.0
            )
        }
    }

    @Test
    fun `limits, budgets and codes match the golden file`() {
        val limits = golden.getJSONObject("limits")
        assertEquals(TimingCore.DEFAULT_RATE, limits.getDouble("defaultRate"), 0.0)
        assertEquals(TimingCore.SESSION_TIMINGS, limits.getInt("sessionTimings"))
        assertEquals(TimingCore.MAX_MS, limits.getDouble("maxMs"), 0.0)
        assertEquals(plain(golden.getJSONObject("budgets")), TimingCore.BUDGETS)
        assertEquals(plain(golden.getJSONObject("budgetKeys")), TimingCore.BUDGET_KEYS)
        assertEquals(plain(golden.getJSONObject("slowCodes")), TimingCore.SLOW_CODES)
        assertEquals(plain(golden.getJSONArray("steps")), TimingCore.STEPS)
    }

    @Test
    fun `edge values the golden file cannot carry`() {
        assertEquals(null, TimingCore.parseBudgetMs(Double.NaN))
        assertEquals(null, TimingCore.parseBudgetMs(0.5))
        assertEquals(12L, TimingCore.parseBudgetMs("+12"))
        assertEquals(null, TimingCore.parseBudgetMs(true))
        assertEquals(TimingCore.DEFAULT_RATE, TimingCore.timingRate(Double.POSITIVE_INFINITY), 0.0)
        assertEquals(TimingCore.DEFAULT_RATE, TimingCore.timingRate(true), 0.0)
        assertEquals(false, TimingCore.isTimingSampled(null, 0.01))
        val ctx = TimingContext(timingSampleRate = 1)
        assertEquals(
            "invalid_ms",
            TimingCore.decideTiming(null, TimingInput("config.fetch", Double.NaN), ctx, "u", 1).reason
        )
        assertEquals(
            "invalid_ms",
            TimingCore.decideTiming(null, TimingInput("config.fetch", Double.POSITIVE_INFINITY), ctx, "u", 1).reason
        )
        assertEquals(
            "7",
            TimingCore.decideTiming(null, TimingInput("config.fetch", 7), ctx, null, 1).event?.attributes?.get("ms")
        )
        assertEquals(false, TimingCore.isSlow("config.fetch", Double.NaN, null))
    }

    @Test
    fun `null state, input and context are empty, and a non-number budget source is none`() {
        assertEquals("invalid_step", TimingCore.decideTiming(null, null, null, null, 1).reason)
        assertEquals(3000L, TimingCore.budgetFor("config.fetch", "not a map"))
        assertEquals(1500L, TimingCore.budgetFor("config.fetch", mapOf("TIMING_BUDGET_CONFIG_MS" to 1500)))
        assertEquals(false, TimingCore.isSlow("config.fetch", "9999", null))
    }
}
