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
        unit.addAsset(NativeImageAsset(200, 200, 200, 200).apply {
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
            dataType = NativeDataAsset.DATA_TYPE.CTA_TEXT
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

    private fun truthy(v: Any?): Boolean = when (v) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        is String -> v.lowercase() in setOf("1", "true", "yes", "on")
        else -> false
    }

    private fun JSONObject.optAny(key: String): Any? =
        if (has(key) && !isNull(key)) get(key) else null
}
