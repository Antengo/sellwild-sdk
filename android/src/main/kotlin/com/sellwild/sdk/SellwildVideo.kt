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

import com.sellwild.sdk.core.RemoteValues
import java.util.EnumSet
import com.sellwild.prebid.Signals
import com.sellwild.prebid.VideoParameters
import com.sellwild.prebid.api.data.AdUnitFormat

internal object SellwildVideo {

    /**
     * Whether outstream video is enabled for this placement. Remote-config
     * gated; defaults to `false` (banner-only). A truthy global `VIDEO_ENABLED`
     * forces on; otherwise the per-zone map decides.
     */
    fun isEnabled(remoteJson: String?, zoneId: String?): Boolean =
        flag(remoteJson, zoneId, "VIDEO_ENABLED", "VIDEO_ENABLED_BY_ZONE")

    /** Format set for a multiformat banner+video ad unit. */
    fun bannerVideoFormats(): EnumSet<AdUnitFormat> =
        EnumSet.of(AdUnitFormat.BANNER, AdUnitFormat.VIDEO)

    /**
     * Whether outstream audio is enabled (unmuted) for this placement.
     * Remote-config gated; defaults to `false` (muted autoplay — the in-feed
     * standard, matches iOS) when unset. A truthy global `VIDEO_SOUND_ENABLED`
     * forces sound on; otherwise the per-zone map decides. Mirrors `isEnabled`.
     *
     * Unlike iOS, the shaded fork's rendering `BannerView`/`AdUnitConfiguration`
     * exposes no client-side mute knob (no `VideoControlsConfiguration`
     * equivalent) — this value is consumed by [SellwildAdView]'s direct
     * `VideoView.mute()` enforcement instead of a request-side config write.
     */
    fun soundEnabled(remoteJson: String?, zoneId: String?): Boolean =
        flag(remoteJson, zoneId, "VIDEO_SOUND_ENABLED", "VIDEO_SOUND_ENABLED_BY_ZONE")

    // Global ON forces the flag everywhere; a falsy/absent global falls through to the
    // per-zone map (so a CMS-emitted VIDEO_ENABLED:false doesn't dead-letter
    // VIDEO_ENABLED_BY_ZONE — the AD_STACK_BY_ZONE gotcha).
    private fun flag(remoteJson: String?, zoneId: String?, key: String, byZoneKey: String): Boolean {
        val obj = remoteObject(remoteJson) ?: return false
        if (RemoteValues.isOn(RemoteValues.optAny(obj, key))) return true
        return RemoteValues.isOn(RemoteValues.byZone(obj, byZoneKey, zoneId))
    }

    /**
     * Outstream in-banner video parameters: mp4, VAST 2.0–4.0, CLICK-TO-PLAY
     * (user-initiated — we never autoplay), OMID + MRAID (no VPAID), in-banner
     * placement, standalone plcmt.
     *
     * Playback is click-to-play by policy: autoplay (even sound-off) is the source
     * of the audio breakthrough and non-compliant creatives ignore the sound-off
     * hint, so video starts only on a user tap. The server-side banner-video-reject
     * hook enforces the same rule (rejects any video imp whose playbackmethod isn't
     * click-to-play). `soundEnabled` above still gates the direct `VideoView.mute()`
     * enforcement in [SellwildAdView] as defense-in-depth for creatives that ignore
     * the click-to-play request.
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
            playbackMethod = listOf(Signals.PlaybackMethod.ClickToPlay)
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
}
