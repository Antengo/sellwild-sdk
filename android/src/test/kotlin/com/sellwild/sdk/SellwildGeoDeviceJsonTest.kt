package com.sellwild.sdk

import com.sellwild.prebid.TargetingParams
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * SellwildGeo.toOrtbGeo with the device's org.json (Robolectric), which refuses a number
 * that is not finite: JSONObject.put throws "Forbidden numeric value: NaN". A partner geo
 * with such a latitude or longitude reaches it from setGeo, bootstrap and the listings geo
 * seed.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildGeoDeviceJsonTest {

    @After
    fun forgetGeo() {
        SellwildGeoStore.current = null
    }

    private fun keys(geo: SellwildGeo): Set<String>? = geo.toOrtbGeo()?.keys()?.asSequence()?.toSet()

    @Test
    fun `a latitude or longitude that is not finite is left out of device geo`() {
        assertEquals(setOf("region"), keys(SellwildGeo(state = "GA", lat = Double.NaN, lon = Double.POSITIVE_INFINITY)))
        assertEquals(setOf("lon"), keys(SellwildGeo(lat = Double.NEGATIVE_INFINITY, lon = -73.75)))
        assertEquals(setOf("lat"), keys(SellwildGeo(lat = 42.65, lon = Double.NaN)))
        assertNull(SellwildGeo(lat = Double.NaN, lon = Double.NaN).toOrtbGeo())
    }

    @Test
    fun `setGeo with a latitude that is not finite stores the geo and sends the rest`() {
        SellwildPrebidMobile.setGeo(SellwildGeo(state = "GA", lat = Double.NaN, lon = -84.39))

        assertEquals("GA", SellwildGeoStore.current?.state)
        val geo = JSONObject(TargetingParams.getGlobalOrtbConfig()).getJSONObject("device").getJSONObject("geo")
        assertEquals(setOf("region", "lon"), geo.keys().asSequence().toSet())
        assertEquals(-84.39, geo.getDouble("lon"), 0.0)
    }
}
