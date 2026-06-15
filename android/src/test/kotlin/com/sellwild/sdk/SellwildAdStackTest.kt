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
    fun `resolve defaults to BOTH when nothing is set`() {
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(null, "43"))
        val empty = JSONObject(mapOf("CODE" to "weatherbug")).toString()
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(empty, "43"))
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
        // Unlisted zone falls back to BOTH.
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(json, "7"))
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
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve("not-json", "43"))
    }

    @Test
    fun `ad-stack keys are not forwarded as bidder params`() {
        val raw = JSONObject(
            mapOf(
                "AD_STACK" to "PREBID",
                "AD_STACK_BY_ZONE" to JSONObject(mapOf("43" to "GAM")),
                "MEDIANET" to JSONObject(mapOf("cid" to "8CU9V99R6")),
            )
        )
        val config = SellwildConfig(partnerCode = "weatherbug", remoteJson = raw.toString())

        val params = SellwildAdView.bidderParamsFromRemote(config)

        // Only the real bidder slips through; AD_STACK* are in the deny list.
        assertEquals(setOf("MEDIANET"), params.keys)
    }
}
