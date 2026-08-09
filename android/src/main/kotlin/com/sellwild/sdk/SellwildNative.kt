// SellwildNative.kt — Prebid native ad-format support.
//
// Native is OFF by default and toggled per-placement from remote config, so it
// ships dormant and is turned on/off from the CDN with no app release:
//   - Global:   NATIVE_ENABLED            (bool / "1" / "true")
//   - Per-zone: NATIVE_ENABLED_BY_ZONE    ({ "<zoneId>": true })
//
// Unlike outstream video (which rides the same rendering BannerView and auto-
// renders), native returns raw ASSETS — title, body, icon, main image, CTA,
// sponsoredBy — that we lay out ourselves and register for impression / click
// tracking. Rendering lives in SellwildNativeAdView; this file isolates ALL
// fork native *request* API (the NativeAdUnit + asset construction), the single
// place to verify against the shaded fork on build.
//
// Scope: native is wired into the PREBID_ONLY stack only — Prebid fetches
// demand and we render the assets, no GAM. A GAM-rendered native variant needs
// GAM native line items + a GADNativeAd renderer (ad-ops); on a non-prebidOnly
// stack the view falls through to a normal banner.

package com.sellwild.sdk

import org.json.JSONObject
import com.sellwild.prebid.NativeAdUnit
import com.sellwild.prebid.NativeTitleAsset
import com.sellwild.prebid.NativeImageAsset
import com.sellwild.prebid.NativeDataAsset
import com.sellwild.prebid.NativeEventTracker

internal object SellwildNative {

    /**
     * Whether native is enabled for this placement. Remote-config gated;
     * defaults to `false`. A truthy global `NATIVE_ENABLED` forces on; otherwise
     * the per-zone map decides. Mirrors [SellwildVideo.isEnabled].
     */
    fun isEnabled(remoteJson: String?, zoneId: String?): Boolean {
        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return false
        if (truthy(obj.optAny("NATIVE_ENABLED"))) return true
        if (zoneId != null) {
            obj.optJSONObject("NATIVE_ENABLED_BY_ZONE")?.let { byZone ->
                if (byZone.has(zoneId) && !byZone.isNull(zoneId)) return truthy(byZone.get(zoneId))
            }
        }
        return false
    }

    /**
     * Hard cap on the rendered native height (dp). Same precedence as the enable
     * toggle — global `NATIVE_MAX_HEIGHT`, then `NATIVE_MAX_HEIGHT_BY_ZONE[zoneId]`
     * — falling back to [fallback] (the host slot height) when unset, so the view
     * is always bounded. Native has no protocol max-height, so this is the
     * render-side backstop for bidders that return taller media than requested.
     */
    fun maxHeight(remoteJson: String?, zoneId: String?, fallback: Int): Int {
        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return fallback
        if (zoneId != null) {
            obj.optJSONObject("NATIVE_MAX_HEIGHT_BY_ZONE")?.let { byZone ->
                if (byZone.has(zoneId) && !byZone.isNull(zoneId)) numeric(byZone.get(zoneId))?.let { return it }
            }
        }
        numeric(obj.optAny("NATIVE_MAX_HEIGHT"))?.let { return it }
        return fallback
    }

