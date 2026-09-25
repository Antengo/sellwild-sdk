package com.sellwild.sdk

import com.sellwild.sdk.core.RemoteValues
import com.sellwild.sdk.failures.FailuresCore
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.FixtureLoader
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Every app-config sample and valid fixture through the real configure() (the CDN answered
 * in-process) and the resolvers that read the result, on the device's org.json
 * (Robolectric), against expectations/app-config.expected.json with drift/android.json
 * honored ([Conformance]).
 */
@RunWith(RobolectricTestRunner::class)
class AppConfigConformanceTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val conformance = Conformance("app-config")

    private val stackNames = mapOf(
        SellwildAdStack.BOTH to "both",
        SellwildAdStack.GAM_ONLY to "gamOnly",
        SellwildAdStack.PREBID_ONLY to "prebidOnly",
    )

    private fun configure(raw: JSONObject): SellwildConfig = HttpStub.install { StubResponse(200, raw.toString()) }.use {
        runBlocking { SellwildSDK.configure(raw.getString("CODE"), raw.getString("SLUG")) }
    }

    /** The expectation fields from Android's typed config and the resolvers that read it. */
    private fun result(raw: JSONObject, config: SellwildConfig, expected: JSONObject): Map<String, Any?> {
        val obj = JSONObject(config.remoteJson!!)
        val house = expected.getJSONObject("houseAd")
        val (width, height) = house.getString("size").split("x").map { it.toInt() }
        val localized = SellwildLocalizedListings.resolve(config)
        return mapOf(
            "partnerCode" to config.partnerCode,
            "slug" to config.slug,
            "mobileZids" to config.mobileZids,
            "mobileBannerZid" to config.mobileBannerZid,
            // Android always holds a value (default 30000): unset is when the key was not mapped.
            "adRefreshIntervalMs" to RemoteValues.optAny(raw, "AD_REFRESH_INTERVAL")?.let { config.adRefreshIntervalMs },
            "iabCats" to config.iabCats,
            "adStack" to mapOf(
                "global" to SellwildAdStack.global(obj).value?.let(stackNames::getValue),
                "byZone" to SellwildAdStack.byZone(obj).value.mapValues { stackNames.getValue(it.value) },
                "resolved" to conformance.zones.associateWith { stackNames.getValue(SellwildAdStack.resolve(config.remoteJson, it)) },
            ),
            "eventsEnabled" to SellwildEvents.isEnabled(config.remoteJson),
            "failuresEnabled" to FailuresCore.coerceFlag(SellwildFailures.context.failuresEnabled),
            "failuresSampleRate" to FailuresCore.coerceRate(SellwildFailures.context.failuresSampleRate),
            "appBundleId" to config.appBundleId,
            "appStoreUrl" to config.appStoreUrl,
            "publisherId" to SellwildPrebidMobile.resolvePublisherId(obj),
            "bannerSizesByZone" to conformance.zones.associateWith { zone ->
                SellwildAdSizes.remoteSizes(obj, zone).value.map { listOf(it.width, it.height) }
            },
            "houseAd" to mapOf(
                "enabled" to SellwildHouseAd.isEnabled(config.remoteJson),
                "zone" to house.getString("zone"),
                "size" to house.getString("size"),
                "candidates" to SellwildHouseAd.candidates(obj, house.getString("zone"), width, height)
                    .map { mapOf("image" to it.imageUrl, "click" to it.clickUrl) },
            ),
            "localizedListings" to localized?.let {
                val state = it.forceState ?: "AL"
                mapOf(
                    "source" to it.source,
                    "baseUrl" to it.baseUrl,
                    "urlTemplate" to it.urlTemplate,
                    "frequency" to it.frequency,
                    "forceState" to it.forceState,
                    "cacheUrlForState" to mapOf("state" to state, "url" to SellwildLocalizedListings.buildCacheUrl(it, state)),
                    "everyNth" to SellwildLocalizedListings.everyN(it.frequency),
                )
            },
            // The .both auction sends no bidder params: SellwildAdView.loadGam passes none to
            // runBannerAuction (bidder params live server-side in the stored imp; iOS parity).
            // SellwildAdViewTest checks the imp ext of a real auction.
            "auctionBidderParams" to emptyMap<String, Any?>(),
        )
    }

    @Test
    fun `android is held to every field it resolves`() {
        assertEquals(
            listOf(
                "partnerCode", "slug", "mobileZids", "mobileBannerZid", "adRefreshIntervalMs", "iabCats", "adStack",
                "eventsEnabled", "failuresEnabled", "failuresSampleRate", "appBundleId", "appStoreUrl", "publisherId",
                "bannerSizesByZone", "houseAd", "localizedListings", "auctionBidderParams",
            ),
            conformance.fields,
        )
        assertTrue(conformance.cases.size >= 37)
        val files = FixtureLoader.list("fixtures/app-config/valid")
        assertEquals("every valid fixture has a case", emptyList<String>(), files.filterNot { f -> conformance.cases.any { it.first == f } })
    }

    @Test
    fun `every case resolves to its expected result`() {
        for ((file, expected) in conformance.cases) {
            val raw = FixtureLoader.jsonObject(file)

            val config = configure(raw)

            val android: (Any?) -> Any? = { (it as Map<*, *>)["android"] }
            conformance.check(
                file,
                expected,
                result(raw, config, expected),
                views = mapOf(
                    "mobileZids" to android,
                    "mobileBannerZid" to android,
                    "appBundleId" to android,
                    "appStoreUrl" to android,
                ),
            )
        }
    }
}
