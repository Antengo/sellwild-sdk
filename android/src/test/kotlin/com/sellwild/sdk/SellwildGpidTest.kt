package com.sellwild.sdk

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/**
 * Unit tests for [SellwildGpid] — GPID base resolution (`GPID_BASE_BY_ZONE`
 * override → `GPID_BASE` global fallback → null) and the shared imp-ext JSON
 * builder (`imp.ext.gpid` == `imp.ext.data.pbadslot`, plus the optional
 * `imp.ext.prebid.bidder` block). Parity with iOS SellwildGpidTests.
 */
class SellwildGpidTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun config(vararg entries: Pair<String, Any?>): String = AppConfigFactory.checked(mapOf(*entries)).toString()

    private val byZone = JSONObject().put("43", "/zone/43")

    // ── resolveBase ──────────────────────────────────────────────────────────

    @Test
    fun `by-zone override wins over global`() {
        assertEquals("/zone/43", SellwildGpid.resolveBase(config("GPID_BASE" to "/global/slot", "GPID_BASE_BY_ZONE" to byZone), "43"))
    }

    @Test
    fun `falls back to global when zone absent from by-zone`() {
        assertEquals("/global/slot", SellwildGpid.resolveBase(config("GPID_BASE" to "/global/slot", "GPID_BASE_BY_ZONE" to byZone), "99"))
    }

    @Test
    fun `global fallback used when no by-zone object`() {
        assertEquals("/global/slot", SellwildGpid.resolveBase(config("GPID_BASE" to "/global/slot"), "43"))
        assertEquals("/global/slot", SellwildGpid.resolveBase(config("GPID_BASE" to "/global/slot", "GPID_BASE_BY_ZONE" to ""), "43"))
    }

    @Test
    fun `neither present resolves null`() {
        assertNull(SellwildGpid.resolveBase(config(), "43"))
    }

    @Test
    fun `no remote config resolves null, and config that does not parse is reported`() {
        assertNull(SellwildGpid.resolveBase(null, "43"))
        assertNull(SellwildGpid.resolveBase("", "43"))
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })

        assertNull(SellwildGpid.resolveBase(FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml"), "43"))
        assertEquals(listOf(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE), sink.pushed.map { it.action })
    }

    @Test
    fun `null zone still resolves global`() {
        assertEquals("/global/slot", SellwildGpid.resolveBase(config("GPID_BASE" to "/global/slot"), null))
    }

    @Test
    fun `empty base string treated as absent`() {
        assertNull(SellwildGpid.resolveBase(config("GPID_BASE" to ""), "43"))
        assertNull(SellwildGpid.resolveBase(config("GPID_BASE_BY_ZONE" to JSONObject().put("43", ""), "GPID_BASE" to ""), "43"))
        assertNull(SellwildGpid.resolveBase(AppConfigFactory.offSchema(mapOf("GPID_BASE" to JSONObject.NULL)).toString(), "43"))
    }

    // ── impExtJson ───────────────────────────────────────────────────────────

    @Test
    fun `gpid only sets both gpid and pbadslot to same value`() {
        val ext = JSONObject(SellwildGpid.impExtJson("/zone/43")!!).getJSONObject("ext")
        assertEquals("/zone/43", ext.getString("gpid"))
        assertEquals("/zone/43", ext.getJSONObject("data").getString("pbadslot"))
        // No bidder params supplied → no prebid.bidder block.
        assertFalse(ext.has("prebid"))
    }

    @Test
    fun `gpid plus bidder params carries both blocks`() {
        val ext = JSONObject(
            SellwildGpid.impExtJson("/zone/43", mapOf("IX" to mapOf("siteId" to "123")))!!,
        ).getJSONObject("ext")
        assertEquals("/zone/43", ext.getString("gpid"))
        assertEquals("/zone/43", ext.getJSONObject("data").getString("pbadslot"))
        // Bidder names lowercased (CDN ships CONSTANT_CASE).
        assertTrue(ext.getJSONObject("prebid").getJSONObject("bidder").has("ix"))
    }

    @Test
    fun `bidder params only omits gpid and pbadslot`() {
        val ext = JSONObject(
            SellwildGpid.impExtJson(null, mapOf("IX" to "x"))!!,
        ).getJSONObject("ext")
        assertFalse(ext.has("gpid"))
        assertFalse(ext.has("data"))
        assertTrue(ext.getJSONObject("prebid").getJSONObject("bidder").has("ix"))
    }

    @Test
    fun `no gpid and no bidder params returns null`() {
        assertNull(SellwildGpid.impExtJson(null))
        assertNull(SellwildGpid.impExtJson(""))
        assertNull(SellwildGpid.impExtJson(null, mapOf("IX" to null)))
    }

    @Test
    fun `occurrence-suffixed value flows through unchanged`() {
        val ext = JSONObject(SellwildGpid.impExtJson("/global/slot#2")!!).getJSONObject("ext")
        assertEquals("/global/slot#2", ext.getString("gpid"))
        assertEquals("/global/slot#2", ext.getJSONObject("data").getString("pbadslot"))
    }
}
