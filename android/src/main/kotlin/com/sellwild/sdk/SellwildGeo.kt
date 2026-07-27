package com.sellwild.sdk

import org.json.JSONObject

/**
 * Partner-supplied geo, emitted as OpenRTB `device.geo` on native Prebid
 * auctions and used to key per-state listing caches. All fields optional —
 * only the ones you set are sent. The SDK never geocodes; the host app supplies
 * resolved values via [SellwildConfig.geo] or [SellwildPrebidMobile.setGeo].
 */
data class SellwildGeo(
    /** ISO-3166-1 alpha-3 country (OpenRTB `device.geo.country`), e.g. "USA". */
    val country: String? = null,
    /** State / region (OpenRTB `device.geo.region`); also keys per-state listing caches. */
    val state: String? = null,
    /** City (OpenRTB `device.geo.city`). */
    val city: String? = null,
    /** Postal / ZIP (OpenRTB `device.geo.zip`). */
    val zip: String? = null,
    /** Google metro / DMA (OpenRTB `device.geo.metro`). */
    val metro: String? = null,
    /** Latitude (OpenRTB `device.geo.lat`). */
    val lat: Double? = null,
    /** Longitude (OpenRTB `device.geo.lon`). */
    val lon: Double? = null,
    /** Geo source (OpenRTB `device.geo.type`): 1=GPS, 2=IP, 3=user. */
    val type: Int? = null,
) {
    /**
     * OpenRTB `device.geo` object built from the non-empty fields (maps [state]
     * onto the ORTB `region` key). Returns null when nothing is set.
     */
    fun toOrtbGeo(): JSONObject? {
        val g = JSONObject()
        country?.takeIf { it.isNotEmpty() }?.let { g.put("country", it) }
        state?.takeIf { it.isNotEmpty() }?.let { g.put("region", it) }
        city?.takeIf { it.isNotEmpty() }?.let { g.put("city", it) }
        zip?.takeIf { it.isNotEmpty() }?.let { g.put("zip", it) }
        metro?.takeIf { it.isNotEmpty() }?.let { g.put("metro", it) }
        lat?.let { g.put("lat", it) }
        lon?.let { g.put("lon", it) }
        type?.let { g.put("type", it) }
        return if (g.length() > 0) g else null
    }
}

/**
 * Process-wide current geo, readable by ANY SDK surface — the native ads path,
 * the listings feed, or host-app code — not just the Prebid auction. Seeded
 * from [SellwildConfig.geo] at bootstrap and updated by
 * [SellwildPrebidMobile.setGeo].
 *
 * Single source of truth for "where is the user"; the Prebid bridge reads from
 * it rather than owning geo privately, so future consumers (e.g. per-state
 * listing caches) can read the same value without going through the ad path.
 */
object SellwildGeoStore {
    @Volatile
    @JvmStatic
    var current: SellwildGeo? = null
}
