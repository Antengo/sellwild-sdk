package com.sellwild.sdk

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
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/**
 * Unit tests for [SellwildAdStack] parsing + resolution. These pin down the
 * decision of WHICH ad SDK stack a placement runs (GAM vs Prebid) before the
 * view touches any Android `Context`, and the config.adstack.invalid report for
 * a mode the SDK does not know.
 */
class SellwildAdStackTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun config(vararg entries: Pair<String, Any?>): String = AppConfigFactory.checked(mapOf(*entries)).toString()

    private fun zones(vararg entries: Pair<String, Any>): JSONObject = JSONObject().apply { entries.forEach { (k, v) -> put(k, v) } }

    @Test
    fun `parse is case and alias tolerant`() {
        val aliases = mapOf(
            SellwildAdStack.BOTH to listOf("BOTH", "all", "default"),
            SellwildAdStack.GAM_ONLY to listOf("GAM", "gam-only", "google", "gads", "Google Ads"),
            SellwildAdStack.PREBID_ONLY to listOf("PREBID_ONLY", "prebid", "prebidOnly", "prebid sdk"),
        )
        for ((stack, names) in aliases) names.forEach { assertEquals(it, stack, SellwildAdStack.parse(it)) }
    }

    @Test
    fun `parse returns null for unknown or null`() {
        assertNull(SellwildAdStack.parse("xyz"))
        assertNull(SellwildAdStack.parse(""))
        assertNull(SellwildAdStack.parse(null))
    }

    @Test
    fun `resolve defaults to BOTH when nothing is set`() {
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(null, "43"))
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(config(), "43"))
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(config("AD_STACK" to "", "AD_STACK_BY_ZONE" to ""), "43"))
        assertEquals("nothing to report", emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `resolve hard-wins on global AD_STACK over per-zone`() {
        val json = FixtureLoader.text("fixtures/app-config/valid/ad-stack-global-wins.json")

        assertEquals(SellwildAdStack.GAM_ONLY, SellwildAdStack.resolve(json, "43"))
        assertEquals(SellwildAdStack.GAM_ONLY, SellwildAdStack.resolve(json, null))
    }

    @Test
    fun `resolve applies per-zone when no global`() {
        val json = config("AD_STACK_BY_ZONE" to zones("43" to "gamOnly", "99" to "prebidOnly", "7" to ""))

        assertEquals(SellwildAdStack.GAM_ONLY, SellwildAdStack.resolve(json, "43"))
        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(json, "99"))
        assertEquals("'' is unset", SellwildAdStack.BOTH, SellwildAdStack.resolve(json, "7"))
        assertEquals("unlisted zone", SellwildAdStack.BOTH, SellwildAdStack.resolve(json, "8"))
        assertEquals("no zone", SellwildAdStack.BOTH, SellwildAdStack.resolve(json, null))
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `resolve override beats remote config`() {
        assertEquals(
            SellwildAdStack.PREBID_ONLY,
            SellwildAdStack.resolve(config("AD_STACK" to "GAM"), "43", override = SellwildAdStack.PREBID_ONLY),
        )
    }

    @Test
    fun `remote JSON that does not parse falls back to BOTH and is reported`() {
        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml"), "43"))

        assertEquals(listOf(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE), sink.pushed.map { it.action })
    }

    @Test
    fun `an unknown global mode falls through to the zone and is reported`() {
        val json = config("AD_STACK" to "gamm", "AD_STACK_BY_ZONE" to zones("43" to "prebid"))

        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(json, "43"))

        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_ADSTACK_INVALID, event.action)
        assertEquals("remoteConfig", event.label)
        assertEquals("warn", event.attributes["severity"])
        assertEquals("AD_STACK is not a known mode: gamm", event.attributes["msg"])
    }

    @Test
    fun `an unknown zone mode is dropped and reported with its zone`() {
        val json = config("AD_STACK_BY_ZONE" to zones("43" to "gam", "280" to 5))

        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(json, "280"))

        val event = sink.pushed.single()
        assertEquals(SellwildFailureCode.CONFIG_ADSTACK_INVALID, event.action)
        assertEquals("AD_STACK_BY_ZONE entry is not a known mode: 5", event.attributes["msg"])
        assertEquals("280", event.attributes["zoneId"])
    }

    @Test
    fun `the same bad config is reported once, however often placements resolve it`() {
        val json = config("AD_STACK" to "gamm", "AD_STACK_BY_ZONE" to zones("43" to "prebid", "280" to "nope"))

        repeat(3) {
            assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.resolve(json, "43"))
            assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(json, "280"))
        }

        assertEquals(2, gateCalls(SellwildFailureCode.CONFIG_ADSTACK_INVALID))
        assertEquals(
            listOf("AD_STACK is not a known mode: gamm", "AD_STACK_BY_ZONE entry is not a known mode: nope"),
            sink.pushed.map { it.attributes["msg"] },
        )
    }

    @Test
    fun `the same bad mode in two zones is one report, as the gate dedupe key has no zone`() {
        val json = config("AD_STACK_BY_ZONE" to zones("43" to "nope", "280" to "nope", "7" to "gamm"))

        repeat(2) { SellwildAdStack.resolve(json, "43") }

        assertEquals(2, gateCalls(SellwildFailureCode.CONFIG_ADSTACK_INVALID))
        assertEquals(
            setOf("AD_STACK_BY_ZONE entry is not a known mode: nope", "AD_STACK_BY_ZONE entry is not a known mode: gamm"),
            sink.pushed.map { it.attributes["msg"] }.toSet(),
        )
    }

    @Test
    fun `a new config text is new, so its bad values are reported again`() {
        failures.expectRepeats()
        val first = config("AD_STACK" to "gamm")
        val refreshed = config("AD_STACK" to "gamm", "AD_STACK_BY_ZONE" to zones("43" to "gam"))

        SellwildAdStack.resolve(first, "43")
        SellwildAdStack.resolve(refreshed, "43")
        SellwildAdStack.resolve(refreshed, "43")

        assertEquals(2, gateCalls(SellwildFailureCode.CONFIG_ADSTACK_INVALID))
    }

    @Test
    fun `only the last 8 config texts are remembered`() {
        failures.expectRepeats()
        val texts = (0..8).map { config("AD_STACK" to "bad$it") }

        texts.forEach { SellwildAdStack.resolve(it, "43") }
        SellwildAdStack.resolve(texts[8], "43")
        assertEquals("nine texts, each reported once", 9, gateCalls(SellwildFailureCode.CONFIG_ADSTACK_INVALID))

        SellwildAdStack.resolve(texts[0], "43")
        assertEquals("the oldest text was forgotten, so it is new again", 10, gateCalls(SellwildFailureCode.CONFIG_ADSTACK_INVALID))
    }

    @Test
    fun `a by-zone value that is not a map is reported`() {
        val json = AppConfigFactory.offSchema(mapOf("AD_STACK_BY_ZONE" to jsonArrayOf("gam"))).toString()

        assertEquals(SellwildAdStack.BOTH, SellwildAdStack.resolve(json, "43"))

        assertEquals("AD_STACK_BY_ZONE is not a map", sink.pushed.single().attributes["msg"])
    }

    @Test
    fun `global and byZone parse the raw keys for every zone`() {
        val obj = AppConfigFactory.checked(mapOf("AD_STACK" to "prebid", "AD_STACK_BY_ZONE" to zones("43" to "GAM", "280" to "nope", "7" to "")))

        assertEquals(SellwildAdStack.PREBID_ONLY, SellwildAdStack.global(obj).value)
        assertEquals(mapOf("43" to SellwildAdStack.GAM_ONLY), SellwildAdStack.byZone(obj).value)
        assertEquals(1, SellwildAdStack.byZone(obj).issues.size)
        assertNull(SellwildAdStack.global(null).value)
        assertEquals(emptyMap<String, SellwildAdStack>(), SellwildAdStack.byZone(null).value)
    }
}
