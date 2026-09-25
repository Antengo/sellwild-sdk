package com.sellwild.sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** SellwildConfig defaults, its JSON form, and the other public config types. */
class SellwildConfigTest {

    @Test
    fun `default config has expected values`() {
        val config = SellwildConfig(partnerCode = "test_partner", listingsUrl = "https://cache.sellwild.com/listings-img-data-sm")

        assertEquals("test_partner", config.partnerCode)
        assertEquals(16, config.titleSize)
        assertEquals(13, config.fontSize)
        assertFalse(config.boltive)
        assertFalse(config.lotame)
        assertFalse(config.debug)
        assertEquals(30_000L, config.adRefreshIntervalMs)
        assertFalse(config.hideBannerTop)
        assertFalse(config.hideBannerBottom)
    }

    @Test
    fun `toJson writes every field, and the optional ones only when set`() {
        val full = SellwildConfig(
            partnerCode = "mypartner",
            title = "Deals",
            gamTag = "/1234/fixture",
            gptProxyUrl = "https://gpt.invalid/proxy",
            boltive = true,
            boltiveClientId = "antengo",
            debug = true,
        ).toJson()
        val bare = SellwildConfig(partnerCode = "mypartner", linkText = null, buyNowText = null).toJson()

        assertEquals("mypartner", full.getString("partnerCode"))
        assertEquals(SellwildConfig.DEFAULT_LISTINGS_URL, full.getString("listingsUrl"))
        assertEquals("Deals", full.getString("title"))
        assertEquals("View all", full.getString("linkText"))
        assertEquals("Buy now", full.getString("buyNowText"))
        assertEquals("/1234/fixture", full.getString("gamTag"))
        assertEquals("https://gpt.invalid/proxy", full.getString("gptProxyUrl"))
        assertTrue(full.getBoolean("boltive"))
        assertEquals("antengo", full.getString("boltiveClientId"))
        assertTrue(full.getBoolean("debug"))
        assertEquals(30_000L, full.getLong("adRefreshInterval"))
        for (key in listOf("title", "linkText", "buyNowText", "gamTag", "gptProxyUrl")) assertFalse(key, bare.has(key))
        assertEquals(25, bare.length())
    }

    @Test
    fun `an empty listings URL falls back to the general cache`() {
        assertEquals(SellwildConfig.DEFAULT_LISTINGS_URL, SellwildConfig(partnerCode = "p", listingsUrl = "").effectiveListingsUrl)
        assertEquals(SellwildConfig.DEFAULT_LISTINGS_URL, SellwildConfig(partnerCode = "p").effectiveListingsUrl)
        assertEquals("https://c.invalid/x", SellwildConfig(partnerCode = "p", listingsUrl = "https://c.invalid/x").effectiveListingsUrl)
    }

    @Test
    fun `AdSize has the IAB dimensions and a WxH label`() {
        assertEquals(
            listOf("320x50", "300x250", "728x90", "300x600", "160x600"),
            AdSize.values().map { it.label },
        )
        assertEquals(320, AdSize.BANNER_320x50.width)
        assertEquals(250, AdSize.MREC_300x250.height)
    }

    @Suppress("DEPRECATION")
    @Test
    fun `the settings types keep what they are given`() {
        val growth = SellwildGrowthCodeConfig(true, "pid", "https://gc.invalid", "weatherbug.com", false, 12)
        val localized = SellwildLocalizedListingsConfig(true, "sportserver", "https://c.invalid/", "x-{state}.json", 25, "AL")
        val server = PrebidServerConfig("acct", "https://pbs.invalid/openrtb2/auction", listOf("appnexus"), 900, "https://pbs.invalid/cookie_sync")
        val ix = IxConfig(siteIdM = "m", siteIdD = "d")
        val openx = OpenxConfig(delDomain = "x.openx.net", unitM = "1", unitD = "2")
        val pubmatic = PubmaticConfig(pubIdM = "p", adSlotM = "m", adSlotD = "d")
        val appnexus = AppnexusConfig(placementIdM = 1, placementIdD = 2)
        val waterfall = WaterfallPartnerConfig(false, 0.1f, 0.2f, "a", "b", "c", "d", 0.5f, 0.6f, 3, 60_000L, "US")

        assertEquals(12, growth.ttlHours)
        assertEquals("AL", localized.forceState)
        assertEquals(1500, PrebidServerConfig("acct", "https://pbs.invalid", emptyList()).timeout)
        assertEquals(900, server.timeout)
        assertFalse(ix.disabled || openx.disabled || pubmatic.disabled || appnexus.disabled || waterfall.disabled)
        assertEquals("US", waterfall.geo)
        assertEquals(
            SellwildConfig(partnerCode = "p", growthCode = growth, localizedListings = localized, prebidServer = server, ix = ix),
            SellwildConfig(partnerCode = "p").copy(growthCode = growth, localizedListings = localized, prebidServer = server, ix = ix),
        )
    }
}
