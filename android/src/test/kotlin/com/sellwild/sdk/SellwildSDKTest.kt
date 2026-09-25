package com.sellwild.sdk

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.jsonArrayOf
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** SellwildSDK.apply: CDN keys onto SellwildConfig fields. Payloads come from AppConfigFactory. */
class SellwildSDKTest {

    private val base = SellwildConfig(partnerCode = "weatherbug")

    @Test
    fun `every mapped key reaches its field`() {
        val config = SellwildSDK.apply(AppConfigFactory.everyMappedKey(), base)

        assertEquals(
            SellwildConfig(
                partnerCode = "fixture",
                slug = "fixture-app",
                name = "Fixture App",
                listingsUrl = "https://cache.sellwild.com/listings-img-data-sm-fixture",
                title = "Marketplace",
                partnerUrl = "https://sellwild.com/?p=fixture",
                col1 = "LLGB",
                bhTag = "bh-fixture",
                linkText = "More",
                buyNowText = "Get it",
                titleColor = "#111111",
                linkColor = "#222222",
                fontColor = "#333333",
                priceColor = "#444444",
                priceFontColor = "#555555",
                marginBottom = 14,
                colors = listOf("#295baa", "#000000"),
                overlayTitle = true,
                watermark = true,
                watermarkTitle = "By Sellwild",
                bannerZid = "43",
                bottomBannerZid = "44",
                mobileBannerZid = "android-banner",
                mobileZids = listOf("android-feed"),
                hideBannerTop = true,
                hideBannerBottom = true,
                gamTag = "/1234/fixture",
                disableGpt = true,
                adDisableDisplay = true,
                adRefreshMax = 5,
                adRefreshMaxMobile = 6,
                adRefreshIntervalMs = 45_000L,
                maxFailedAuctions = 7,
                gppEnabled = true,
                tcfVersion = 2,
                iabCats = listOf("IAB2", "IAB2-15"),
                enableInterstitial = true,
                enableFullscreenVideo = true,
                interstitialsPerSession = 2,
                videoTakeoversPerSession = 1,
                appBundleId = "com.fixture.android",
                appStoreUrl = "https://play.google.com/store/apps/details?id=com.fixture.android",
                boltive = true,
                boltiveClientId = "boltive-fixture",
                lotame = true,
                debug = true,
                pbsDebug = true,
            ),
            config,
        )
    }

    @Test
    fun `apply accepts IAB_CATS as array or comma-separated string`() {
        val single = SellwildSDK.apply(JSONObject(mapOf("IAB_CATS" to "IAB15")), base)
        assertEquals(listOf("IAB15"), single.iabCats)

        val csv = SellwildSDK.apply(JSONObject(mapOf("IAB_CATS" to " IAB15, IAB19 ,,")), base)
        assertEquals(listOf("IAB15", "IAB19"), csv.iabCats)

        val arr = JSONObject().put("IAB_CATS", org.json.JSONArray(listOf("IAB15", "IAB19")))
        assertEquals(listOf("IAB15", "IAB19"), SellwildSDK.apply(arr, base).iabCats)
    }

    @Test
    fun `absent keys keep the base values`() {
        val custom = base.copy(listingsUrl = "https://cache.sellwild.com/listings-custom", title = "Deals", adRefreshIntervalMs = 60_000L)

        val config = SellwildSDK.apply(AppConfigFactory.checked(), custom)

        assertEquals(custom.copy(partnerCode = "minimal", slug = "minimal", name = "minimal"), config)
    }

    // A9: '' is how the CMS writes an unset LISTINGS. apply copied it over the base URL, so
    // a partner-set listings URL became '' and the feed fell back to the general cache.
    @Test
    fun `an empty LISTINGS keeps the base listings URL, as core does`() {
        val custom = base.copy(listingsUrl = "https://cache.sellwild.com/listings-img-data-sm-ferrarichat")

        val config = SellwildSDK.apply(AppConfigFactory.checked(mapOf("LISTINGS" to "")), custom)

        assertEquals("https://cache.sellwild.com/listings-img-data-sm-ferrarichat", config.listingsUrl)
        assertEquals(config.listingsUrl, config.effectiveListingsUrl)
    }

    @Test
    fun `an empty LISTINGS with no base URL uses the general cache`() {
        val config = SellwildSDK.apply(AppConfigFactory.checked(mapOf("LISTINGS" to "")), base)

        assertNull(config.listingsUrl)
        assertEquals(SellwildConfig.DEFAULT_LISTINGS_URL, config.effectiveListingsUrl)
    }

