package com.sellwild.sdk

import org.json.JSONObject

/**
 * Client-side GPID (Global Placement ID) resolution + imp-ext construction.
 *
 * On every native Prebid auction we set BOTH `imp.ext.gpid` AND
 * `imp.ext.data.pbadslot` to the SAME value, per placement, so demand can key
 * on a stable placement identifier.
 *
 * The value string:
 *   - `base` normally, authored remotely per zone.
 *   - `base#n` (1-based, row order) when one feed screen uses the same base for
 *     more than one ad slot — the feed computes the suffix and injects it via
 *     [SellwildAdView.gpidOverride]; standalone views use the bare base.
 *
 * `base` is resolved from `remoteJson`: the per-zone `GPID_BASE_BY_ZONE[zoneId]`
 * wins, else the top-level `GPID_BASE` string. Neither present → null, and the
 * imp carries no gpid/pbadslot at all.
 */
object SellwildGpid {

    /**
     * Resolve the GPID base for a placement.
     *
     * Precedence:
     *   1. Per-zone `GPID_BASE_BY_ZONE[zoneId]`.
     *   2. Top-level `GPID_BASE` string.
     *   3. null — send nothing (no gpid/pbadslot on the imp).
     */
    fun resolveBase(remoteJson: String?, zoneId: String?): String? {
        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null

        if (zoneId != null) {
            val byZone = obj.optJSONObject("GPID_BASE_BY_ZONE")
            byZone?.optStringOrNull(zoneId)?.let { return it }
        }

        return obj.optStringOrNull("GPID_BASE")
    }

    /**
     * Build the imp-ext ORTB JSON string shared by both ad-stack paths. Shape:
     * ```
     * { "ext": { "gpid": "<v>", "data": { "pbadslot": "<v>" },
     *            "prebid": { "bidder": { …bidder params… } } } }
     * ```
     * Both `ext.gpid` and `ext.data.pbadslot` carry the same [gpid]. The
     * `ext.prebid.bidder` block is emitted only when [bidderParams] is non-empty
     * (the `.both` path forwards CDN bidder params here; `.prebidOnly` passes
     * none). Bidder names are lowercased — CDN ships CONSTANT_CASE, Prebid
     * expects lowercase.
     *
     * Returns null when there is nothing to set (no gpid AND no bidder params),
     * so callers can skip `setImpOrtbConfig` entirely.
     */
    fun impExtJson(gpid: String?, bidderParams: Map<String, Any?> = emptyMap()): String? {
        val bidders = JSONObject()
        for ((k, v) in bidderParams) {
            if (v == null) continue
            bidders.put(k.lowercase(), v)
        }

        val hasGpid = !gpid.isNullOrEmpty()
        if (!hasGpid && bidders.length() == 0) return null

        val ext = JSONObject()
        if (hasGpid) {
            ext.put("gpid", gpid)
            ext.put("data", JSONObject().apply { put("pbadslot", gpid) })
        }
        if (bidders.length() > 0) {
            ext.put("prebid", JSONObject().apply { put("bidder", bidders) })
        }
        return JSONObject().apply { put("ext", ext) }.toString()
    }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotEmpty() } else null
}
