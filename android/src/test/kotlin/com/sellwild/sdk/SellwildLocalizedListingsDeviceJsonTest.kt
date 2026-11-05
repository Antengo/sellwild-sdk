package com.sellwild.sdk

import com.sellwild.sdk.SellwildLocalizedListings.Integration
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.LocalizedListingsConfigFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * A9: LOCALIZED_LISTINGS text fields on a device. The device org.json reads JSON null as the
 * text "null" (the JVM org.json of the plain unit tests reads ""), so a null baseUrl became
 * the cache base "null", a null forceState normalized to the state "LL", and a null source
 * became the label "null". Robolectric runs the device org.json.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildLocalizedListingsDeviceJsonTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()
    private val base = "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/"
    private val template = "sports-img-data-sm-webp-{state}.json"

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun resolve(overrides: Map<String, Any?>): Integration? {
        val localized = LocalizedListingsConfigFactory.offSchema(overrides)
        val remote = AppConfigFactory.offSchema(mapOf("LOCALIZED_LISTINGS" to localized)).toString()
        return SellwildLocalizedListings.resolve(SellwildConfig(partnerCode = "fixture", remoteJson = remote))
    }

    @Test
    fun `this runtime has the device org json`() {
        assertEquals("null", JSONObject("""{"a":null}""").optString("a"))
    }

    @Test
    fun `a JSON null source or forceState is unset, not the label null or the state LL`() {
        assertEquals(
            Integration(null, base, template, 25, null),
            resolve(mapOf("source" to JSONObject.NULL, "forceState" to JSONObject.NULL)),
        )
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `a JSON null baseUrl is a missing URL part, off and reported, not the base null`() {
        assertNull(resolve(mapOf("baseUrl" to JSONObject.NULL)))

        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.LOCALIZED_CONFIG_INVALID, event.action)
        assertEquals("LOCALIZED_LISTINGS lacks baseUrl or urlTemplate", event.attributes["msg"])
    }

    @Test
    fun `a JSON null urlTemplate is a missing URL part too`() {
        assertNull(resolve(mapOf("urlTemplate" to JSONObject.NULL)))

        assertEquals(listOf(SellwildFailureCode.LOCALIZED_CONFIG_INVALID), sink.pushed.map { it.action })
    }
}
