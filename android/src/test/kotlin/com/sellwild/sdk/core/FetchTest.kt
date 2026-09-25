package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildGeo
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.support.NetworkBlockedException
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.MalformedURLException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException

/** The pure decisions behind the SDK's HTTP fetches. */
class FetchTest {

    @Test
    fun `a thrown fetch maps to timeout, parse, network or exception`() {
        val cases = mapOf(
            SocketTimeoutException("read timed out") to "timeout",
            JSONException("A JSONObject text must begin with '{'") to "parse",
            UnknownHostException("cache.sellwild.com") to "network",
            IOException("reset") to "network",
            SecurityException("INTERNET permission") to "network",
            ClassCastException("java.lang.Long cannot be cast to java.lang.String") to "exception",
            IllegalStateException("refused") to "exception",
        )
        for ((error, reason) in cases) {
            assertEquals("listings.fetch.$reason", Fetch.codeFor(error, Fetch.LISTINGS))
            assertEquals("localized.fetch.$reason", Fetch.codeFor(error, Fetch.LOCALIZED))
            assertEquals("growthcode.sync.$reason", Fetch.codeFor(error, Fetch.GROWTHCODE))
        }
        assertEquals(SellwildFailureCode.LISTINGS_FETCH_NETWORK, Fetch.codeFor(NetworkBlockedException(URL("https://x.invalid")), Fetch.LISTINGS))
    }

    @Test
    fun `a thrown config fetch maps the same way, and what throws past the network is applying it`() {
        assertEquals(SellwildFailureCode.CONFIG_FETCH_TIMEOUT, Fetch.codeFor(SocketTimeoutException("t"), Fetch.CONFIG))
        assertEquals(SellwildFailureCode.CONFIG_FETCH_PARSE, Fetch.codeFor(JSONException("p"), Fetch.CONFIG))
        assertEquals(SellwildFailureCode.CONFIG_FETCH_NETWORK, Fetch.codeFor(IOException("n"), Fetch.CONFIG))
        assertEquals(SellwildFailureCode.CONFIG_APPLY_EXCEPTION, Fetch.codeFor(IllegalArgumentException("a"), Fetch.CONFIG))
    }

    @Test
    fun `httpUrl takes http and https and says why anything else is refused`() {
        assertEquals("https", Fetch.httpUrl("https://cache.sellwild.com/listings-img-data-sm").getOrThrow().protocol)
        assertEquals("http", Fetch.httpUrl("http://cache.sellwild.com/x").getOrThrow().protocol)

        val file = Fetch.httpUrl("file:///data/data/app/prefs.xml").exceptionOrNull()
        assertTrue(file is MalformedURLException)
        assertEquals("not an http(s) URL: file", file!!.message)
        assertTrue(Fetch.httpUrl("cache.sellwild.com/listings").exceptionOrNull() is MalformedURLException)
        assertTrue(Fetch.httpUrl("").exceptionOrNull() is MalformedURLException)
    }

    @Test
    fun `a 403 or 404 from a state cache is a missing state, not a failure`() {
        assertTrue(Fetch.isMissingStateCache(403))
        assertTrue(Fetch.isMissingStateCache(404))
        listOf(200, 400, 410, 500, 503).forEach { assertFalse("$it", Fetch.isMissingStateCache(it)) }
    }

    @Test
    fun `CloudFront headers fill an empty state and a North America country, never overwrite`() {
        assertEquals(SellwildGeo(state = "GA", country = "USA"), Fetch.seededGeo(null, " GA ", "us"))
        assertEquals(SellwildGeo(state = "GA"), Fetch.seededGeo(SellwildGeo(state = ""), "GA", null))
        assertEquals(SellwildGeo(state = "NY", country = "CAN"), Fetch.seededGeo(SellwildGeo(state = "NY"), "GA", "CA"))

        assertNull("both set already", Fetch.seededGeo(SellwildGeo(state = "NY", country = "USA"), "GA", "US"))
        assertNull("no headers", Fetch.seededGeo(null, null, null))
        assertNull("blank headers", Fetch.seededGeo(null, "  ", " "))
        assertNull("a country outside North America is skipped", Fetch.seededGeo(SellwildGeo(state = "NY"), null, "GB"))
    }
}
