package com.sellwild.sdk

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the pure-logic helpers on [SellwildAdView].
 *
 * The view itself can't be exercised in plain JUnit — it needs an Android
 * `Context` and a live GMA `AdManagerAdView`. Robolectric / instrumented
 * tests cover that surface; this file pins down the pieces that decide
 * *what* to load: the GAM ad unit ID and the bidder-param passthrough.
 */
class SellwildAdViewTest {

    @Test
    fun `resolveGAMAdUnitID prefers typed gamTag`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            gamTag = "/12345/weatherbug/banner_top",
            remoteJson = JSONObject(mapOf("GAM" to "/99999/cdn/banner")).toString(),
        )

        val unit = SellwildAdView.resolveGAMAdUnitID(config)

        assertEquals("/12345/weatherbug/banner_top", unit)
    }

    @Test
    fun `resolveGAMAdUnitID falls back to remote GAM passthrough`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = JSONObject(mapOf("GAM" to "/99999/cdn/banner")).toString(),
        )

        val unit = SellwildAdView.resolveGAMAdUnitID(config)

        assertEquals("/99999/cdn/banner", unit)
    }

    @Test
    fun `resolveGAMAdUnitID falls back to GMA test ad unit when nothing is set`() {
        val config = SellwildConfig(partnerCode = "weatherbug")

        val unit = SellwildAdView.resolveGAMAdUnitID(config)

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT, unit)
    }

    @Test
    fun `resolveGAMAdUnitID falls back to test unit when remoteJson lacks GAM`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = JSONObject(mapOf("CODE" to "weatherbug")).toString(),
        )

        val unit = SellwildAdView.resolveGAMAdUnitID(config)

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT, unit)
    }

    @Test
    fun `bidderParamsFromRemote returns empty when remoteJson is null`() {
        val config = SellwildConfig(partnerCode = "weatherbug")

        val params = SellwildAdView.bidderParamsFromRemote(config)

        assertTrue(params.isEmpty())
    }

    @Test
    fun `bidderParamsFromRemote returns empty when remoteJson is malformed`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = "not-json",
        )

        val params = SellwildAdView.bidderParamsFromRemote(config)

        assertTrue(params.isEmpty())
    }

    @Test
    fun `bidderParamsFromRemote keeps CONSTANT_CASE bidder keys`() {
        val raw = JSONObject(
            mapOf(
                "MEDIANET" to JSONObject(mapOf("cid" to "8CU9V99R6")),
                "AMX" to JSONObject(mapOf("tagId" to "MainAd")),
                "SOVRN" to JSONObject(mapOf("tagid" to "1234")),
            )
        )
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = raw.toString(),
        )

        val params = SellwildAdView.bidderParamsFromRemote(config)

        assertEquals(setOf("MEDIANET", "AMX", "SOVRN"), params.keys)
    }

    @Test
    fun `bidderParamsFromRemote skips first-class typed keys`() {
        val raw = JSONObject(
            mapOf(
                "CODE" to "weatherbug",
                "LISTINGS" to "https://cache.sellwild.com/listings",
                "S2S_CONFIG" to JSONObject(mapOf("endpoint" to "https://prebid.sellwild.com")),
                "GAM" to "/12345/weatherbug/banner",
                "BANNER_ZID" to 43,
                "MEDIANET" to JSONObject(mapOf("cid" to "8CU9V99R6")),
            )
        )
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = raw.toString(),
        )

        val params = SellwildAdView.bidderParamsFromRemote(config)

        // Only the bidder slipped through; everything in the deny list is gone.
        assertEquals(setOf("MEDIANET"), params.keys)
    }

    @Test
    fun `bidderParamsFromRemote skips non-CONSTANT_CASE keys`() {
        // CDN should never ship lowercase keys, but if it does we don't want
        // them masquerading as bidders.
        val raw = JSONObject(
            mapOf(
                "title" to "Local Deals",
                "MEDIANET" to JSONObject(mapOf("cid" to "8CU9V99R6")),
            )
        )
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = raw.toString(),
        )

        val params = SellwildAdView.bidderParamsFromRemote(config)

        assertEquals(setOf("MEDIANET"), params.keys)
    }
}
