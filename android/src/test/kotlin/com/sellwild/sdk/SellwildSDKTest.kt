package com.sellwild.sdk

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SellwildSDKTest {

    @Test
    fun `apply populates identity fields from CDN keys`() {
        val base = SellwildConfig(partnerCode = "weatherbug")
        val raw = JSONObject(
            mapOf(
                "CODE" to "weatherbug",
                "SLUG" to "weatherbug-main",
                "NAME" to "WeatherBug",
                "LISTINGS" to "https://api.sellwild.com/widget/listings?partner=weatherbug",
            )
        )

        val merged = SellwildSDK.apply(raw, base)

        assertEquals("weatherbug", merged.partnerCode)
        assertEquals("weatherbug-main", merged.slug)
        assertEquals("WeatherBug", merged.name)
        assertEquals(
            "https://api.sellwild.com/widget/listings?partner=weatherbug",
            merged.listingsUrl,
        )
    }

    @Test
    fun `apply converts AD_REFRESH_INTERVAL seconds to milliseconds`() {
        val base = SellwildConfig(partnerCode = "weatherbug")
        val raw = JSONObject(mapOf("AD_REFRESH_INTERVAL" to 30.0))

        val merged = SellwildSDK.apply(raw, base)

        assertEquals(30_000L, merged.adRefreshIntervalMs)
    }

    @Test
    fun `apply populates app identity`() {
        val base = SellwildConfig(partnerCode = "weatherbug")
        val raw = JSONObject(
            mapOf(
                "APP_BUNDLE_ID" to "com.aws.android",
                "APP_STORE_URL" to "https://play.google.com/store/apps/details?id=com.aws.android",
            )
        )

        val merged = SellwildSDK.apply(raw, base)

        assertEquals("com.aws.android", merged.appBundleId)
        assertEquals(
            "https://play.google.com/store/apps/details?id=com.aws.android",
            merged.appStoreUrl,
        )
    }

    @Test
    fun `apply ignores unknown keys`() {
        val base = SellwildConfig(partnerCode = "weatherbug")
        val raw = JSONObject(mapOf("FUTURE_FEATURE_FLAG" to true))

        val merged = SellwildSDK.apply(raw, base)

        assertEquals("weatherbug", merged.partnerCode)
    }

    @Test
    fun `effectiveListingsUrl falls back when null`() {
        val config = SellwildConfig(partnerCode = "weatherbug")

        assertNull(config.listingsUrl)
        assertEquals(
            "https://api.sellwild.com/widget/listings?partner=weatherbug",
            config.effectiveListingsUrl,
        )
    }

    @Test
    fun `effectiveListingsUrl prefers explicit value`() {
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            listingsUrl = "https://custom.example.com/listings",
        )

        assertEquals("https://custom.example.com/listings", config.effectiveListingsUrl)
    }

    @Test
    fun `partnerCode-only constructor works`() {
        val config = SellwildConfig(partnerCode = "weatherbug")
        assertEquals("weatherbug", config.partnerCode)
        assertNull(config.listingsUrl)
    }
}