    @Test
    fun `the Android zone keys win, then MOBILE_ZID_ALL_ANDROID, then the shared keys`() {
        val perOs = SellwildSDK.apply(AppConfigFactory.checked(mapOf("MOBILE_ZID_ANDROID" to jsonArrayOf("a"), "MOBILE_BANNER_ZID_ANDROID" to "b")), base)
        val all = SellwildSDK.apply(
            AppConfigFactory.checked(mapOf("MOBILE_ZID_ANDROID" to jsonArrayOf(), "MOBILE_BANNER_ZID_ANDROID" to "", "MOBILE_ZID_ALL_ANDROID" to "all")),
            base,
        )
        val shared = SellwildSDK.apply(
            AppConfigFactory.checked(mapOf("MOBILE_ZID_ALL_ANDROID" to "", "MOBILE_ZID" to jsonArrayOf("s"), "MOBILE_BANNER_ZID" to 43)),
            base,
        )
        val none = SellwildSDK.apply(AppConfigFactory.offSchema(mapOf("MOBILE_ZID" to null, "MOBILE_ZID_ANDROID" to null)), base.copy(mobileZids = listOf("kept")))

        assertEquals(listOf("a"), perOs.mobileZids)
        assertEquals("b", perOs.mobileBannerZid)
        assertEquals(listOf("all"), all.mobileZids)
        assertEquals("all", all.mobileBannerZid)
        assertEquals(listOf("s"), shared.mobileZids)
        assertEquals("43", shared.mobileBannerZid)
        assertEquals(listOf("kept"), none.mobileZids)
        assertNull(none.mobileBannerZid)
    }

    @Test
    fun `the Android app identity keys win over the shared ones`() {
        val shared = SellwildSDK.apply(
            AppConfigFactory.checked(mapOf("APP_BUNDLE_ID" to "com.aws.android", "APP_STORE_URL" to "https://play.google.com/store/apps/details?id=com.aws.android")),
            base,
        )

        assertEquals("com.aws.android", shared.appBundleId)
        assertEquals("https://play.google.com/store/apps/details?id=com.aws.android", shared.appStoreUrl)
    }

    @Test
    fun `AD_REFRESH_INTERVAL is milliseconds, stored as is`() {
        val config = SellwildSDK.apply(AppConfigFactory.checked(mapOf("AD_REFRESH_INTERVAL" to 30_000.0)), base)

        assertEquals(30_000L, config.adRefreshIntervalMs)
    }

    @Test
    fun `JSON null, arrays and objects where text belongs fall back to the base`() {
        val raw = AppConfigFactory.offSchema(
            mapOf(
                "TITLE" to JSONObject.NULL,
                "MOBILE_BANNER_ZID" to jsonArrayOf(),
                "GAM" to JSONObject().put("unit", "/1/x"),
                "MARGIN_BOTTOM" to JSONObject.NULL,
                "AD_REFRESH_INTERVAL" to JSONObject.NULL,
                "DEBUG" to JSONObject.NULL,
                "COLORS" to JSONObject.NULL,
                "IAB_CATS" to "IAB15",
            ),
        )

        val config = SellwildSDK.apply(raw, base.copy(title = "Deals", gamTag = "/9/base"))

        assertEquals("Deals", config.title)
        assertNull(config.mobileBannerZid)
        assertEquals("/9/base", config.gamTag)
        assertEquals(10, config.marginBottom)
        assertEquals(30_000L, config.adRefreshIntervalMs)
        assertFalse(config.debug)
        assertEquals(listOf("#333333"), config.colors)
        assertEquals("text IAB_CATS is read too (origin fd19058)", listOf("IAB15"), config.iabCats)
    }

    @Test
    fun `a config without CODE, SLUG or NAME keeps the base identity`() {
        val config = SellwildSDK.apply(AppConfigFactory.offSchema(mapOf("CODE" to null, "SLUG" to null, "NAME" to null)), base.copy(slug = "s", name = "n"))

        assertEquals("weatherbug", config.partnerCode)
        assertEquals("s", config.slug)
        assertEquals("n", config.name)
    }

    @Test
    fun `unknown keys are ignored`() {
        val config = SellwildSDK.apply(AppConfigFactory.checked(mapOf("VIDEO_ENABLED" to true)), base)

        assertEquals("minimal", config.partnerCode)
        assertTrue(config.remoteJson == null)
    }

    @Test
    fun `a static config without remote config uses the general listings cache`() {
        val config = SellwildConfig(partnerCode = "weatherbug", slug = "weatherbug-weatherbug")

        assertNull(config.listingsUrl)
        assertEquals("https://cache.sellwild.com/listings-img-data-sm", config.effectiveListingsUrl)
        assertEquals("https://custom.example.com/listings", config.copy(listingsUrl = "https://custom.example.com/listings").effectiveListingsUrl)
    }
}
