package com.sellwild.sdk

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for [SellwildGpid] — GPID base resolution (`GPID_BASE_BY_ZONE`
 * override → `GPID_BASE` global fallback → null) and the shared imp-ext JSON
 * builder (`imp.ext.gpid` == `imp.ext.data.pbadslot`, plus the optional
 * `imp.ext.prebid.bidder` block). Parity with iOS SellwildGpidTests.
 */
class SellwildGpidTest {

    // ── resolveBase ──────────────────────────────────────────────────────────

    @Test
    fun `by-zone override wins over global`() {
        val json = """{"GPID_BASE":"/global/slot","GPID_BASE_BY_ZONE":{"43":"/zone/43"}}"""
        assertEquals("/zone/43", SellwildGpid.resolveBase(json, "43"))
    }

    @Test
    fun `falls back to global when zone absent from by-zone`() {
        val json = """{"GPID_BASE":"/global/slot","GPID_BASE_BY_ZONE":{"43":"/zone/43"}}"""
        assertEquals("/global/slot", SellwildGpid.resolveBase(json, "99"))
    }

    @Test
    fun `global fallback used when no by-zone object`() {
        assertEquals("/global/slot", SellwildGpid.resolveBase("""{"GPID_BASE":"/global/slot"}""", "43"))
    }

    @Test
    fun `neither present resolves null`() {
        assertNull(SellwildGpid.resolveBase("""{"SOMETHING_ELSE":"x"}""", "43"))
    }

    @Test
    fun `null and blank remoteJson resolve null`() {
        assertNull(SellwildGpid.resolveBase(null, "43"))
        assertNull(SellwildGpid.resolveBase("", "43"))
        assertNull(SellwildGpid.resolveBase("not json", "43"))
    }

    @Test
    fun `null zone still resolves global`() {
        assertEquals("/global/slot", SellwildGpid.resolveBase("""{"GPID_BASE":"/global/slot"}""", null))
    }

    @Test
    fun `empty base string treated as absent`() {
        assertNull(SellwildGpid.resolveBase("""{"GPID_BASE":""}""", "43"))
        assertNull(SellwildGpid.resolveBase("""{"GPID_BASE_BY_ZONE":{"43":""},"GPID_BASE":""}""", "43"))
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