    /**
     * Standard native template ad unit: title, icon, main image, plus data
     * assets for sponsoredBy / body / CTA. This is the request contract the
     * server-side stored request must satisfy.
     *
     * NOTE (verify on build): the asset classes (`NativeTitleAsset`,
     * `NativeImageAsset`, `NativeDataAsset`, `NativeEventTracker`), the image
     * type enum (`NativeImageAsset.IMAGE_TYPE.MAIN` / `.ICON`), the data type
     * enum (`NativeDataAsset.DATA_TYPE.SPONSORED` / `.DESC` / `.CTA_TEXT`), and
     * the context enums on `NativeAdUnit` are Prebid Mobile 3.x. Confirm they
     * resolve in the shaded `com.sellwild.prebid` fork; fix names here only.
     */
    fun makeRequest(configId: String): NativeAdUnit {
        val unit = NativeAdUnit(configId)
        unit.setContextType(NativeAdUnit.CONTEXT_TYPE.CONTENT_CENTRIC)
        unit.setPlacementType(NativeAdUnit.PLACEMENTTYPE.CONTENT_FEED)
        unit.setContextSubType(NativeAdUnit.CONTEXTSUBTYPE.GENERAL)

        unit.addAsset(NativeTitleAsset().apply {
            setLength(90)
            isRequired = true
        })
        unit.addAsset(NativeImageAsset(20, 20, 20, 20).apply {
            imageType = NativeImageAsset.IMAGE_TYPE.ICON
            isRequired = false
        })
        // Landscape ~1.91:1 main image (the standard native main-image ratio) so
        // returned media has a predictable height and the render cap rarely has
        // to clip. Bidders treat this as a target, not a guarantee — hence the
        // maxHeight backstop at render time.
        unit.addAsset(NativeImageAsset(300, 157, 300, 157).apply {
            imageType = NativeImageAsset.IMAGE_TYPE.MAIN
            isRequired = false
        })
        unit.addAsset(NativeDataAsset().apply {
            setLen(25)
            dataType = NativeDataAsset.DATA_TYPE.SPONSORED
            isRequired = false
        })
        unit.addAsset(NativeDataAsset().apply {
            setLen(140)
            dataType = NativeDataAsset.DATA_TYPE.DESC
            isRequired = false
        })
        unit.addAsset(NativeDataAsset().apply {
            setLen(25)
            dataType = NativeDataAsset.DATA_TYPE.CTATEXT
            isRequired = false
        })

        val methods = arrayListOf(
            NativeEventTracker.EVENT_TRACKING_METHOD.IMAGE,
            NativeEventTracker.EVENT_TRACKING_METHOD.JS,
        )
        unit.addEventTracker(
            NativeEventTracker(NativeEventTracker.EVENT_TYPE.IMPRESSION, methods)
        )

        return unit
    }

    /**
     * Resolve the Prebid `configId` for the native request.
     *
     * Some partners issue a dedicated native placement id, distinct from the
     * banner/video id. Mirrors the mobile zone precedence (per-placement
     * per-platform -> platform-wide -> shared) for the native keys, then falls
     * back to [zoneId] — itself the already-resolved mobile zone
     * (MOBILE_ZID_ANDROID -> MOBILE_ZID_ALL_ANDROID -> MOBILE_ZID). Full chain:
     *   NATIVE_ZID_ANDROID -> NATIVE_ZID_ALL_ANDROID -> NATIVE_ZID -> <mobile zoneId>.
     */
    fun resolveConfigId(remoteJson: String?, zoneId: String): String {
        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return zoneId
        return firstNonEmpty(obj.optAny("NATIVE_ZID_ANDROID"))
            ?: firstNonEmpty(obj.optAny("NATIVE_ZID_ALL_ANDROID"))
            ?: firstNonEmpty(obj.optAny("NATIVE_ZID"))
            ?: zoneId
    }

    /** A single non-empty id from a value that may be a String or JSONArray of strings. */
    private fun firstNonEmpty(v: Any?): String? = when (v) {
        is String -> v.takeIf { it.isNotEmpty() }
        is org.json.JSONArray -> (0 until v.length()).asSequence()
            .map { v.optString(it) }.firstOrNull { it.isNotEmpty() }
        else -> null
    }

    private fun truthy(v: Any?): Boolean = when (v) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        is String -> v.lowercase() in setOf("1", "true", "yes", "on")
        else -> false
    }

    /** Coerce a remote value to a positive Int (numbers or numeric strings). */
    private fun numeric(v: Any?): Int? = when (v) {
        is Number -> v.toInt()
        is String -> v.trim().toDoubleOrNull()?.toInt()
        else -> null
    }?.takeIf { it > 0 }

    private fun JSONObject.optAny(key: String): Any? =
        if (has(key) && !isNull(key)) get(key) else null
}
