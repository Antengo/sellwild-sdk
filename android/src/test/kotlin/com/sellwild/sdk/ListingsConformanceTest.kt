package com.sellwild.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.failures.FailuresRule
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
 * Every listings sample and valid fixture through the real fetch and parser, on the device's
 * org.json (Robolectric), against expectations/listings-response.expected.json with
 * drift/android.json honored ([Conformance]). The per-state localized samples run through
 * the localized fetch, which shares the parser.
 */
@RunWith(RobolectricTestRunner::class)
class ListingsConformanceTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val conformance = Conformance("listings-response")
    private val url = "https://cache.sellwild.com/conformance"

    @Test
    fun `this runtime has the device org json`() {
        assertEquals("null", JSONObject("""{"a":null}""").optString("a"))
    }

    @Test
    fun `android is held to items, ids, null remote_url ids and the cache version`() {
        assertEquals(listOf("items", "ids", "nullRemoteUrlIds", "widgetCacheVersionId"), conformance.fields)
        assertTrue(conformance.cases.size >= 9)
    }

    @Test
    fun `every case parses to its expected result`() {
        val events = CapturedEvents().install()
        for ((file, expected) in conformance.cases) {
            val body = FixtureLoader.text(file)
            val response = HttpStub.install { StubResponse(200, body) }.use {
                runBlocking { SellwildAPIClient(ApplicationProvider.getApplicationContext<Context>()).fetchListings(SellwildConfig("conformance", listingsUrl = url)) }
                    .getOrThrow()
            }
            val raw = JSONObject(body).let { it.optJSONObject("result") ?: it }.getJSONArray("rs")
            val nullIds = (0 until raw.length()).map { raw.getJSONObject(it) }
                .filter { it.has("remote_url") && it.isNull("remote_url") }
                .map { it.getString("id") }

            conformance.check(
                file,
                expected,
                mapOf(
                    "items" to response.listings.size,
                    "ids" to response.listings.map { it.id },
                    "nullRemoteUrlIds" to response.listings.filter { it.id in nullIds && it.remoteUrl == null }.map { it.id },
                    "widgetCacheVersionId" to response.widgetCacheVersionId,
                ),
            )
        }
        assertEquals("a good body reports nothing", emptyList<String>(), events.codes)
    }

    /** One localized fetch of [file]'s body, answered with [status]. */
    private fun fetchLocalized(file: String, status: Int): Result<List<SellwildListing>> {
        val body = FixtureLoader.text(file)
        return HttpStub.install { StubResponse(status, body) }.use {
            runBlocking {
                SellwildAPIClient(ApplicationProvider.getApplicationContext<Context>())
                    .fetchCacheListings("https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/${file.substringAfterLast('/')}")
            }
        }
    }

    @Test
    fun `every localized listings sample parses through the localized fetch, and a missing state is a quiet skip`() {
        val events = CapturedEvents().install()
        val samples = FixtureLoader.list("samples/localized-listings-response")
        val json = samples.filter { it.endsWith(".json") }
        assertEquals("the AL and GA per-state caches", 2, json.size)

        for (file in json) {
            val listings = fetchLocalized(file, 200).getOrThrow()

            val raw = JSONObject(FixtureLoader.text(file)).getJSONObject("result").getJSONArray("rs")
            val items = (0 until raw.length()).map { raw.getJSONObject(it) }
            assertEquals(file, 10, listings.size)
            assertEquals(file, items.map { it.getString("id") }, listings.map { it.id })
            assertEquals(file, items.map { it.getString("title") }, listings.map { it.title })
            assertEquals(file, items.map { it.getJSONArray("photos").length() }, listings.map { it.photos.size })
            assertEquals(file, items.map { it.getString("remote_url") }, listings.map { it.remoteUrl })
        }

        // S3 answers a state without a cache with its 403 AccessDenied XML.
        val missing = samples.single { it.endsWith(".403.xml") }
        assertTrue(fetchLocalized(missing, 403).isFailure)
        assertEquals("good bodies and a missing state report nothing", emptyList<String>(), events.codes)
    }
}
