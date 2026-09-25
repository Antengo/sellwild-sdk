// SellwildAdSizes.kt — multi-size banner support.
//
// A placement can request more than one banner size in a single auction/imp so
// demand falls back to a smaller size when the primary doesn't fill (e.g. no
// 300x250 → take 320x50). Sizes are remote-config driven, per-zone, so they're
// tuned from the CDN with no app release:
//   - Global:   BANNER_SIZES           (["300x250","320x50"] or [[300,250],[320,50]])
//   - Per-zone: BANNER_SIZES_BY_ZONE   ({ "<zoneId>": ["300x250","320x50"] })
//
// The primary size (the AdSize the host passes to SellwildAdView) is always
// included and always first; remote entries are additional. Applied to all
// three stacks (BOTH / GAM_ONLY / PREBID_ONLY).
//
// PARSING is pure and verifiable here. The per-stack APPLY helpers touch the
// GAM SDK (solid) and the shaded Prebid fork (verify-on-build) — the single
// place to confirm the fork's multi-size API, mirroring SellwildVideo /
// SellwildNative.

package com.sellwild.sdk

import com.sellwild.sdk.core.Issue
import com.sellwild.sdk.core.RemoteValues
import com.sellwild.sdk.core.Resolved
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import com.google.android.gms.ads.AdSize as GmaAdSize
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.AdSize as PrebidAdSize
import com.sellwild.prebid.BannerAdUnit
import com.sellwild.prebid.api.rendering.BannerView as PrebidBannerView

object SellwildAdSizes {

    /** A banner size in dp. */
    data class Size(val width: Int, val height: Int)

    /**
     * Ordered, de-duplicated size set for a placement: [primary] first, then any
     * remote `BANNER_SIZES` / `BANNER_SIZES_BY_ZONE` entries (per-zone overrides
     * global). Returns `[primary]` when nothing is configured. Entries that do not
     * parse, or are not positive, are dropped and reported as config.banner_sizes.invalid,
     * once per config text.
     */
    fun resolve(remoteJson: String?, zoneId: String?, primary: Size): List<Size> =
        (listOf(primary) + remoteSizes(remoteObject(remoteJson), zoneId).reportedOncePer(remoteJson)).distinct()

    /**
     * The remote sizes for [zoneId], pure: `BANNER_SIZES_BY_ZONE[zoneId]` when that map has
     * the zone, else `BANNER_SIZES`. Only positive sizes, in order, duplicates removed.
     */
    internal fun remoteSizes(obj: JSONObject?, zoneId: String?): Resolved<List<Size>> {
        val zoneValue = RemoteValues.byZone(obj, "BANNER_SIZES_BY_ZONE", zoneId)
        // The zone is in the message: the message holds only counts, and an issue is
        // reported once per code and message (reportedOncePer), so without it a second
        // zone's different bad entry would never be reported.
        val key = if (zoneValue != null) "BANNER_SIZES_BY_ZONE[$zoneId]" else "BANNER_SIZES"
        val (entries, listError) = parseList(zoneValue ?: RemoteValues.optAny(obj, "BANNER_SIZES"))
        val sizes = entries.filterNotNull().filter { it.width > 0 && it.height > 0 }
        val dropped = entries.size - sizes.size
        if (dropped == 0) return Resolved(sizes.distinct())
        val issue = Issue(
            SellwildFailureCode.CONFIG_BANNER_SIZES_INVALID,
            SellwildFailureComponent.REMOTE_CONFIG,
            SellwildFailureSeverity.WARN,
            message = "$key: dropped $dropped of ${entries.size} entries",
            error = listError,
            zoneId = zoneValue?.let { zoneId },
        )
        return Resolved(sizes.distinct(), listOf(issue))
    }

    /**
     * The smallest [Size] that contains every size in the set — `max(width) ×
     * max(height)`. Reserves a slot that fits the widest/tallest creative the
     * auction may return, so a fallback never clips (including on prebidOnly,
     * where the winning creative size isn't surfaced back to the SDK).
     */
    fun boundingSize(sizes: List<Size>): Size =
        Size(sizes.maxOfOrNull { it.width } ?: 0, sizes.maxOfOrNull { it.height } ?: 0)

    // ── Apply (per stack) ────────────────────────────────────────────────────

    /** GAM multi-size — this is what delivers fallback fill on BOTH / GAM_ONLY. */
    fun applyGam(sizes: List<Size>, adView: AdManagerAdView) {
        if (sizes.isEmpty()) return
        adView.setAdSizes(*sizes.map { GmaAdSize(it.width, it.height) }.toTypedArray())
    }

    /**
     * Attach additional sizes to a transactional Prebid [BannerAdUnit] (the BOTH
     * bid). Primary is set at construction; this adds the rest.
     *
     * NOTE (verify on build): `addAdditionalSize(w, h)` is the Prebid Mobile
     * multi-size API; confirm it resolves in the shaded fork.
     */
    fun applyPrebid(sizes: List<Size>, unit: BannerAdUnit) {
        sizes.drop(1).forEach { unit.addAdditionalSize(it.width, it.height) }
    }

    /**
     * Attach additional sizes to the rendering [PrebidBannerView] (PREBID_ONLY).
     *
     * NOTE (verify on build): the rendering BannerView multi-size API is
     * fork-dependent; confirm `addAdditionalSize` (or the fork equivalent).
     */
    fun applyRendering(sizes: List<Size>, banner: PrebidBannerView) {
        val extras = sizes.drop(1).map { PrebidAdSize(it.width, it.height) }
        if (extras.isNotEmpty()) banner.addAdditionalSizes(*extras.toTypedArray())
    }

    // ── Parsing (pure) ────────────────────────────────────────────────────────

    // One element per entry, null when it does not parse. '' (the CMS's unset value)
    // and a missing value have no entries; a value of another type is one bad entry.
    // With the entries comes the JSONException of text that looks like a list but is not
    // one; the caller reports it with config.banner_sizes.invalid.
    private fun parseList(raw: Any?): Pair<List<Size?>, JSONException?> = when (raw) {
        null, "" -> emptyList<Size?>() to null
        is JSONArray -> entries(raw) to null
        is String -> parseText(raw)
        else -> listOf<Size?>(null) to null
    }

    // Text is a JSON list or one "WxH" size. Text that looks like a list but is not one is
    // parsed as one size (dropped if it is not one), and its JSONException goes with it.
    private fun parseText(text: String): Pair<List<Size?>, JSONException?> {
        if (!text.trimStart().startsWith("[")) return listOf(parseOne(text)) to null
        return try {
            entries(JSONArray(text)) to null
        } catch (e: JSONException) {
            listOf(parseOne(text)) to e
        }
    }

    private fun entries(array: JSONArray): List<Size?> = (0 until array.length()).map { parseOne(array.opt(it)) }

    private fun parseOne(e: Any?): Size? = when (e) {
        is String -> {
            val parts = e.lowercase().split("x").mapNotNull { it.trim().toDoubleOrNull()?.toInt() }
            if (parts.size == 2) Size(parts[0], parts[1]) else null
        }
        is JSONArray -> {
            if (e.length() == 2) {
                val w = e.optDouble(0, 0.0).toInt()
                val h = e.optDouble(1, 0.0).toInt()
                if (w > 0 && h > 0) Size(w, h) else null
            } else null
        }
        else -> null
    }
}
