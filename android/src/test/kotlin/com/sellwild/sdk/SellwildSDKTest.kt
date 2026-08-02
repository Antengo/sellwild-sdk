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
    fun `apply reads AD_REFRESH_INTERVAL as milliseconds`() {
        val base = SellwildConfig(partnerCode = "weatherbug")
        // AD_REFRESH_INTERVAL is milliseconds (matches web + CMS); stored as-is.
        val raw = JSONObject(mapOf("AD_REFRESH_INTERVAL" to 30000.0))

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

    /**
     * Validates that when the remote config provides LISTINGS pointing to
     * cache.sellwild.com, the SDK uses that URL instead of the api.sellwild.com
     * fallback. This is the WeatherBug production scenario.
     */
    @Test
    fun `apply uses cache_sellwild_com LISTINGS from remote config`() {
        val base = SellwildConfig(partnerCode = "weatherbug")
        val raw = JSONObject(
            mapOf(
                "CODE" to "weatherbug",
                "SLUG" to "weatherbug-weatherbug",
                "LISTINGS" to "https://cache.sellwild.com/listings-img-data-sm-ferrarichat",
                "APP_BUNDLE_ID" to "com.aws.weatherbug.pro",
            )
        )

        val merged = SellwildSDK.apply(raw, base)

        // CRITICAL: listingsUrl must be the CDN URL, not the fallback
        assertEquals(
            "https://cache.sellwild.com/listings-img-data-sm-ferrarichat",
            merged.listingsUrl,
        )
        // And effectiveListingsUrl must return the same since listingsUrl is set
        assertEquals(
            "https://cache.sellwild.com/listings-img-data-sm-ferrarichat",
            merged.effectiveListingsUrl,
        )
        // Verify other fields populated correctly
        assertEquals("weatherbug-weatherbug", merged.slug)
        assertEquals("com.aws.weatherbug.pro", merged.appBundleId)
    }

    /**
     * Validates the failure case: when a developer uses SellwildConfig directly
     * without calling configure(), listingsUrl is null and effectiveListingsUrl
     * falls back to api.sellwild.com — which returns 404.
     */
    @Test
    fun `static config without remote fetch uses api_sellwild_com fallback`() {
        // This is the WRONG pattern that caused WeatherBug's 404 issue
        val config = SellwildConfig(
            partnerCode = "weatherbug",
            slug = "weatherbug-weatherbug",
        )

        // listingsUrl is null because remote config was never fetched
        assertNull(config.listingsUrl)
        // effectiveListingsUrl falls back to the deprecated endpoint
        assertEquals(
            "https://api.sellwild.com/widget/listings?partner=weatherbug",
            config.effectiveListingsUrl,
        )
    }
}
