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

    /// Outstream in-banner video parameters: mp4, VAST 2.0–4.2, CLICK-TO-PLAY
    /// (user-initiated — we never autoplay), OMID + MRAID (no VPAID), in-banner
    /// placement, standalone (no-content) plcmt.
    ///
    /// Playback is click-to-play by policy: autoplay (even sound-off) is the
    /// source of the audio breakthrough and non-compliant creatives ignore the
    /// sound-off hint, so video starts only on a user tap. The server-side
    /// banner-video-reject hook enforces the same rule (rejects any video imp
    /// whose playbackmethod isn't click-to-play).
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
        params.playbackMethod = [Signals.PlaybackMethod.ClickToPlay]
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
    /// ON) in the fork, so the mute write is defense-in-depth. The request-side
    /// `playbackMethod = ClickToPlay` is the primary control (video starts only on
    /// a user tap); the mute write keeps any stray playback silent regardless.
    ///
    /// NOTE (verify on build): these `AdConfiguration` members are Prebid Mobile
    /// 3.x; confirm they resolve in the shaded `SellwildPrebidSDK` fork.
    static func enableOutstream(on bannerView: PrebidBannerView, remoteValues: [String: Any]?, zoneId: String?) {
        let cfg = bannerView.adUnitConfig
        cfg.adFormats = [.banner, .video]
        cfg.adConfiguration.videoParameters = outstreamParameters()
        cfg.adConfiguration.videoControlsConfig.isMuted = !soundEnabled(remoteValues: remoteValues, zoneId: zoneId)
    }

    /// Force video autoplay muted on a rendering `BannerView` even when this
    /// zone never requested video (`isEnabled` is `false`, so `enableOutstream`
    /// never runs and `videoControlsConfig.isMuted` is never written).
    ///
    /// Defensive mitigation: `videoControlsConfig.isMuted` defaults to `false`
    /// (sound ON) in the fork — see `enableOutstream`'s doc comment — so a
    /// banner-only imp that unexpectedly wins a video/VAST creative (a bidder or
    /// stored-imp config ignoring the requested `imp.video` absence) would
    /// autoplay with sound by the fork's own default, with nothing in this SDK
    /// having ever touched the mute config for that placement. Call this on
    /// every rendering `BannerView` that does NOT call `enableOutstream`, so
    /// the mute config is written either way.
    static func forceDefaultMute(on bannerView: PrebidBannerView) {
        bannerView.adUnitConfig.adConfiguration.videoControlsConfig.isMuted = true
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
