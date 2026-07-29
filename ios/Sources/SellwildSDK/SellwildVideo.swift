// SellwildVideo.swift — outstream (in-banner) video support.
//
// Video is OFF by default and toggled per-placement from remote config, so it
// ships dormant and is turned on/off from the CDN with no app release:
//   - Global:   VIDEO_ENABLED            (bool / "1" / "true")
//   - Per-zone: VIDEO_ENABLED_BY_ZONE    ({ "<zoneId>": true })
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
        return params
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
