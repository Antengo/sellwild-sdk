package com.sellwild.rnsdk

import com.facebook.react.bridge.ReadableMap
import com.sellwild.sdk.SellwildGeo

/**
 * Marshals a bridged JS geo object (React `ReadableMap`) into the native
 * [SellwildGeo]. Lives in the RN module (not core) because `ReadableMap` is a
 * React type — the core SDK must not depend on React. Returns null when nothing
 * usable is present, so callers can clear geo by passing an empty object.
 */
internal object RnGeo {
    fun readableMapToGeo(map: ReadableMap?): SellwildGeo? {
        if (map == null) return null
        fun str(k: String) = if (map.hasKey(k) && !map.isNull(k)) map.getString(k) else null
        fun dbl(k: String) = if (map.hasKey(k) && !map.isNull(k)) map.getDouble(k) else null
        fun int(k: String) = if (map.hasKey(k) && !map.isNull(k)) map.getInt(k) else null
        val geo = SellwildGeo(
            country = str("country"),
            state = str("state"),
            city = str("city"),
            zip = str("zip"),
            metro = str("metro"),
            lat = dbl("lat"),
            lon = dbl("lon"),
            type = int("type"),
        )
        // toOrtbGeo() returns null when every field is empty — treat that as "no geo".
        return if (geo.toOrtbGeo() != null) geo else null
    }
}
