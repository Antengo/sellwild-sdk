package com.sellwild.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for [SellwildGeo] — the North America alpha-2 → alpha-3 country
 * map used to seed `device.geo.country` from the CloudFront viewer header, and
 * the `toOrtbGeo` serialization. Parity with iOS SellwildGeoTests.
 */
class SellwildGeoTest {

    @Test
    fun northAmericaCoreCountries() {
        assertEquals("USA", SellwildGeo.northAmericaAlpha3("US"))
        assertEquals("CAN", SellwildGeo.northAmericaAlpha3("CA"))
        assertEquals("MEX", SellwildGeo.northAmericaAlpha3("MX"))
    }

    @Test
    fun northAmericaExtendedCountries() {
        assertEquals("GTM", SellwildGeo.northAmericaAlpha3("GT"))
        assertEquals("CRI", SellwildGeo.northAmericaAlpha3("CR"))
        assertEquals("PAN", SellwildGeo.northAmericaAlpha3("PA"))
        assertEquals("GRL", SellwildGeo.northAmericaAlpha3("GL"))
    }

    @Test
    fun caseInsensitive() {
        assertEquals("USA", SellwildGeo.northAmericaAlpha3("us"))
        assertEquals("MEX", SellwildGeo.northAmericaAlpha3("Mx"))
    }

    @Test
    fun outsideNorthAmericaReturnsNull() {
        assertNull(SellwildGeo.northAmericaAlpha3("GB"))
        assertNull(SellwildGeo.northAmericaAlpha3("IN"))
        assertNull(SellwildGeo.northAmericaAlpha3("DE"))
        assertNull(SellwildGeo.northAmericaAlpha3(""))
    }

    @Test
    fun toOrtbGeoMapsCountryAndRegion() {
        val g = SellwildGeo(country = "USA", state = "NY").toOrtbGeo()
        assertNotNull(g)
        assertEquals("USA", g!!.optString("country"))
        assertEquals("NY", g.optString("region"))   // state -> region
    }
}
