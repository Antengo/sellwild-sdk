package com.sellwild.sdk

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * The CDN ships `S2S_CONFIG` as a JS object-literal string; pin that the
 * tolerant parser reads it (and real JSON) and rejects garbage.
 */
class SellwildS2SConfigTest {

    /** Verbatim shape of the live weatherbug CDN value. */
    private val liveSample = """
        [{
          accountId: 'weatherbug',
          bidders: ['ix', 'medianet'],
          adapter: 'prebidServer',
          enabled: true,
          endpoint: {
            p1Consent: 'https://prebid.sellwild.com/openrtb2/auction',
            noP1Consent: 'https://prebid.sellwild.com/openrtb2/auction'
          },
          syncEndpoint: {
            p1Consent: 'https://prebid.sellwild.com/cookie_sync',
            noP1Consent: 'https://prebid.sellwild.com/cookie_sync'
          },
          timeout: 1300
        }]
    """.trimIndent()

    @Test
    fun `parses live JS-literal sample`() {
        assertEquals(
            SellwildS2SConfig("weatherbug", "https://prebid.sellwild.com/openrtb2/auction", 1300),
            SellwildS2SConfig.parse(liveSample),
        )
    }

    @Test
    fun `parses JS literal with trailing commas and escaped quotes`() {
        val s = "{ accountId: 'it\\'s \"x\"', endpoint: 'https://a.example/auction', timeout: 900, bidders: ['ix',], }"
        assertEquals(
            SellwildS2SConfig("it's \"x\"", "https://a.example/auction", 900),
            SellwildS2SConfig.parse(s),
        )
    }

    @Test
    fun `parses JSON string object and array`() {
        val obj = """{"accountId":"acct","endpoint":"https://b.example/auction","timeout":1500}"""
        val expected = SellwildS2SConfig("acct", "https://b.example/auction", 1500)
        assertEquals(expected, SellwildS2SConfig.parse(obj))
        assertEquals(expected, SellwildS2SConfig.parse("[$obj]"))
    }

    @Test
    fun `parses already-decoded object and array`() {
        val o = JSONObject(mapOf("account" to "acct", "url" to "https://c.example/auction"))
        val expected = SellwildS2SConfig("acct", "https://c.example/auction", null)
        assertEquals(expected, SellwildS2SConfig.parse(o))
        assertEquals(expected, SellwildS2SConfig.parse(JSONArray().put(o)))
    }

    @Test
    fun `garbage returns null`() {
        assertNull(SellwildS2SConfig.parse(null))
        assertNull(SellwildS2SConfig.parse(""))
        assertNull(SellwildS2SConfig.parse("not a config"))
        assertNull(SellwildS2SConfig.parse("[{ accountId: 'unterminated"))
        assertNull(SellwildS2SConfig.parse("[]"))
        assertNull(SellwildS2SConfig.parse("{ enabled: true }"))
        assertNull(SellwildS2SConfig.parse(42))
    }

    @Test
    fun `resolvePrebidServer reads the S2S_CONFIG string form`() {
        val raw = JSONObject().put("S2S_CONFIG", liveSample)
        val config = SellwildConfig(partnerCode = "other", remoteJson = raw.toString())

        val resolved = SellwildPrebidMobile.resolvePrebidServer(config, remoteRoot = raw)

        assertEquals("https://prebid.sellwild.com/openrtb2/auction", resolved.url)
        assertEquals("weatherbug", resolved.accountId)
        assertEquals(1300, resolved.timeout)
    }

    @Test
    fun `per-config fields overlay keeps prior values for absent fields`() {
        val applied = SellwildPrebidMobile.PerConfigFields(
            serverUrl = "https://a/auction", accountId = "a", timeout = 1300, publisherId = "123",
        )
        val bare = SellwildPrebidMobile.perConfigFields(SellwildConfig(partnerCode = "a"), remoteRoot = null)
        assertEquals(applied, bare.overlaying(applied))

        val changed = SellwildPrebidMobile.PerConfigFields(accountId = "b").overlaying(applied)
        assertEquals("b", changed.accountId)
        assertEquals("123", changed.publisherId)
    }
}
