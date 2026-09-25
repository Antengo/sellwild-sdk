package com.sellwild.sdk

import com.sellwild.sdk.SellwildAdSizes.Size
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.FakeFailureSink
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.failures.gateCalls
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Multi-size banners: BANNER_SIZES / BANNER_SIZES_BY_ZONE parsing and config.banner_sizes.invalid. */
class SellwildAdSizesTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()
    private val mrec = Size(300, 250)

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun resolve(zone: String?, vararg entries: Pair<String, Any?>): List<Size> =
        SellwildAdSizes.resolve(AppConfigFactory.checked(mapOf(*entries)).toString(), zone, mrec)

    @Test
    fun `nothing configured is just the primary`() {
        assertEquals(listOf(mrec), SellwildAdSizes.resolve(null, "43", mrec))
        assertEquals(listOf(mrec), resolve("43"))
        assertEquals(listOf(mrec), resolve("43", "BANNER_SIZES" to "", "BANNER_SIZES_BY_ZONE" to ""))
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `every size shape parses, primary first, duplicates removed`() {
        assertEquals(listOf(mrec, Size(320, 50)), resolve("43", "BANNER_SIZES" to jsonArrayOf("320x50", " 300 X 250 ", "320x50")))
        assertEquals(listOf(mrec, Size(728, 90)), resolve("43", "BANNER_SIZES" to jsonArrayOf(jsonArrayOf(728, 90), jsonArrayOf("300", "250.0"))))
        assertEquals(listOf(mrec, Size(320, 50)), resolve("43", "BANNER_SIZES" to "[\"320x50\"]"))
        assertEquals(listOf(mrec, Size(320, 50)), resolve("43", "BANNER_SIZES" to "320x50"))
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `the zone entry wins over the global list`() {
        val byZone = JSONObject().put("43", jsonArrayOf("320x50")).put("280", "")

        assertEquals(listOf(mrec, Size(320, 50)), resolve("43", "BANNER_SIZES" to jsonArrayOf("728x90"), "BANNER_SIZES_BY_ZONE" to byZone))
        assertEquals("'' for a zone is its own (empty) list", listOf(mrec), resolve("280", "BANNER_SIZES" to jsonArrayOf("728x90"), "BANNER_SIZES_BY_ZONE" to byZone))
        assertEquals(listOf(mrec, Size(728, 90)), resolve("999", "BANNER_SIZES" to jsonArrayOf("728x90"), "BANNER_SIZES_BY_ZONE" to byZone))
    }

    @Test
    fun `the conformance fixtures resolve per zone`() {
        val obj = FixtureLoader.jsonObject("fixtures/app-config/valid/by-zone-maps-objects.json")

        assertEquals(listOf(Size(300, 250), Size(320, 50)), SellwildAdSizes.remoteSizes(obj, "43").value)
        assertEquals(listOf(Size(300, 600), Size(300, 250)), SellwildAdSizes.remoteSizes(obj, "280").value)
        assertEquals(listOf(Size(300, 250)), SellwildAdSizes.remoteSizes(obj, "999").value)
    }

    @Test
    fun `entries that do not parse or are not positive are dropped and reported once`() {
        val raw = AppConfigFactory.offSchema(
            mapOf(
                "BANNER_SIZES" to jsonArrayOf(
                    "320x50", "300x", "0x250", "300x0", jsonArrayOf(0, 50), jsonArrayOf(300, 0), jsonArrayOf(1, 2, 3), 300,
                ),
            ),
        )

        val sizes = SellwildAdSizes.resolve(raw.toString(), "43", mrec)

        assertEquals(listOf(mrec, Size(320, 50)), sizes)
        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_BANNER_SIZES_INVALID, event.action)
        assertEquals("remoteConfig", event.label)
        assertEquals("warn", event.attributes["severity"])
        assertEquals("BANNER_SIZES: dropped 7 of 8 entries", event.attributes["msg"])
        assertEquals(null, event.attributes["zoneId"])
    }

    @Test
    fun `a size text with more than two parts is dropped and reported once`() {
        val json = AppConfigFactory.offSchema(mapOf("BANNER_SIZES" to jsonArrayOf("300x250x5", "320x50"))).toString()

        val sizes = SellwildAdSizes.resolve(json, "43", mrec)

        assertEquals(listOf(mrec, Size(320, 50)), sizes)
        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_BANNER_SIZES_INVALID, event.action)
        assertEquals("BANNER_SIZES: dropped 1 of 2 entries", event.attributes["msg"])
    }

    @Test
    fun `the same bad config is reported once, however often a banner resolves it`() {
        val byZone = JSONObject().put("43", "big")
        val json = AppConfigFactory.offSchema(mapOf("BANNER_SIZES" to jsonArrayOf("320x50", "wide"), "BANNER_SIZES_BY_ZONE" to byZone)).toString()

        repeat(3) {
            assertEquals(listOf(mrec), SellwildAdSizes.resolve(json, "43", mrec))
            assertEquals(listOf(mrec, Size(320, 50)), SellwildAdSizes.resolve(json, "280", mrec))
            assertEquals(listOf(mrec, Size(320, 50)), SellwildAdSizes.resolve(json, "999", mrec))
        }

        assertEquals(2, gateCalls(SellwildFailureCode.CONFIG_BANNER_SIZES_INVALID))
        assertEquals(
            listOf("BANNER_SIZES_BY_ZONE[43]: dropped 1 of 1 entries" to "43", "BANNER_SIZES: dropped 1 of 2 entries" to null),
            sink.pushed.map { it.attributes["msg"] to it.attributes["zoneId"] },
        )
    }

    @Test
    fun `a bad zone entry names its zone`() {
        val byZone = JSONObject().put("43", "big")

        assertEquals(listOf(mrec), resolve("43", "BANNER_SIZES_BY_ZONE" to byZone))

        val event = sink.pushed.single()
        assertEquals("BANNER_SIZES_BY_ZONE[43]: dropped 1 of 1 entries", event.attributes["msg"])
        assertEquals("43", event.attributes["zoneId"])
    }

    @Test
    fun `a different bad entry in each zone is reported for each zone, even with the same counts`() {
        val byZone = JSONObject().put("43", "big").put("280", "huge")
        val json = AppConfigFactory.checked(mapOf("BANNER_SIZES_BY_ZONE" to byZone)).toString()

        repeat(2) {
            assertEquals(listOf(mrec), SellwildAdSizes.resolve(json, "43", mrec))
            assertEquals(listOf(mrec), SellwildAdSizes.resolve(json, "280", mrec))
        }

        assertEquals(2, gateCalls(SellwildFailureCode.CONFIG_BANNER_SIZES_INVALID))
        assertEquals(
            listOf("BANNER_SIZES_BY_ZONE[43]: dropped 1 of 1 entries" to "43", "BANNER_SIZES_BY_ZONE[280]: dropped 1 of 1 entries" to "280"),
            sink.pushed.map { it.attributes["msg"] to it.attributes["zoneId"] },
        )
    }

    @Test
    fun `text that looks like a list but is not one is one bad entry, reported with its parse error`() {
        assertEquals(listOf(mrec), resolve("43", "BANNER_SIZES" to "[300x250"))

        val event = sink.pushed.single()
        // The parser's own words follow the message; they differ between org.json builds.
        assertTrue(event.attributes["msg"].orEmpty().startsWith("BANNER_SIZES: dropped 1 of 1 entries: "))
        assertEquals("JSONException", event.attributes["errName"])
    }

    @Test
    fun `a value of another type is one bad entry`() {
        val json = AppConfigFactory.offSchema(mapOf("BANNER_SIZES" to 300)).toString()

        assertEquals(listOf(mrec), SellwildAdSizes.resolve(json, "43", mrec))

        val event = sink.pushed.single()
        assertEquals("BANNER_SIZES: dropped 1 of 1 entries", event.attributes["msg"])
        // Nothing threw: there is no error to name.
        assertEquals(null, event.attributes["errName"])
    }

    @Test
    fun `the bounding size fits every size`() {
        assertEquals(Size(320, 250), SellwildAdSizes.boundingSize(listOf(Size(300, 250), Size(320, 50))))
        assertEquals(Size(320, 250), SellwildAdSizes.boundingSize(listOf(Size(320, 50), Size(300, 250))))
        assertEquals(Size(0, 0), SellwildAdSizes.boundingSize(emptyList()))
    }
}
