package com.sellwild.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.factories.ListingsResponseFactory
import com.sellwild.sdk.factories.LocalizedListingsResponseFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.FixtureLoader
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.net.MalformedURLException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * SellwildAPIClient's listings and localized fetches: each failure is reported once, here,
 * with its registry code, and returned to the caller. [HttpStub] answers the caches
 * in-process; [CapturedEvents] receives what logFailure sends.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildAPIClientTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val listingsUrl = "https://cache.sellwild.com/listings-img-data-sm"
    private val stateUrl = "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/sports-img-data-sm-webp-al.json"
    private lateinit var events: CapturedEvents

    @Before
    fun capture() {
        events = CapturedEvents().install()
        SellwildGeoStore.current = null
    }

    @After
    fun forgetGeo() {
        SellwildGeoStore.current = null
    }

    private fun fetch(response: StubResponse?, url: String = listingsUrl, client: SellwildAPIClient = SellwildAPIClient(context)) =
        HttpStub.install { response }.use { stub ->
            runBlocking { client.fetchListings(SellwildConfig(partnerCode = "weatherbug", listingsUrl = url)) } to stub.requests.size
        }

    private fun fetchState(response: StubResponse?, url: String = stateUrl) =
        HttpStub.install { response }.use { runBlocking { SellwildAPIClient(context).fetchCacheListings(url) } }

    private val goodBody = ListingsResponseFactory.withItems(ListingFactory.build()).toString()

    @Test
    fun `a good listings body parses, is cached per URL, and reports nothing`() {
        val client = SellwildAPIClient(context)

        val (first, requests) = fetch(StubResponse(200, goodBody), client = client)
        val (second, again) = fetch(StubResponse(500), client = client)

        assertEquals(listOf("105140231"), first.getOrThrow().listings.map { it.id })
        assertEquals(1, requests)
        assertEquals(0, again)
        assertTrue(second.getOrThrow() === first.getOrThrow())
        client.clearCache()
        assertEquals(1, fetch(StubResponse(200, goodBody), client = client).second)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a non-200 listings status is listings fetch http, once, with the status and host`() {
        val (result, _) = fetch(StubResponse(503, "Service Unavailable"))

        assertEquals("HTTP 503 from $listingsUrl", result.exceptionOrNull()?.message)
        assertTrue(result.exceptionOrNull() is SellwildException)
        val event = events.single(SellwildFailureCode.LISTINGS_FETCH_HTTP)
        assertEquals("listings", event.getString("label"))
        val attributes = event.getJSONObject("attributes")
        assertEquals("503", attributes.getString("httpStatus"))
        assertEquals("HTTP 503", attributes.getString("msg"))
        assertEquals("cache.sellwild.com", attributes.getString("host"))
        assertEquals("error", attributes.getString("severity"))
        assertEquals("weatherbug", attributes.getString("code"))
    }

    @Test
    fun `both fetches run on the injected dispatcher`() {
        val executor = Executors.newSingleThreadExecutor { Thread(it, "sellwild-test-io") }
        val threads = CopyOnWriteArrayList<String>()
        val client = SellwildAPIClient(context, executor.asCoroutineDispatcher(), SellwildPrebidMobile::setGeo)
        val stateBody = LocalizedListingsResponseFactory.checked().toString()

        try {
            HttpStub.install { url ->
                // Coroutine debug mode appends " @coroutine#N" to the thread name.
                threads += Thread.currentThread().name.substringBefore(" @")
                StubResponse(200, if (url.toString() == stateUrl) stateBody else goodBody)
            }.use {
                runBlocking {
                    assertTrue(client.fetchListings(SellwildConfig(partnerCode = "weatherbug", listingsUrl = listingsUrl)).isSuccess)
                    assertTrue(client.fetchCacheListings(stateUrl).isSuccess)
                }
            }
        } finally {
            executor.shutdown()
        }

        assertEquals(listOf("sellwild-test-io", "sellwild-test-io"), threads)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a fetch attaches logFailure to the process-wide queue, not a queue of its own`() {
        val shared = CapturedEvents()
        SellwildEventQueue.setSharedForTests(shared.queue)
        SellwildFailures.bind(null)

        fetch(StubResponse(503))

        // Bound to anything but SellwildEventQueue.shared, the failure would have gone to a
        // queue that POSTs for real (and hit the network block) instead of this one.
        assertEquals(listOf(SellwildFailureCode.LISTINGS_FETCH_HTTP), shared.codes)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a hand-built config names the partner on failures, unless configure set one`() {
        fetch(StubResponse(500))
        SellwildFailures.setContext { it.copy(partnerCode = "configured") }
        HttpStub.install { StubResponse(502) }.use {
            runBlocking { SellwildAPIClient(context).fetchListings(SellwildConfig(partnerCode = "other", listingsUrl = listingsUrl)) }
        }
        HttpStub.install { StubResponse(504) }.use {
            runBlocking { SellwildAPIClient(context).fetchListings(SellwildConfig(partnerCode = "", listingsUrl = listingsUrl)) }
        }

        assertEquals(listOf("weatherbug", "configured", "configured"), events.failures.map { it.getJSONObject("attributes").getString("code") })
    }

    @Test
    fun `a listings network failure is listings fetch network`() {
        network.expectAttempts()

        val (result, _) = fetch(null)

        assertEquals(listOf(listingsUrl), network.attempts)
        assertTrue(result.isFailure)
        val attributes = events.attributes(SellwildFailureCode.LISTINGS_FETCH_NETWORK)
        assertEquals("NetworkBlockedException", attributes.getString("errName"))
        assertEquals("cache.sellwild.com", attributes.getString("host"))
    }

    @Test
    fun `a listings body that is not JSON is listings fetch parse`() {
        val (result, _) = fetch(StubResponse(200, FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml")))

        assertTrue(result.isFailure)
        val attributes = events.attributes(SellwildFailureCode.LISTINGS_FETCH_PARSE)
        assertEquals("JSONException", attributes.getString("errName"))
        assertEquals("cache.sellwild.com", attributes.getString("host"))
        assertEquals("error", attributes.getString("severity"))
    }

    @Test
    fun `a listings URL that is not http(s) is listings url invalid, with no request`() {
        val (noScheme, requests) = fetch(StubResponse(200, goodBody), url = "cache.sellwild.com/listings")

        assertTrue(noScheme.exceptionOrNull() is MalformedURLException)
        assertEquals(0, requests)
        val attributes = events.attributes(SellwildFailureCode.LISTINGS_URL_INVALID)
        assertEquals("MalformedURLException", attributes.getString("errName"))
        assertEquals("error", attributes.getString("severity"))
    }

    @Test
    fun `CloudFront viewer headers seed an empty geo once, and never overwrite it`() {
        val headers = mapOf("CloudFront-Viewer-Country-Region" to "GA", "CloudFront-Viewer-Country" to "US")

        fetch(StubResponse(200, goodBody, headers))
        assertEquals(SellwildGeo(country = "USA", state = "GA"), SellwildGeoStore.current)

        SellwildGeoStore.current = SellwildGeo(state = "NY", country = "CAN")
        fetch(StubResponse(200, goodBody, headers))
        assertEquals(SellwildGeo(state = "NY", country = "CAN"), SellwildGeoStore.current)
    }

    @Test
    fun `a geo seed that throws is geo seed exception, once, and the listings still load`() {
        // setGeo hands the seeded geo to the Prebid fork (setGlobalOrtbConfig), which may throw.
        val seeded = CopyOnWriteArrayList<SellwildGeo>()
        val client = SellwildAPIClient(context, Dispatchers.IO) { geo ->
            seeded += geo
            throw IllegalStateException("ortb config refused")
        }

        val (result, _) = fetch(StubResponse(200, goodBody, mapOf("CloudFront-Viewer-Country-Region" to "GA")), client = client)

        assertEquals(listOf("105140231"), result.getOrThrow().listings.map { it.id })
        assertEquals(listOf(SellwildGeo(state = "GA")), seeded)
        val event = events.single(SellwildFailureCode.GEO_SEED_EXCEPTION)
        assertEquals("geo", event.getString("label"))
        val attributes = event.getJSONObject("attributes")
        assertEquals("warn", attributes.getString("severity"))
        assertEquals("IllegalStateException", attributes.getString("errName"))
    }

    @Test
    fun `a partner geo with a latitude that is not finite still takes the seed, with nothing reported`() {
        // org.json refuses NaN; toOrtbGeo now leaves it out instead of throwing from setGeo.
        SellwildGeoStore.current = SellwildGeo(lat = Double.NaN)

        val (result, _) = fetch(StubResponse(200, goodBody, mapOf("CloudFront-Viewer-Country-Region" to "GA")))

        assertEquals(listOf("105140231"), result.getOrThrow().listings.map { it.id })
        assertEquals("GA", SellwildGeoStore.current?.state)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a state cache parses with the listings parser`() {
        val body = LocalizedListingsResponseFactory.checked().toString()

        val listings = fetchState(StubResponse(200, body)).getOrThrow()

        assertEquals(listOf("104874856"), listings.map { it.id })
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a 403 or 404 state cache is a normal skip, not reported`() {
        val missing = FixtureLoader.text("samples/localized-listings-response/sports-img-data-sm-webp-zz.403.xml")

        val forbidden = fetchState(StubResponse(403, missing))
        val notFound = fetchState(StubResponse(404))

        assertEquals("HTTP 403 from $stateUrl", forbidden.exceptionOrNull()?.message)
        assertEquals("HTTP 404 from $stateUrl", notFound.exceptionOrNull()?.message)
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `any other state cache status is localized fetch http, as a warning`() {
        val result = fetchState(StubResponse(500))

        assertTrue(result.exceptionOrNull() is SellwildException)
        val event = events.single(SellwildFailureCode.LOCALIZED_FETCH_HTTP)
        assertEquals("localized", event.getString("label"))
        val attributes = event.getJSONObject("attributes")
        assertEquals("500", attributes.getString("httpStatus"))
        assertEquals("warn", attributes.getString("severity"))
        assertEquals("sellwild-sports-cache.s3.us-east-1.amazonaws.com", attributes.getString("host"))
    }

    @Test
    fun `a state cache network failure is localized fetch network`() {
        network.expectAttempts()

        assertTrue(fetchState(null).isFailure)

        val attributes = events.attributes(SellwildFailureCode.LOCALIZED_FETCH_NETWORK)
        assertEquals("NetworkBlockedException", attributes.getString("errName"))
        assertEquals("sellwild-sports-cache.s3.us-east-1.amazonaws.com", attributes.getString("host"))
    }

    @Test
    fun `a state cache body that is not JSON is localized fetch parse`() {
        assertTrue(fetchState(StubResponse(200, FixtureLoader.text("samples/localized-listings-response/sports-img-data-sm-webp-zz.403.xml"))).isFailure)

        val attributes = events.attributes(SellwildFailureCode.LOCALIZED_FETCH_PARSE)
        assertEquals("JSONException", attributes.getString("errName"))
        assertEquals("sellwild-sports-cache.s3.us-east-1.amazonaws.com", attributes.getString("host"))
        assertEquals("warn", attributes.getString("severity"))
    }

    @Test
    fun `a state cache URL that is not http(s) is localized url invalid`() {
        assertTrue(fetchState(StubResponse(200), url = "file:///sdcard/al.json").exceptionOrNull() is MalformedURLException)

        val attributes = events.attributes(SellwildFailureCode.LOCALIZED_URL_INVALID)
        assertEquals("not an http(s) URL: file", attributes.getString("msg"))
    }

    @Test
    fun `the listing tap URL adds the Bargain Hunter tag, else uses remote_url or the product page`() {
        val bargain = ListingsParserFor.listing(ListingFactory.variant("bargainhunter"))
        val remote = ListingsParserFor.listing(ListingFactory.build())
        val product = ListingsParserFor.listing(ListingFactory.variant("no-remote-url"))

        val localized = ListingsParserFor.listing(ListingFactory.variant("localized-item"))

        assertEquals("https://o.bttn.io/19BIp9F5cLj?tag=sw-bh", bargain.tapUrl("weatherbug", "sw-bh"))
        assertEquals(
            "other query params are kept, the tag goes last",
            "https://sportserver.com/products/ncaa-tee?utm_source=sellwild&tag=sw-bh",
            localized.tapUrl("weatherbug", "sw-bh"),
        )
        assertEquals("https://o.bttn.io/19BIp9F5cLj?tag=marketplace-usw-20", bargain.tapUrl("weatherbug"))
        assertEquals("https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1", remote.tapUrl("weatherbug", ""))
        assertEquals("https://sellwild.com/product/105140231?p=a%20b&utm_source=a%20b", product.tapUrl("a b"))
        assertEquals("https://sellwild.com/product/105140231?p=sellwild&utm_source=sellwild", product.tapUrl(null))
        assertNull(product.copy(id = "").tapUrl("weatherbug"))
        assertEquals("https://sellwild.com/product/105140231?p=sellwild&utm_source=sellwild", product.copy(url = "").tapUrl(""))
    }

    @Test
    fun `display price and primary photo`() {
        val listing = ListingsParserFor.listing(ListingFactory.build())

        assertEquals("19315", listing.displayPrice)
        assertEquals("https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231.jpg", listing.primaryPhotoUrl)
        assertNull(listing.copy(price = "0").displayPrice)
        assertNull(listing.copy(price = "free").displayPrice)
        assertNull(listing.copy(price = null, photos = emptyList()).displayPrice)
        assertNull(listing.copy(photos = emptyList()).primaryPhotoUrl)
    }

    @Test
    fun `SellwildException keeps its cause`() {
        val cause = IllegalStateException("x")

        assertTrue(SellwildException("wrapped", cause).cause === cause)
        assertNull(SellwildException("plain").cause)
    }
}

/** A listing through the SDK's parser. */
private object ListingsParserFor {
    fun listing(json: org.json.JSONObject): SellwildListing = com.sellwild.sdk.core.ListingsParser.parseListing(json)
}
