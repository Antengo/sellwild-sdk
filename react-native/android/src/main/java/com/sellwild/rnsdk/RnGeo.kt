package com.sellwild.rnsdk

import com.facebook.react.bridge.ReadableMap
import com.sellwild.sdk.SellwildGeo

/**
 * Marshals a bridged JS geo object (React `ReadableMap`) into the native
 * [SellwildGeo]. Lives in the RN module (not core) because `ReadableMap` is a
 * React type — the core SDK must not depend on React. The geo is null when
 * nothing usable is present, so callers can clear geo by passing an empty object.
 */
internal object RnGeo {
    /** A bridged geo: the geo to set (null clears), and why each dropped field was dropped. */
    class Parsed(val geo: SellwildGeo?, val problems: List<String>)

    /**
     * Reads each field by its type. A field of another type (for example lat
     * sent as text) is dropped and named in [Parsed.problems]; the other
     * fields are kept, as the iOS bridge keeps them. ReadableMap getters
     * throw for a field of another type, so none is called for one.
     */
    fun parse(map: ReadableMap?): Parsed {
        if (map == null) return Parsed(null, emptyList())
        val dropped = RnBridgeRules.geoWrongTyped { if (map.hasKey(it)) map.getType(it).name else null }
        fun readable(k: String) = map.hasKey(k) && !map.isNull(k) && k !in dropped
        fun str(k: String) = if (readable(k)) map.getString(k) else null
        fun dbl(k: String) = if (readable(k)) map.getDouble(k) else null
        fun int(k: String) = if (readable(k)) map.getInt(k) else null
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
        return Parsed(if (geo.toOrtbGeo() != null) geo else null, dropped.values.toList())
    }

    /**
     * The geo inside a view's config prop. As before, a field of the wrong
     * type throws, and the view manager reports the whole config
     * (`bridge.config.invalid`); the message names the fields, never a value.
     */
    fun readableMapToGeo(map: ReadableMap?): SellwildGeo? {
        val parsed = parse(map)
        if (parsed.problems.isNotEmpty()) throw IllegalArgumentException(parsed.problems.joinToString("; "))
        return parsed.geo
    }
}
