// SellwildVideo.swift — outstream (in-banner) video support.
//
// Video is OFF by default and toggled per-placement from remote config, so it
// ships dormant and is turned on/off from the CDN with no app release:
//   - Global:   VIDEO_ENABLED            (bool / "1" / "true")
//   - Per-zone: VIDEO_ENABLED_BY_ZONE    ({ "<zoneId>": true })
//
// Sound is OFF by default (muted autoplay — the in-feed standard) and opt-in
// per-placement, same shape as the enable flags:
//   - Global:   VIDEO_SOUND_ENABLED         (bool / "1" / "true")
//   - Per-zone: VIDEO_SOUND_ENABLED_BY_ZONE ({ "<zoneId>": true })
//
// This file isolates ALL Prebid Mobile video API. It is the single place to
// verify against the shaded fork on build — if a `Signals.*` case or a
// `VideoParameters` property name differs in the fork, fix it here only.
//
// Rendering is handled by whichever ad stack the placement resolves to:
//   - .both       (GAM-rendered)    → BannerAdUnit multiformat, GAM renders the
//                                      outstream creative (needs a GAM outstream
//                                      line item / renderer — ad-ops).
//   - .prebidOnly (Prebid-rendered) → BannerView renders outstream itself, no GAM.

import Foundation
import SellwildPrebidSDK

public enum SellwildVideo {

    /// Whether outstream video is enabled for this placement. Remote-config
    /// gated; defaults to `false` (banner-only) when unset or unrecognized.
    /// A truthy global `VIDEO_ENABLED` forces on; otherwise the per-zone map decides.
    static func isEnabled(remoteValues: [String: Any]?, zoneId: String?) -> Bool {
        // Global ON forces video everywhere; a falsy/absent global falls through
        // to the per-zone map (so a CMS-emitted VIDEO_ENABLED:false doesn't
        // dead-letter VIDEO_ENABLED_BY_ZONE — the AD_STACK_BY_ZONE gotcha).
        if truthy(remoteValues?["VIDEO_ENABLED"]) { return true }
        if let zoneId,
           let byZone = remoteValues?["VIDEO_ENABLED_BY_ZONE"] as? [String: Any],
           let perZone = byZone[zoneId] {
            return truthy(perZone)
        }
        return false
    }

    /// Whether outstream audio is enabled (unmuted) for this placement.
    /// Remote-config gated; defaults to `false` (muted autoplay — the in-feed
    /// standard) when unset. A truthy global `VIDEO_SOUND_ENABLED` forces sound
    /// on; otherwise the per-zone map decides. Mirrors `isEnabled`.
    static func soundEnabled(remoteValues: [String: Any]?, zoneId: String?) -> Bool {
        if truthy(remoteValues?["VIDEO_SOUND_ENABLED"]) { return true }
        if let zoneId,
           let byZone = remoteValues?["VIDEO_SOUND_ENABLED_BY_ZONE"] as? [String: Any],
           let perZone = byZone[zoneId] {
            return truthy(perZone)
        }
        return false
    }

    /// Outstream in-banner video parameters: mp4, VAST 2.0–4.2, autoplay with
    /// sound off (the in-feed standard), OMID + MRAID (no VPAID), in-banner
    /// placement, standalone (no-content) plcmt.
    ///
    /// NOTE (verify on build): the `Signals.*` enum cases and `VideoParameters`
    /// property names below are Prebid Mobile 3.x; confirm they resolve in the
    /// shaded `SellwildPrebidSDK` fork.
    static func outstreamParameters() -> VideoParameters {
        let params = VideoParameters(mimes: ["video/mp4"])
        params.protocols = [
            Signals.Protocols.VAST_2_0,
            Signals.Protocols.VAST_3_0,
            Signals.Protocols.VAST_4_0,
        ]
        params.playbackMethod = [Signals.PlaybackMethod.AutoPlaySoundOff]
        params.placement = Signals.Placement.InBanner   // deprecated in 2.6 but widely honored
        // NOTE: Prebid Mobile 3.x shaded fork doesn't expose `plcmt` (OpenRTB 2.6);
        // `placement = InBanner` covers the intent for buyers still on the 2.5 signal.
        params.api = [Signals.Api.OMID_1, Signals.Api.MRAID_3]
        // Duration bounds — parity with Android (SellwildVideo.kt). Several video
        // DSPs filter on / require maxduration; without bounds the iOS outstream
        // imp was a weaker demand signal than Android for the same zone.
        params.minDuration = 5
        params.maxDuration = 30
        return params
    }

    /// Enable outstream (in-banner) video on a `.prebidOnly` rendering
    /// `BannerView`: request banner + video in one imp and apply the outstream
    /// params, muted unless the zone opts into sound (`VIDEO_SOUND_ENABLED`).
    ///
    /// All three are **direct writes** to the fork's stored, non-optional config
    /// (`adUnitConfig.adFormats`, `adConfiguration.videoParameters`,
    /// `adConfiguration.videoControlsConfig.isMuted`) — the same path the fork's
    /// own mediation adapters use — so there's no reliance on mutating a get-only
    /// proxy in place. `videoControlsConfig.isMuted` defaults to `false` (sound
    /// ON) in the fork, so the mute write is what keeps autoplay silent (the
    /// request-side `playbackMethod = AutoPlaySoundOff` is only an advisory
    /// auction signal).
    ///
    /// NOTE (verify on build): these `AdConfiguration` members are Prebid Mobile
    /// 3.x; confirm they resolve in the shaded `SellwildPrebidSDK` fork.
    static func enableOutstream(on bannerView: PrebidBannerView, remoteValues: [String: Any]?, zoneId: String?) {
        let cfg = bannerView.adUnitConfig
        cfg.adFormats = [.banner, .video]
        cfg.adConfiguration.videoParameters = outstreamParameters()
        cfg.adConfiguration.videoControlsConfig.isMuted = !soundEnabled(remoteValues: remoteValues, zoneId: zoneId)
    }

    private static func truthy(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "yes", "on"].contains(s.lowercased())
        default: return false
        }
    }
}
