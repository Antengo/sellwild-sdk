package com.sellwild.sdk

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for [SellwildNative.resolveConfigId] — the precedence that picks
 * the native placement id, independent of the Prebid fork request/render.
 *
 * Chain: NATIVE_ZID_ANDROID -> NATIVE_ZID_ALL_ANDROID -> NATIVE_ZID -> <mobile zoneId>.
 */
class SellwildNativeTest {

    private val zone = "banner-zone-43"

    @Test
    fun `falls back to zone when no native keys`() {
        assertEquals(zone, SellwildNative.resolveConfigId(null, zone))
        val empty = JSONObject(mapOf("CODE" to "weatherbug")).toString()
        assertEquals(zone, SellwildNative.resolveConfigId(empty, zone))
    }

    @Test
    fun `shared native key used when no platform keys`() {
        val json = JSONObject(mapOf("NATIVE_ZID" to "native-shared")).toString()
        assertEquals("native-shared", SellwildNative.resolveConfigId(json, zone))
    }

    @Test
    fun `platform-all beats shared`() {
        val json = JSONObject(
            mapOf(
                "NATIVE_ZID_ALL_ANDROID" to "native-android-all",
                "NATIVE_ZID" to "native-shared",
            )
        ).toString()
        assertEquals("native-android-all", SellwildNative.resolveConfigId(json, zone))
    }

    @Test
    fun `per-platform beats everything`() {
        val json = JSONObject(
            mapOf(
                "NATIVE_ZID_ANDROID" to "native-android",
                "NATIVE_ZID_ALL_ANDROID" to "native-android-all",
                "NATIVE_ZID" to "native-shared",
            )
        ).toString()
        assertEquals("native-android", SellwildNative.resolveConfigId(json, zone))
    }

    @Test
    fun `array value takes first non-empty`() {
        val json = JSONObject(
            mapOf("NATIVE_ZID_ANDROID" to JSONArray(listOf("", "native-android-a", "native-android-b")))
        ).toString()
        assertEquals("native-android-a", SellwildNative.resolveConfigId(json, zone))
    }

    @Test
    fun `empty value falls through to next tier`() {
        // Empty per-platform string/array must not shadow a valid lower tier.
        val json = JSONObject(
            mapOf(
                "NATIVE_ZID_ANDROID" to "",
                "NATIVE_ZID_ALL_ANDROID" to JSONArray(emptyList<String>()),
                "NATIVE_ZID" to "native-shared",
            )
        ).toString()
        assertEquals("native-shared", SellwildNative.resolveConfigId(json, zone))
    }
}
