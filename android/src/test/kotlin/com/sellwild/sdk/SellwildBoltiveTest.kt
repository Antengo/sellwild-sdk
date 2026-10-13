package com.sellwild.sdk

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the Boltive policy: the on/off switch precedence, the client
 * id requirement, and the sampling / per-session / per-slot caps.
 */
class SellwildBoltiveTest {

    private val zone = "43"

    private fun json(vararg pairs: Pair<String, Any>): String =
        JSONObject().apply { pairs.forEach { (k, v) -> put(k, v) } }.toString()

    private val on = arrayOf<Pair<String, Any>>(
        "MOBILE_BOLTIVE_ENABLED" to true,
        "MOBILE_BOLTIVE_CLIENT_ID" to "abc",
    )

    @Test fun offByDefault() {
        assertNull(SellwildBoltive.policy(null, zone))
        assertNull(SellwildBoltive.policy(json("MOBILE_BOLTIVE_CLIENT_ID" to "abc"), zone))
    }

    @Test fun requiresClientId() {
        assertNull(SellwildBoltive.policy(json("MOBILE_BOLTIVE_ENABLED" to true), zone))
        assertNull(SellwildBoltive.policy(json("MOBILE_BOLTIVE_ENABLED" to true, "MOBILE_BOLTIVE_CLIENT_ID" to "  "), zone))
    }

    @Test fun enabledDefaults() {
        assertEquals(
            SellwildBoltive.Policy("abc", sampleRate = 1.0, maxPerSession = 0, maxPerSlot = 0),
            SellwildBoltive.policy(json(*on), zone),
        )
    }

    @Test fun stringAndNumberTruthiness() {
        assertTrue(SellwildBoltive.isEnabled(json("MOBILE_BOLTIVE_ENABLED" to "true"), zone))
        assertTrue(SellwildBoltive.isEnabled(json("MOBILE_BOLTIVE_ENABLED" to 1), zone))
        assertFalse(SellwildBoltive.isEnabled(json("MOBILE_BOLTIVE_ENABLED" to "off"), zone))
    }

    @Test fun platformOverride() {
        assertNull(
            "platform false is a hard kill",
            SellwildBoltive.policy(json(*on, "MOBILE_BOLTIVE_ENABLED_ANDROID" to false), zone),
        )
        assertTrue(SellwildBoltive.isEnabled(json("MOBILE_BOLTIVE_ENABLED_ANDROID" to true), zone))
        assertFalse(
            SellwildBoltive.isEnabled(
                json(
                    "MOBILE_BOLTIVE_ENABLED_ANDROID" to false,
                    "MOBILE_BOLTIVE_ENABLED_BY_ZONE" to JSONObject().put(zone, true),
                ),
                zone,
            ),
        )
    }

    @Test fun perZone() {
        val v = json(
            "MOBILE_BOLTIVE_ENABLED" to false,
            "MOBILE_BOLTIVE_ENABLED_BY_ZONE" to JSONObject().put(zone, true),
        )
        assertTrue(SellwildBoltive.isEnabled(v, zone))
        assertFalse(SellwildBoltive.isEnabled(v, "other"))
        assertFalse(SellwildBoltive.isEnabled(v, null))
    }

    @Test fun capsAndSampleRateParsing() {
        assertEquals(
            SellwildBoltive.Policy("abc", sampleRate = 0.25, maxPerSession = 50, maxPerSlot = 3),
            SellwildBoltive.policy(
                json(
                    *on,
                    "MOBILE_BOLTIVE_SAMPLE_RATE" to "0.25",
                    "MOBILE_BOLTIVE_MAX_PER_SESSION" to 50,
                    "MOBILE_BOLTIVE_MAX_PER_SLOT" to "3",
                ),
                zone,
            ),
        )
        val p = SellwildBoltive.policy(
            json(*on, "MOBILE_BOLTIVE_SAMPLE_RATE" to 7, "MOBILE_BOLTIVE_MAX_PER_SLOT" to -2),
            zone,
        )
        assertEquals("clamped to [0, 1]", 1.0, p!!.sampleRate, 0.0)
        assertEquals("negative = unlimited", 0, p.maxPerSlot)
    }

    @Test fun shouldMonitor() {
        val p = SellwildBoltive.Policy("abc", sampleRate = 0.5, maxPerSession = 10, maxPerSlot = 2)
        assertTrue(SellwildBoltive.shouldMonitor(p, slotCount = 0, sessionCount = 0, roll = 0.49))
        assertFalse(SellwildBoltive.shouldMonitor(p, slotCount = 0, sessionCount = 0, roll = 0.5))
        assertFalse("slot cap", SellwildBoltive.shouldMonitor(p, slotCount = 2, sessionCount = 0, roll = 0.0))
        assertFalse("session cap", SellwildBoltive.shouldMonitor(p, slotCount = 0, sessionCount = 10, roll = 0.0))
        val none = SellwildBoltive.Policy("abc", sampleRate = 0.0, maxPerSession = 0, maxPerSlot = 0)
        assertFalse(SellwildBoltive.shouldMonitor(none, slotCount = 0, sessionCount = 0, roll = 0.0))
        val all = SellwildBoltive.Policy("abc", sampleRate = 1.0, maxPerSession = 0, maxPerSlot = 0)
        assertTrue(SellwildBoltive.shouldMonitor(all, slotCount = 999, sessionCount = 999, roll = 0.999))
    }
}
