package com.sellwild.sdk

import com.sellwild.sdk.SellwildLocalizedListings.Integration
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.LocalizedListingsConfigFactory
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.failures.gateCalls
import com.sellwild.sdk.support.FixtureLoader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import kotlin.random.Random

/**
 * Localized (per-state) listings: resolving the integration (local wins, else the remote
 * object or JSON text), state and URL building, dispersion, and localized.config.invalid for
 * a value the SDK cannot use.
 */
class SellwildLocalizedListingsTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()
    private val base = "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/"
    private val template = "sports-img-data-sm-webp-{state}.json"

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun remote(value: Any?) =
        SellwildConfig(partnerCode = "fixture", remoteJson = AppConfigFactory.checked(mapOf("LOCALIZED_LISTINGS" to value)).toString())

    @Test
    fun `the remote object resolves, with the frequency as a number or text`() {
        val full = SellwildLocalizedListings.resolve(remote(LocalizedListingsConfigFactory.checked()))
        val text = SellwildLocalizedListings.resolve(remote(LocalizedListingsConfigFactory.variant("no-force-state")))

        assertEquals(Integration("sportserver", base, template, 25, "AL"), full)
        assertEquals(Integration("sportserver", base, template, 10, null), text)
        assertEquals(
            "no frequency is 0 (off)",
            Integration(null, base, template, 0, null),
            SellwildLocalizedListings.resolve(remote(LocalizedListingsConfigFactory.variant("minimal"))),
        )
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `JSON text of the object resolves too`() {
        val config = SellwildConfig(partnerCode = "fixture", remoteJson = FixtureLoader.text("fixtures/app-config/valid/localized-json-text.json"))

        assertEquals(
            Integration(null, "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com", template, 20, "AL"),
            SellwildLocalizedListings.resolve(config),
        )
    }

    @Test
    fun `unset, disabled or no remote config is off and not reported`() {
        assertNull(SellwildLocalizedListings.resolve(SellwildConfig(partnerCode = "fixture")))
        assertNull(SellwildLocalizedListings.resolve(remote(null)))
        assertNull(SellwildLocalizedListings.resolve(remote("")))
        assertNull(SellwildLocalizedListings.resolve(remote(LocalizedListingsConfigFactory.variant("disabled"))))
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `an object without its URL parts is off and reported`() {
        failures.expectRepeats()
        assertNull(SellwildLocalizedListings.resolve(remote(LocalizedListingsConfigFactory.checked(mapOf("baseUrl" to null)))))
        assertNull(SellwildLocalizedListings.resolve(remote(LocalizedListingsConfigFactory.checked(mapOf("urlTemplate" to null)))))

        // The same issue twice: the gate sends it once and folds the repeat.
        assertEquals(listOf(SellwildFailureCode.LOCALIZED_CONFIG_INVALID), sink.pushed.map { it.action })
        assertEquals(1, SellwildFailures.gateState.keys.single().suppressed)
        assertEquals("LOCALIZED_LISTINGS lacks baseUrl or urlTemplate", sink.pushed.first().attributes["msg"])
        assertEquals("localized", sink.pushed.first().label)
        assertEquals("warn", sink.pushed.first().attributes["severity"])
    }

    @Test
    fun `the same unusable config is reported once, however often feeds resolve it`() {
        val remote = remote(LocalizedListingsConfigFactory.checked(mapOf("baseUrl" to null)))
        val local = SellwildConfig(partnerCode = "fixture", localizedListings = SellwildLocalizedListingsConfig(baseUrl = base))

        repeat(3) {
            assertNull(SellwildLocalizedListings.resolve(remote))
            assertNull(SellwildLocalizedListings.resolve(local))
            assertNull(SellwildLocalizedListings.resolve(local.copy()))
        }

        assertEquals(2, gateCalls(SellwildFailureCode.LOCALIZED_CONFIG_INVALID))
        assertEquals(
            listOf("LOCALIZED_LISTINGS lacks baseUrl or urlTemplate", "config.localizedListings lacks baseUrl or urlTemplate"),
            sink.pushed.map { it.attributes["msg"] },
        )
    }

    @Test
    fun `a different local override is a new config, so its issue is reported again, once`() {
        failures.expectRepeats()
        val remote = remote(LocalizedListingsConfigFactory.checked())
        val first = remote.copy(localizedListings = SellwildLocalizedListingsConfig(baseUrl = base))
        val second = remote.copy(localizedListings = SellwildLocalizedListingsConfig(urlTemplate = template))

        repeat(2) {
            assertNull(SellwildLocalizedListings.resolve(first))
            assertNull(SellwildLocalizedListings.resolve(second))
        }

        // Same remote text both times: the override, not the remote text, keys the memory.
        assertEquals(2, gateCalls(SellwildFailureCode.LOCALIZED_CONFIG_INVALID))
    }

    @Test
    fun `text that is not a JSON object, or a value of another type, is off and reported`() {
        val notJson = remote("{\"baseUrl\"")
        val list = SellwildConfig(
            partnerCode = "fixture",
            remoteJson = AppConfigFactory.offSchema(mapOf("LOCALIZED_LISTINGS" to jsonArrayOf("x"))).toString(),
        )

        assertNull(SellwildLocalizedListings.resolve(notJson))
        assertNull(SellwildLocalizedListings.resolve(list))

        val messages = sink.pushed.map { it.attributes["msg"].orEmpty() }
        assertEquals(2, messages.size)
        assertEquals(true, messages[0].startsWith("LOCALIZED_LISTINGS text is not a JSON object: "))
        assertEquals("LOCALIZED_LISTINGS is not an object", messages[1])
        assertEquals("JSONException", sink.pushed.first().attributes["errName"])
    }

    @Test
    fun `the local override wins whole, and reports when it lacks its URL parts`() {
        val local = SellwildLocalizedListingsConfig(baseUrl = " $base ", urlTemplate = template, frequency = 50, forceState = "ga", source = " ")
        val config = remote(LocalizedListingsConfigFactory.checked()).copy(localizedListings = local)

        assertEquals(Integration(null, base, template, 50, "GA"), SellwildLocalizedListings.resolve(config))
        assertNull(SellwildLocalizedListings.resolve(config.copy(localizedListings = local.copy(enabled = false))))
        assertNull(SellwildLocalizedListings.resolve(config.copy(localizedListings = SellwildLocalizedListingsConfig(baseUrl = base))))

        assertEquals("config.localizedListings lacks baseUrl or urlTemplate", sink.pushed.single().attributes["msg"])
    }

    @Test
    fun `config that does not parse is off and reported`() {
        val bad = SellwildConfig(partnerCode = "fixture", remoteJson = FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml"))

        assertNull(SellwildLocalizedListings.resolve(bad))

        assertEquals(listOf(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE), sink.pushed.map { it.action })
    }

    @Test
    fun `the forced state wins, then the geo state, normalized to two upper-case letters`() {
        val forced = Integration(null, base, template, 25, "AL")
        val free = forced.copy(forceState = null)

        assertEquals("AL", SellwildLocalizedListings.resolveState(forced, "GA"))
        assertEquals("GA", SellwildLocalizedListings.resolveState(free, " ga "))
        assertEquals("CA", SellwildLocalizedListings.resolveState(free, "US-CA"))
        assertEquals("1", SellwildLocalizedListings.normState("1"))
        assertNull(SellwildLocalizedListings.resolveState(free, "  "))
        assertNull(SellwildLocalizedListings.normState(null))
    }

    @Test
    fun `the cache URL joins base and template with one slash and a lower-case state`() {
        fun url(base: String, template: String) = SellwildLocalizedListings.buildCacheUrl(Integration(null, base, template, 25, null), "AL")

        assertEquals("https://c.invalid/x-al.json", url("https://c.invalid/", "/x-{STATE}.json"))
        assertEquals("https://c.invalid/x-al.json", url("https://c.invalid", "x-{state}.json"))
        assertEquals("https://c.invalid/x-al.json", url("https://c.invalid/", "x-{state}.json"))
        assertEquals("https://c.invalid/x-al.json", url("https://c.invalid", "/x-{state}.json"))
    }

    @Test
    fun `everyN turns a percent into a slot interval`() {
        assertEquals(0, SellwildLocalizedListings.everyN(0))
        assertEquals(0, SellwildLocalizedListings.everyN(-5))
        assertEquals(4, SellwildLocalizedListings.everyN(25))
        assertEquals(5, SellwildLocalizedListings.everyN(20))
        assertEquals(1, SellwildLocalizedListings.everyN(100))
        assertEquals(1, SellwildLocalizedListings.everyN(150))
        assertEquals(1, SellwildLocalizedListings.everyN(99))
    }

    private fun listing(id: String) = SellwildListing(id = id, status = "1", title = "listing $id")

    @Test
    fun `merge puts a de-duped localized listing in every Nth slot, in the injected random order`() {
        val primary = (1..6).map { listing("p$it") }
        val secondary = listOf(listing("s1"), listing("p2"), listing("s2"))
        val order = listOf(listing("s1"), listing("s2")).shuffled(Random(3))

        val merged = SellwildLocalizedListings.merge(primary, secondary, everyN = 2, random = Random(3))

        assertEquals(listOf("p1", order[0].id, "p3", order[1].id, "p5", order[0].id), merged.map { it.id })
        assertEquals(6, SellwildLocalizedListings.merge(primary, secondary, 3).size)
    }

    @Test
    fun `merge leaves the primary list alone when there is nothing to disperse`() {
        val primary = listOf(listing("p1"), listing("p2"))

        assertSame(primary, SellwildLocalizedListings.merge(primary, listOf(listing("s1")), everyN = 0))
        assertSame(primary, SellwildLocalizedListings.merge(primary, emptyList(), everyN = 2))
        assertEquals(emptyList<SellwildListing>(), SellwildLocalizedListings.merge(emptyList(), listOf(listing("s1")), everyN = 2))
        assertSame(primary, SellwildLocalizedListings.merge(primary, listOf(listing("p1")), everyN = 2))
    }
}
