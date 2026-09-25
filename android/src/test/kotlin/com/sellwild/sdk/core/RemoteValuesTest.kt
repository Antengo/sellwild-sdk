package com.sellwild.sdk.core

import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.jsonArrayOf
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pure readers every remote-config resolver shares. */
class RemoteValuesTest {

    @Test
    fun `parse gives the object, nothing for no config, and an issue for text that is not an object`() {
        val config = AppConfigFactory.checked()

        assertEquals("minimal", RemoteValues.parse(config.toString()).value?.getString("CODE"))
        assertEquals(emptyList<Issue>(), RemoteValues.parse(config.toString()).issues)
        assertEquals(Resolved<JSONObject?>(null), RemoteValues.parse(null))
        assertEquals(Resolved<JSONObject?>(null), RemoteValues.parse("  "))

        val bad = RemoteValues.parse(FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml"))
        assertNull(bad.value)
        val issue = bad.issues.single()
        assertEquals(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE, issue.code)
        assertEquals("remoteConfig", issue.component)
        assertEquals("warn", issue.severity)
        assertTrue(issue.error is JSONException)
    }

    @Test
    fun `optAny reads a value, and absent or JSON null as nothing`() {
        val obj = AppConfigFactory.offSchema(mapOf("TITLE" to JSONObject.NULL, "MARGIN_BOTTOM" to 14))

        assertEquals(14, RemoteValues.optAny(obj, "MARGIN_BOTTOM"))
        assertNull(RemoteValues.optAny(obj, "TITLE"))
        assertNull(RemoteValues.optAny(obj, "NOT_THERE"))
        assertNull(RemoteValues.optAny(null, "MARGIN_BOTTOM"))
    }

    @Test
    fun `byZone reads the zone entry of a map, and nothing without a zone, a map or an entry`() {
        val obj = AppConfigFactory.checked(
            mapOf(
                "VIDEO_ENABLED_BY_ZONE" to JSONObject().put("43", true).put("280", false),
                "NATIVE_ENABLED_BY_ZONE" to "",
            ),
        )

        assertEquals(true, RemoteValues.byZone(obj, "VIDEO_ENABLED_BY_ZONE", "43"))
        assertEquals(false, RemoteValues.byZone(obj, "VIDEO_ENABLED_BY_ZONE", "280"))
        assertNull(RemoteValues.byZone(obj, "VIDEO_ENABLED_BY_ZONE", "999"))
        assertNull(RemoteValues.byZone(obj, "VIDEO_ENABLED_BY_ZONE", null))
        assertNull("'' is the CMS's unset map", RemoteValues.byZone(obj, "NATIVE_ENABLED_BY_ZONE", "43"))
        assertNull(RemoteValues.byZone(null, "VIDEO_ENABLED_BY_ZONE", "43"))
    }

    @Test
    fun `isOn is a default-off flag`() {
        listOf<Any>(true, 1, 2.5, -1, "1", "true", "YES", "On").forEach { assertTrue("$it", RemoteValues.isOn(it)) }
        listOf<Any?>(false, 0, 0.5, "0", "off", "", " true", JSONObject(), jsonArrayOf(), null)
            .forEach { assertFalse("$it", RemoteValues.isOn(it)) }
    }

    @Test
    fun `isNotOff is a default-on flag`() {
        listOf<Any?>(true, 1, "yes", "anything", "", JSONObject(), null).forEach { assertTrue("$it", RemoteValues.isNotOff(it)) }
        listOf<Any>(false, 0, 0.5, "0", "FALSE", "No", "off").forEach { assertFalse("$it", RemoteValues.isNotOff(it)) }
    }

    @Test
    fun `number reads numbers and numeric text`() {
        assertEquals(24.0, RemoteValues.number(24)!!, 0.0)
        assertEquals(12.5, RemoteValues.number("12.5")!!, 0.0)
        assertNull(RemoteValues.number("24h"))
        assertNull(RemoteValues.number(true))
        assertNull(RemoteValues.number(null))
    }
}
