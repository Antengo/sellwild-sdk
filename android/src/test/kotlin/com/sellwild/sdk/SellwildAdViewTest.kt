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
    fun `resolveGAMAdUnitID falls back to 320x50 test unit for banner size`() {
        val config = SellwildConfig(partnerCode = "weatherbug")

        val unit = SellwildAdView.resolveGAMAdUnitID(config, AdSize.BANNER_320x50)

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_BANNER, unit)
    }

    @Test
    fun `resolveGAMAdUnitID falls back to adaptive test unit for non-banner sizes`() {
        val config = SellwildConfig(partnerCode = "weatherbug")

        val unit = SellwildAdView.resolveGAMAdUnitID(config, AdSize.MREC_300x250)

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_ADAPTIVE, unit)
    }

    @Test
    fun `resolveGAMAdUnitID defaults to adaptive test unit when size unspecified`() {
        val config = SellwildConfig(partnerCode = "weatherbug")

        val unit = SellwildAdView.resolveGAMAdUnitID(config)

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_ADAPTIVE, unit)
    }

    @Test
    fun `resolveGAMAdUnitID falls back to test unit when remoteJson lacks GAM`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = JSONObject(mapOf("CODE" to "weatherbug")).toString(),
        )

        val unit = SellwildAdView.resolveGAMAdUnitID(config, AdSize.BANNER_320x50)

        assertEquals(SellwildAdView.GAM_TEST_AD_UNIT_BANNER, unit)
    }
}
