package com.sellwild.sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for [SellwildGeo] — the North America alpha-2 → alpha-3 country
 * map used to seed `device.geo.country` from the CloudFront viewer header, and
 * the `toOrtbGeo` serialization. Parity with iOS SellwildGeoTests.
 */
class SellwildGeoTest {

    @Test
    fun `every North America country maps to alpha-3, in any case`() {
        val expected = mapOf(
            "US" to "USA", "CA" to "CAN", "MX" to "MEX", "GT" to "GTM", "BZ" to "BLZ", "SV" to "SLV", "HN" to "HND",
            "NI" to "NIC", "CR" to "CRI", "PA" to "PAN", "GL" to "GRL", "BM" to "BMU", "PM" to "SPM",
        )
        for ((alpha2, alpha3) in expected) {
            assertEquals(alpha3, SellwildGeo.northAmericaAlpha3(alpha2))
            assertEquals(alpha3, SellwildGeo.northAmericaAlpha3(alpha2.lowercase()))
        }
    }

    @Test
    fun `outside North America is null`() {
        listOf("GB", "IN", "DE", "", "USA").forEach { assertNull(it, SellwildGeo.northAmericaAlpha3(it)) }
    }

    @Test
    fun `toOrtbGeo maps every set field, state onto region`() {
        val geo = SellwildGeo(country = "USA", state = "NY", city = "Albany", zip = "12207", metro = "532", lat = 42.65, lon = -73.75, type = 2)

        val ortb = geo.toOrtbGeo()!!

        assertEquals(setOf("country", "region", "city", "zip", "metro", "lat", "lon", "type"), ortb.keys().asSequence().toSet())
        assertEquals("USA", ortb.getString("country"))
        assertEquals("NY", ortb.getString("region"))
        assertEquals("Albany", ortb.getString("city"))
        assertEquals("12207", ortb.getString("zip"))
        assertEquals("532", ortb.getString("metro"))
        assertEquals(42.65, ortb.getDouble("lat"), 0.0)
        assertEquals(-73.75, ortb.getDouble("lon"), 0.0)
        assertEquals(2, ortb.getInt("type"))
    }

    @Test
    fun `empty text fields are left out, and nothing set is null`() {
        assertNull(SellwildGeo().toOrtbGeo())
        assertNull(SellwildGeo(country = "", state = "", city = "", zip = "", metro = "").toOrtbGeo())
        assertEquals(setOf("lat"), SellwildGeo(lat = 1.5).toOrtbGeo()!!.keys().asSequence().toSet())
    }

    @Test
    fun `the store holds the current geo`() {
        val before = SellwildGeoStore.current
        try {
            SellwildGeoStore.current = SellwildGeo(state = "GA")
            assertEquals("GA", SellwildGeoStore.current?.state)
        } finally {
            SellwildGeoStore.current = before
        }
    }
}
