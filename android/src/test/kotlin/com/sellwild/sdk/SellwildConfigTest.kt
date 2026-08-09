package com.sellwild.sdk

import org.junit.Assert.*
import org.junit.Test

class SellwildConfigTest {

    @Test
    fun `default config has expected values`() {
        val config = SellwildConfig(
            partnerCode = "test_partner",
            listingsUrl = "https://cache.sellwild.com/listings-img-data-sm"
        )

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
    fun `toJson includes required fields`() {
        val config = SellwildConfig(
            partnerCode = "mypartner",
            listingsUrl = "https://cache.sellwild.com/listings-img-data-sm",
            boltive = true,
            boltiveClientId = "antengo",
            debug = true,
        )

        val json = config.toJson()
        assertEquals("mypartner", json.getString("partnerCode"))
        assertTrue(json.getBoolean("boltive"))
        assertEquals("antengo", json.getString("boltiveClientId"))
        assertTrue(json.getBoolean("debug"))
    }

    @Test
    fun `AdSize dimensions are correct`() {
        assertEquals(320, AdSize.BANNER_320x50.width)
        assertEquals(50, AdSize.BANNER_320x50.height)
        assertEquals(300, AdSize.MREC_300x250.width)
        assertEquals(250, AdSize.MREC_300x250.height)
        assertEquals(728, AdSize.LEADERBOARD_728x90.width)
        assertEquals(90, AdSize.LEADERBOARD_728x90.height)
    }
}
