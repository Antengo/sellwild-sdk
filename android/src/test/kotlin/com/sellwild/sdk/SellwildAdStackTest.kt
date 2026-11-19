package com.sellwild.sdk

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for [SellwildAdStack] parsing + resolution. These pin down the
 * decision of WHICH ad SDK stack a placement runs (GAM vs Prebid) before the
 * view touches any Android `Context`.
 */
class SellwildAdStackTest {

    @Test
    fun `parse is case and alias tolerant`() {
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.parse("BOTH"))
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.parse("default"))
        assertEquals(SellwildAdStack.GAM_ONLY, SellwildAdStack.parse("GAM"))
        assertEquals(SellwildAdStack.GAM_ONLY, SellwildAdStack.parse("gam-only"))
        assertEquals(SellwildAdStack.GAM_ONLY, SellwildAdStack.parse("google"))
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.parse("PREBID_ONLY"))
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.parse("prebid"))
    }

    @Test
    fun `parse returns null for unknown or null`() {
        assertNull(SellwildAdStack.parse("xyz"))
        assertNull(SellwildAdStack.parse(null))
    }

    @Test
    fun `resolve defaults to PREBID_ONLY when nothing is set`() {
        // Unknown stack (no remote config, or a config without AD_STACK) must
        // never fall through to a GAM request.
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(null, "43"))
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(null, null))
        val empty = JSONObject(mapOf("CODE" to "acme")).toString()
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(empty, "43"))
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(empty, null))
    }

    @Test
    fun `resolve keeps BOTH when the CMS asks for it explicitly`() {
        val both = JSONObject(mapOf("AD_STACK" to "both")).toString()
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(both, "43"))
        // The CMS value "default" is an explicit alias for BOTH — unchanged.
        val aliased = JSONObject(mapOf("AD_STACK" to "default")).toString()
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(aliased, "43"))
        val byZone = JSONObject(
            mapOf("AD_STACK_BY_ZONE" to JSONObject(mapOf("43" to "both")))
        ).toString()
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(byZone, "43"))
    }

    @Test
    fun `resolve ignores an unrecognised AD_STACK value`() {
        val json = JSONObject(mapOf("AD_STACK" to "xyz")).toString()
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(json, "43"))
    }

    @Test
    fun `resolve hard-wins on global AD_STACK over per-zone`() {
        val json = JSONObject(
            mapOf(
                "AD_STACK" to "PREBID",
                "AD_STACK_BY_ZONE" to JSONObject(mapOf("43" to "GAM")),
            )
        ).toString()

        // Global forces every placement, even ones with a per-zone entry.
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(json, "43"))
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(json, null))
    }

    @Test
    fun `resolve applies per-zone when no global`() {
        val json = JSONObject(
            mapOf(
                "AD_STACK_BY_ZONE" to JSONObject(
                    mapOf("43" to "gamOnly", "99" to "prebidOnly")
                ),
            )
        ).toString()

        assertEquals(SellwildAdStack.GAM_ONLY, SellwildAdStack.resolve(json, "43"))
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(json, "99"))
        // Unlisted zone falls back to the PREBID_ONLY default.
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(json, "7"))
    }

    @Test
    fun `resolve override beats remote config`() {
        val json = JSONObject(mapOf("AD_STACK" to "GAM")).toString()

        assertEquals(
            SellwildAdStack.PREBID_ONLY,
            SellwildAdStack.resolve(json, "43", override = SellwildAdStack.PREBID_ONLY),
        )
    }

    @Test
    fun `resolve tolerates malformed remote json`() {
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve("not-json", "43"))
    }
}
