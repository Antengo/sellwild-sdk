package com.sellwild.sdk.failures

import android.util.Log
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowLog

/** Robolectric, so the default printer reaches a real (shadowed) Logcat. */
@RunWith(RobolectricTestRunner::class)
class SellwildLogTest {

    @get:Rule
    val failures = FailuresRule()

    @Test
    fun `prints nothing and builds nothing while disabled`() {
        var built = false

        SellwildLog.debug("plain")
        SellwildLog.debug { built = true; "lazy" }

        assertEquals(emptyList<String>(), failures.lines)
        assertFalse(built)
    }

    @Test
    fun `prints both forms when enabled`() {
        SellwildLog.enabled = true

        SellwildLog.debug("plain")
        SellwildLog.debug { "lazy" }

        assertEquals(listOf("plain", "lazy"), failures.lines)
    }

    @Test
    fun `setContext debug turns it on and off`() {
        SellwildFailures.setContext { it.copy(debug = true) }
        SellwildLog.debug("on")
        SellwildFailures.setContext { it.copy(debug = false) }
        SellwildLog.debug("off")

        assertEquals(listOf("on"), failures.lines)
    }

    @Test
    fun `the default printer writes debug lines to logcat under the Sellwild tag`() {
        SellwildLog.resetForTests()
        SellwildLog.enabled = true
        ShadowLog.clear()

        SellwildLog.debug("to logcat")

        val logs = ShadowLog.getLogsForTag(SellwildLog.TAG)
        assertEquals(listOf("to logcat"), logs.map { it.msg })
        assertEquals(listOf(Log.DEBUG), logs.map { it.type })
        assertEquals(emptyList<String>(), failures.lines)
    }
}
