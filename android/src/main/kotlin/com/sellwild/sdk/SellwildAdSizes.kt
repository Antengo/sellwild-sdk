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

import org.json.JSONArray
import org.json.JSONObject
import com.google.android.gms.ads.AdSize as GmaAdSize
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.BannerAdUnit
import com.sellwild.prebid.api.rendering.BannerView as PrebidBannerView

internal object SellwildAdSizes {

    /** A banner size in dp. */
    data class Size(val width: Int, val height: Int)

    /**
     * Ordered, de-duplicated size set for a placement: [primary] first, then any
     * remote `BANNER_SIZES` / `BANNER_SIZES_BY_ZONE` entries (per-zone overrides
     * global). Returns `[primary]` when nothing is configured.
     */
    fun resolve(remoteJson: String?, zoneId: String?, primary: Size): List<Size> {
        val out = LinkedHashSet<Size>()
        out.add(primary)

        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return out.toList()

        val raw: Any? = run {
            if (zoneId != null) {
                obj.optJSONObject("BANNER_SIZES_BY_ZONE")?.let { byZone ->
                    if (byZone.has(zoneId) && !byZone.isNull(zoneId)) return@run byZone.get(zoneId)
                }
            }
            if (obj.has("BANNER_SIZES") && !obj.isNull("BANNER_SIZES")) obj.get("BANNER_SIZES") else null
        }
        parseList(raw).forEach { if (it.width > 0 && it.height > 0) out.add(it) }
        return out.toList()
    }

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
        sizes.drop(1).forEach { banner.addAdditionalSize(it.width, it.height) }
    }

    // ── Parsing (pure) ────────────────────────────────────────────────────────

    private fun parseList(raw: Any?): List<Size> = when (raw) {
        is JSONArray -> (0 until raw.length()).mapNotNull { parseOne(raw.opt(it)) }
        is String -> {
            val arr = runCatching { JSONArray(raw) }.getOrNull()
            if (arr != null) (0 until arr.length()).mapNotNull { parseOne(arr.opt(it)) }
            else listOfNotNull(parseOne(raw))
        }
        else -> emptyList()
    }

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
