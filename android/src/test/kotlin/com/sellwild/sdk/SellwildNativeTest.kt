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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/**
 * [SellwildNative]'s remote toggles and [SellwildNative.resolveConfigId], the precedence that
 * picks the native placement id: NATIVE_ZID_ANDROID -> NATIVE_ZID_ALL_ANDROID -> NATIVE_ZID
 * -> <mobile zoneId>. The fork request builder runs in SellwildAdAdaptersTest.
 */
class SellwildNativeTest {

    @get:Rule
    val failures = FailuresRule()

    private val sink = FakeFailureSink()
    private val zone = "banner-zone-43"

    @Before
    fun attachSink() {
        SellwildFailures.bind(sink)
    }

    private fun config(vararg entries: Pair<String, Any?>): String = AppConfigFactory.checked(mapOf(*entries)).toString()

    @Test
    fun `native is off by default, on globally, or per zone`() {
        assertFalse(SellwildNative.isEnabled(null, "43"))
        assertFalse(SellwildNative.isEnabled(config(), "43"))
        assertTrue(SellwildNative.isEnabled(config("NATIVE_ENABLED" to "true"), null))
        val byZone = config("NATIVE_ENABLED" to 0, "NATIVE_ENABLED_BY_ZONE" to JSONObject().put("43", 1).put("280", false))
        assertTrue(SellwildNative.isEnabled(byZone, "43"))
        assertFalse(SellwildNative.isEnabled(byZone, "280"))
        assertFalse(SellwildNative.isEnabled(byZone, "999"))
        assertFalse(SellwildNative.isEnabled(byZone, null))
        assertEquals(emptyList<String>(), sink.pushed.map { it.action })
    }

    @Test
    fun `max height takes the zone value, then the global one, then the slot height`() {
        val json = config("NATIVE_MAX_HEIGHT" to "320", "NATIVE_MAX_HEIGHT_BY_ZONE" to JSONObject().put("43", 250).put("280", 0))

        assertEquals(250, SellwildNative.maxHeight(json, "43", fallback = 100))
        assertEquals("a zone value that is not positive falls through", 320, SellwildNative.maxHeight(json, "280", fallback = 100))
        assertEquals(320, SellwildNative.maxHeight(json, null, fallback = 100))
        assertEquals(100, SellwildNative.maxHeight(config("NATIVE_MAX_HEIGHT" to "tall"), "43", fallback = 100))
        assertEquals(100, SellwildNative.maxHeight(null, "43", fallback = 100))
        assertEquals(100, SellwildNative.maxHeight(AppConfigFactory.offSchema(mapOf("NATIVE_MAX_HEIGHT" to true)).toString(), "43", 100))
    }

    @Test
    fun `falls back to zone when no native keys`() {
        assertEquals(zone, SellwildNative.resolveConfigId(null, zone))
        assertEquals(zone, SellwildNative.resolveConfigId(config(), zone))
        assertEquals(zone, SellwildNative.resolveConfigId(AppConfigFactory.offSchema(mapOf("NATIVE_ZID" to 43)).toString(), zone))
    }

    @Test
    fun `shared native key used when no platform keys`() {
        assertEquals("native-shared", SellwildNative.resolveConfigId(config("NATIVE_ZID" to "native-shared"), zone))
    }

    @Test
    fun `platform-all beats shared`() {
        assertEquals(
            "native-android-all",
            SellwildNative.resolveConfigId(config("NATIVE_ZID_ALL_ANDROID" to "native-android-all", "NATIVE_ZID" to "native-shared"), zone),
        )
    }

    @Test
    fun `per-platform beats everything`() {
        val json = config(
            "NATIVE_ZID_ANDROID" to "native-android",
            "NATIVE_ZID_ALL_ANDROID" to "native-android-all",
            "NATIVE_ZID" to "native-shared",
        )
        assertEquals("native-android", SellwildNative.resolveConfigId(json, zone))
    }

    @Test
    fun `array value takes first non-empty`() {
        assertEquals(
            "native-android-a",
            SellwildNative.resolveConfigId(config("NATIVE_ZID_ANDROID" to jsonArrayOf("", "native-android-a", "native-android-b")), zone),
        )
    }

    @Test
    fun `empty value falls through to next tier`() {
        // Empty per-platform string/array must not shadow a valid lower tier.
        val json = config("NATIVE_ZID_ANDROID" to "", "NATIVE_ZID_ALL_ANDROID" to jsonArrayOf(), "NATIVE_ZID" to "native-shared")
        assertEquals("native-shared", SellwildNative.resolveConfigId(json, zone))
    }

    @Test
    fun `config that does not parse is reported and every toggle falls back`() {
        val bad = FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml")

        assertFalse(SellwildNative.isEnabled(bad, "43"))
        assertEquals(90, SellwildNative.maxHeight(bad, "43", 90))
        assertEquals(zone, SellwildNative.resolveConfigId(bad, zone))

        // Reported once for the text, not on each of the three reads (FAILURES.md 9).
        assertEquals(listOf(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE), sink.pushed.map { it.action })
        assertEquals(1, gateCalls(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE))
    }

    @Test
    fun `another config text that does not parse is reported again`() {
        assertFalse(SellwildNative.isEnabled("{\"NATIVE_ENABLED\"", "43"))
        assertFalse(SellwildNative.isEnabled("[]", "43"))
        assertFalse(SellwildNative.isEnabled("[]", "43"))

        assertEquals(2, gateCalls(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE))
        assertEquals(listOf("JSONException", "JSONException"), sink.pushed.map { it.attributes["errName"] })
    }
}
