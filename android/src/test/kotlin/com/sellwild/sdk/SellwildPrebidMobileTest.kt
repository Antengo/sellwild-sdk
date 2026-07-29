package com.sellwild.sdk

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SellwildPrebidMobileTest {

    @Test
    fun `resolvePrebidServer prefers typed prebidServer config`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            prebidServer = PrebidServerConfig(
                accountId = "abc-123",
                endpoint = "https://prebid.example.com/openrtb2/auction",
                bidders = listOf("appnexus"),
            ),
        )

        val resolved = SellwildPrebidMobile.resolvePrebidServer(config, remoteRoot = null)

        assertEquals("https://prebid.example.com/openrtb2/auction", resolved.url)
        assertEquals("abc-123", resolved.accountId)
    }

    @Test
    fun `resolvePrebidServer falls back to S2S_CONFIG passthrough`() {
        val raw = JSONObject(
            mapOf(
                "S2S_CONFIG" to JSONObject(
                    mapOf(
                        "endpoint" to "https://prebid-cdn.example.com/openrtb2/auction",
                        "accountId" to "cdn-account",
                    )
                )
            )
        )
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = raw.toString(),
        )

        val resolved = SellwildPrebidMobile.resolvePrebidServer(config, remoteRoot = raw)

        assertEquals("https://prebid-cdn.example.com/openrtb2/auction", resolved.url)
        assertEquals("cdn-account", resolved.accountId)
    }

    @Test
    fun `resolvePrebidServer falls back to Sellwild defaults`() {
        val config = SellwildConfig(partnerCode = "weatherbug")

        val resolved = SellwildPrebidMobile.resolvePrebidServer(config, remoteRoot = null)

        assertEquals("https://prebid.sellwild.com/openrtb2/auction", resolved.url)
        assertEquals("weatherbug", resolved.accountId)
    }

    @Test
    fun `ortbExtJson returns null for empty params`() {
        assertNull(SellwildPrebidMobile.ortbExtJson(emptyMap()))
    }

    @Test
    fun `ortbExtJson lowercases bidder names and wraps as imp ext prebid bidder`() {
        val params = mapOf(
            "MEDIANET" to JSONObject(mapOf("cid" to "8CU9V99R6")),
            "AMX" to JSONObject(mapOf("tagId" to "MainAd")),
        )

        val json = SellwildPrebidMobile.ortbExtJson(params)

        assertNotNull(json)
        val parsed = JSONObject(json!!)
        val bidder = parsed
            .getJSONObject("ext")
            .getJSONObject("prebid")
            .getJSONObject("bidder")
        assertTrue(bidder.has("medianet"))
        assertTrue(bidder.has("amx"))
        assertFalse(bidder.has("MEDIANET"))
    }

    @Test
    fun `ortbExtJson skips null values`() {
        val params = mapOf<String, Any?>(
            "MEDIANET" to null,
            "AMX" to JSONObject(mapOf("tagId" to "MainAd")),
        )

        val json = SellwildPrebidMobile.ortbExtJson(params)

        assertNotNull(json)
        val bidder = JSONObject(json!!)
            .getJSONObject("ext")
            .getJSONObject("prebid")
            .getJSONObject("bidder")
        assertEquals(1, bidder.length())
        assertTrue(bidder.has("amx"))
    }
}
