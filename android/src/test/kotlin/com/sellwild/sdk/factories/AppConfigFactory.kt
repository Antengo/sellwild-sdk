package com.sellwild.sdk.factories

import org.json.JSONObject

/**
 * The CDN app config (`GET widget.sellwild.com/app/{partner}/{slug}.json`), the payload
 * SellwildSDK.configure parses. Base: `fixtures/app-config/valid/minimal.json`.
 */
object AppConfigFactory : JsonObjectFactory("app-config", "fixtures/app-config/valid/minimal.json") {

    /** The remote kill switches and sample rate, as raw values (Boolean, Number or String). */
    fun withFailureFlags(failuresEnabled: Any?, sampleRate: Any?, eventsEnabled: Any? = null): JSONObject =
        build(
            mapOf(
                "EVENTS_ENABLED" to eventsEnabled,
                "FAILURES_ENABLED" to failuresEnabled,
                "FAILURES_SAMPLE_RATE" to sampleRate,
            ),
        )

    /**
     * Every key SellwildSDK.apply maps, each set to a value that differs from the
     * SellwildConfig default, so a test sees every mapping take effect.
     */
    fun everyMappedKey(): JSONObject = build(
        mapOf(
            "CODE" to "fixture",
            "SLUG" to "fixture-app",
            "NAME" to "Fixture App",
            "LISTINGS" to "https://cache.sellwild.com/listings-img-data-sm-fixture",
            "TITLE" to "Marketplace",
            "PARTNER_URL" to "https://sellwild.com/?p=fixture",
            "COL1" to "LLGB",
            "BH_TAG" to "bh-fixture",
            "LINK_TEXT" to "More",
            "BUY_NOW_TEXT" to "Get it",
            "TITLE_COLOR" to "#111111",
            "LINK_COLOR" to "#222222",
            "FONT_COLOR" to "#333333",
            "PRICE_COLOR" to "#444444",
            "PRICE_FONT_COLOR" to "#555555",
            "MARGIN_BOTTOM" to 14,
            "COLORS" to jsonArrayOf("#295baa", "#000000"),
            "OVERLAY_TITLE" to true,
            "WATERMARK" to true,
            "WATERMARK_TITLE" to "By Sellwild",
            "BANNER_ZID" to "43",
            "BOTTOM_BANNER_ZID" to 44,
            "MOBILE_BANNER_ZID_ANDROID" to "android-banner",
            "MOBILE_ZID_ALL_ANDROID" to "android-all",
            "MOBILE_BANNER_ZID" to "shared-banner",
            "MOBILE_ZID_ANDROID" to jsonArrayOf("android-feed"),
            "MOBILE_ZID" to jsonArrayOf("shared-feed"),
            "HIDE_BANNER_TOP" to true,
            "HIDE_BANNER_BOTTOM" to true,
            "GAM" to "/1234/fixture",
            "DISABLE_GPT" to true,
            "AD_DISABLE_DISPLAY" to true,
            "AD_REFRESH_MAX" to 5,
            "AD_REFRESH_MAX_MOBILE" to 6,
            "AD_REFRESH_INTERVAL" to 45000,
            "MAX_FAILED_AUCTIONS" to 7,
            "GPP_ENABLED" to true,
            "TCF_VERSION" to 2,
            "IAB_CATS" to jsonArrayOf("IAB2", "IAB2-15"),
            "ENABLE_INTERSTITIAL" to true,
            "ENABLE_FULLSCREEN_VIDEO" to true,
            "INTERSTITIALS_PER_SESSION" to 2,
            "VIDEO_TAKEOVERS_PER_SESSION" to 1,
            "APP_BUNDLE_ID_ANDROID" to "com.fixture.android",
            "APP_BUNDLE_ID" to "com.fixture",
            "APP_STORE_URL_ANDROID" to "https://play.google.com/store/apps/details?id=com.fixture.android",
            "APP_STORE_URL" to "https://sellwild.com/app",
            "BOLTIVE" to true,
            "BOLTIVE_CLIENT_ID" to "boltive-fixture",
            "LOTAME" to true,
            "DEBUG" to true,
            "PBS_DEBUG" to true,
        ),
    )

    override val variants = listOf(
        Variant("default") { build() },
        Variant("every-mapped-key") { everyMappedKey() },
        Variant("sample-weatherbug") { contractObject("samples/app-config/weatherbug_weatherbug-weatherbug.json") },
        Variant("failures-off") { withFailureFlags(false, 0.25, eventsEnabled = true) },
        Variant("failures-text") { withFailureFlags("off", "0.5", eventsEnabled = "yes") },
        Variant("per-os-zids") {
            build(mapOf("MOBILE_ZID" to jsonArrayOf("shared-1"), "MOBILE_ZID_ANDROID" to jsonArrayOf("android-1")))
        },
    )

    override val invalid = listOf(
        Variant("missing-code") { build(mapOf("CODE" to null)) },
        Variant("banner-zid-empty-array") { build(mapOf("MOBILE_BANNER_ZID" to jsonArrayOf())) },
        Variant("sample-rate-object") { build(mapOf("FAILURES_SAMPLE_RATE" to JSONObject().put("rate", 0.5))) },
    )
}
