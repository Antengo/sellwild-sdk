package com.sellwild.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.factories.ListingsResponseFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.support.FixtureLoader
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * The listings parser in SellwildAPI.kt under Robolectric, which loads the device's org.json
 * (plain JVM tests get org.json:json, where optString of JSON null is ""). On a device
 * optString returns the text "null", so a JSON-null remote_url used to become the URL "null"
 * and tapUrl opened it for a dataSourceId 31 listing.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildListingsParserDeviceJsonTest {

    @get:Rule
    val network = NetworkBlockRule()

    // A fetch attaches logFailure, which creates the process-wide queue: reset it after.
    @get:Rule
    val failures = FailuresRule()

    private val listingsUrl = "https://cache.sellwild.com/listings-img-data-sm"

    private fun fetch(body: String): SellwildListingsResponse {
        val client = SellwildAPIClient(ApplicationProvider.getApplicationContext<Context>())
        val config = SellwildConfig(partnerCode = "weatherbug", listingsUrl = listingsUrl)
        return HttpStub.install { url -> StubResponse(200, body).takeIf { url.toString() == listingsUrl } }.use {
            runBlocking { client.fetchListings(config) }.getOrThrow()
        }
    }

    @Test
    fun `this runtime has the device org json`() {
        // The premise of the tests below: without it they would pass for the wrong reason.
        assertEquals("null", JSONObject("""{"a":null}""").optString("a"))
    }

    @Test
    fun `a JSON null remote_url parses as absent, and tapUrl falls back to the product page`() {
        val body = ListingsResponseFactory.withItems(ListingFactory.remoteUrlNull()).toString()

        val listing = fetch(body).listings.single()

        assertEquals("31", listing.dataSourceId)
        assertNull(listing.remoteUrl)
        assertEquals(
            "https://sellwild.com/product/105140231?p=weatherbug&utm_source=weatherbug",
            listing.tapUrl("weatherbug"),
        )
    }

    @Test
    fun `a text remote_url is kept`() {
        val body = ListingsResponseFactory.withItems(ListingFactory.build()).toString()

        val listing = fetch(body).listings.single()

        assertEquals("https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1", listing.remoteUrl)
        assertEquals(listing.remoteUrl, listing.tapUrl("weatherbug"))
    }

    @Test
    fun `the real weatherbug cache has no listing with the text null as remote_url`() {
        val expectations = FixtureLoader.jsonObject("expectations/listings-response.expected.json").getJSONArray("cases")
        val case = (0 until expectations.length()).map { expectations.getJSONObject(it) }
            .single { it.getString("file") == "samples/listings-response/listings-img-data-sm-avif-weatherbug.json" }
        val nullIds = case.getJSONObject("expected").getJSONArray("nullRemoteUrlIds").let { ids ->
            (0 until ids.length()).map { ids.getString(it) }
        }

        val listings = fetch(FixtureLoader.text(case.getString("file"))).listings

        assertEquals(case.getJSONObject("expected").getInt("items"), listings.size)
        val byId = listings.associateBy { it.id }
        assertEquals(7, nullIds.size)
        nullIds.forEach { id -> assertNull(id, byId.getValue(id).remoteUrl) }
        assertEquals(emptyList<String>(), listings.filter { it.remoteUrl == "null" }.map { it.id })
    }
}
