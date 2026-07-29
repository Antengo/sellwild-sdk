// SellwildVideo.kt — outstream (in-banner) video support.
//
// Video is OFF by default and toggled per-placement from remote config, so it
// ships dormant and is turned on/off from the CDN with no app release:
//   - Global:   VIDEO_ENABLED            (bool / "1" / "true")
//   - Per-zone: VIDEO_ENABLED_BY_ZONE    ({ "<zoneId>": true })
//
// This file isolates ALL Prebid Mobile video API. It is the single place to
// verify against the shaded fork on build — if an AdUnitFormat / Signals case
// or a VideoParameters setter differs in the fork, fix it here only.

package com.sellwild.sdk

import java.util.EnumSet
import org.json.JSONObject
import com.sellwild.prebid.Signals
import com.sellwild.prebid.VideoParameters
import com.sellwild.prebid.api.data.AdUnitFormat

internal object SellwildVideo {

    /**
     * Whether outstream video is enabled for this placement. Remote-config
     * gated; defaults to `false` (banner-only). A truthy global `VIDEO_ENABLED`
     * forces on; otherwise the per-zone map decides.
     */
    fun isEnabled(remoteJson: String?, zoneId: String?): Boolean {
        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return false
        // Global ON forces video everywhere; a falsy/absent global falls through
        // to the per-zone map (so a CMS-emitted VIDEO_ENABLED:false doesn't
        // dead-letter VIDEO_ENABLED_BY_ZONE — the AD_STACK_BY_ZONE gotcha).
        if (truthy(obj.optAny("VIDEO_ENABLED"))) return true
        if (zoneId != null) {
            obj.optJSONObject("VIDEO_ENABLED_BY_ZONE")?.let { byZone ->
                if (byZone.has(zoneId) && !byZone.isNull(zoneId)) return truthy(byZone.get(zoneId))
            }
        }
        return false
    }

    /** Format set for a multiformat banner+video ad unit. */
    fun bannerVideoFormats(): EnumSet<AdUnitFormat> =
        EnumSet.of(AdUnitFormat.BANNER, AdUnitFormat.VIDEO)

    /**
     * Outstream in-banner video parameters: mp4, VAST 2.0–4.0, autoplay with
     * sound off, OMID + MRAID (no VPAID), in-banner placement, standalone plcmt.
     *
     * NOTE (verify on build): the `Signals.*` cases below are Prebid Mobile 3.x;
     * confirm they resolve in the shaded fork.
     */
    fun outstreamParameters(): VideoParameters =
        VideoParameters(listOf("video/mp4")).apply {
            protocols = listOf(
                Signals.Protocols.VAST_2_0,
                Signals.Protocols.VAST_3_0,
                Signals.Protocols.VAST_4_0,
            )
            playbackMethod = listOf(Signals.PlaybackMethod.AutoPlaySoundOff)
            api = listOf(Signals.Api.OMID_1, Signals.Api.MRAID_3)
            // InBanner (OpenRTB 2.5 placement value 2, deprecated in 2.6 but
            // widely honored) + Standalone / no-content (OpenRTB 2.6 plcmt
            // value 4). Named constants keep parity with the iOS implementation
            // and avoid drift if the shaded fork ever remaps the ints.
            placement = Signals.Placement.InBanner
            plcmt = Signals.Plcmt.Standalone
            maxDuration = 30
            minDuration = 5
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
