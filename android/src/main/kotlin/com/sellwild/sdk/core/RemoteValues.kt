package com.sellwild.sdk.core

import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONException
import org.json.JSONObject

/**
 * Pure readers for raw CDN values in the stored remote config (SellwildConfig.remoteJson).
 * Each keeps the exact coercion its callers used before they shared it.
 */
internal object RemoteValues {

    /**
     * The stored remote config as an object. Blank text means no config. Text that does
     * not parse gives null and a config.remote_values.parse issue, and every flag read from
     * it falls back to its default.
     */
    fun parse(remoteJson: String?): Resolved<JSONObject?> {
        if (remoteJson.isNullOrBlank()) return Resolved(null)
        return try {
            Resolved(JSONObject(remoteJson))
        } catch (e: JSONException) {
            Resolved(
                null,
                listOf(
                    Issue(
                        SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE,
                        SellwildFailureComponent.REMOTE_CONFIG,
                        SellwildFailureSeverity.WARN,
                        error = e,
                    ),
                ),
            )
        }
    }

    /** The value at [key]; null when [obj] is null, or the key is absent or JSON null. */
    fun optAny(obj: JSONObject?, key: String): Any? =
        if (obj != null && obj.has(key) && !obj.isNull(key)) obj.get(key) else null

    /**
     * The value at [key] as optString reads it (text as is, a number or boolean as its text),
     * or null when [obj] is null or the key is absent or JSON null. A device's org.json
     * returns the text "null" from optString for JSON null, which would then be used as a
     * partner id, host or URL.
     */
    fun optText(obj: JSONObject?, key: String): String? =
        if (obj == null || obj.isNull(key)) null else obj.optString(key)

    /**
     * The per-zone entry `obj[mapKey][zoneId]`: null without a zone, when the map is not
     * an object (the CMS writes '' when unset), or when the zone is absent or JSON null.
     */
    fun byZone(obj: JSONObject?, mapKey: String, zoneId: String?): Any? {
        if (zoneId == null) return null
        return optAny(obj?.optJSONObject(mapKey), zoneId)
    }

    /**
     * A default-off flag (VIDEO_ENABLED, NATIVE_ENABLED, GROWTHCODE_*): true, a number
     * whose integer part is not 0, or "1"/"true"/"yes"/"on" in any case.
     */
    fun isOn(v: Any?): Boolean = when (v) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        is String -> v.lowercase() in ON_WORDS
        else -> false
    }

    /**
     * A default-on flag (MOBILE_HOUSE_AD_ENABLED, MOBILE_AD_MUTE_AUTOPLAY): only false, a
     * number whose integer part is 0, or "0"/"false"/"no"/"off" in any case turn it off.
     */
    fun isNotOff(v: Any?): Boolean = when (v) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        is String -> v.lowercase() !in OFF_WORDS
        else -> true
    }

    /** A number, or text that parses as one; else null. */
    fun number(v: Any?): Double? = when (v) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
    }

    private val ON_WORDS = setOf("1", "true", "yes", "on")
    private val OFF_WORDS = setOf("0", "false", "no", "off")
}
