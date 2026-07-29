// SellwildNative.swift — Prebid native ad-format support.
//
// Native is OFF by default and toggled per-placement from remote config, so it
// ships dormant and is turned on/off from the CDN with no app release:
//   - Global:   NATIVE_ENABLED            (bool / "1" / "true")
//   - Per-zone: NATIVE_ENABLED_BY_ZONE    ({ "<zoneId>": true })
//
// Unlike outstream video (which rides the same rendering BannerView and auto-
// renders), native returns raw ASSETS — title, body, icon, main image, CTA,
// sponsoredBy — that we must lay out ourselves and register for impression /
// click tracking. That rendering lives in `SellwildNativeAdView`; this file
// isolates ALL fork native *request* API (asset/config construction), the
// single place to verify against the shaded fork on build.
//
// Scope: native rendering is wired into the `.prebidOnly` stack only — Prebid
// fetches demand and we render the assets, no GAM. A GAM-rendered native
// variant (`.both`) needs GAM native line items + a GADNativeAd renderer and
// is a separate ad-ops effort; when NATIVE_ENABLED resolves on a non-prebidOnly
// stack the view falls through to a normal banner.

import Foundation
import SellwildPrebidSDK

public enum SellwildNative {

    /// Whether native is enabled for this placement. Remote-config gated;
    /// defaults to `false`. A truthy global `NATIVE_ENABLED` forces on;
    /// otherwise the per-zone map decides. Mirrors `SellwildVideo.isEnabled`.
    static func isEnabled(remoteValues: [String: Any]?, zoneId: String?) -> Bool {
        if truthy(remoteValues?["NATIVE_ENABLED"]) { return true }
        if let zoneId,
           let byZone = remoteValues?["NATIVE_ENABLED_BY_ZONE"] as? [String: Any],
           let perZone = byZone[zoneId] {
            return truthy(perZone)
        }
        return false
    }

    /// Hard cap on the rendered native height (points). Remote-config gated with
    /// the same precedence as the enable toggle — global `NATIVE_MAX_HEIGHT`,
    /// then `NATIVE_MAX_HEIGHT_BY_ZONE[zoneId]` — falling back to `fallback`
    /// (the host slot height) when unset, so the view is always bounded.
    /// Native has no protocol max-height, so this is the render-side backstop
    /// for bidders that return taller media than requested.
    static func maxHeight(remoteValues: [String: Any]?, zoneId: String?, fallback: CGFloat) -> CGFloat {
        if let zoneId,
           let byZone = remoteValues?["NATIVE_MAX_HEIGHT_BY_ZONE"] as? [String: Any],
           let perZone = numeric(byZone[zoneId]) {
            return perZone
        }
        if let global = numeric(remoteValues?["NATIVE_MAX_HEIGHT"]) { return global }
        return fallback
    }

    /// Standard native template asset set: title, icon, main image, plus data
    /// assets for sponsoredBy / body / CTA. This is the request contract the
    /// server-side stored request must satisfy.
    ///
    /// NOTE (verify on build): the class name (`NativeRequest`), asset classes
    /// (`NativeAssetTitle` / `NativeAssetImage` / `NativeAssetData`), the image
    /// `.type` enum (`ImageAsset.Main` / `.Icon`) and data `type:` enum
    /// (`DataAsset.sponsored` / `.description` / `.ctatext`), and the context
    /// enums below are Prebid Mobile 3.x; confirm they resolve in the shaded
    /// `SellwildPrebidSDK` fork. If the fork exposes `NativeAdUnit` instead of
    /// `NativeRequest`, swap the constructor here only.
    static func makeRequest(configId: String) -> NativeRequest {
        let title = NativeAssetTitle(length: 90, required: true)

        let icon = NativeAssetImage(minimumWidth: 20, minimumHeight: 20, required: false)
        icon.type = ImageAsset.Icon

        // Landscape ~1.91:1 main image (the standard native main-image ratio) so
        // returned media has a predictable height and the render cap rarely has
        // to clip. Bidders treat this as a target — not a guarantee — hence the
        // maxHeight backstop at render time.
        let image = NativeAssetImage(minimumWidth: 300, minimumHeight: 157, required: false)
        image.type = ImageAsset.Main

        let sponsored = NativeAssetData(type: DataAsset.sponsored, required: false)
        let body = NativeAssetData(type: DataAsset.description, required: false)
        let cta = NativeAssetData(type: DataAsset.ctatext, required: false)

        let request = NativeRequest(
            configId: configId,
            assets: [title, icon, image, sponsored, body, cta]
        )
        request.context = ContextType.Content
        request.placementType = PlacementType.FeedContent
        request.contextSubType = ContextSubType.General

        let tracker = NativeEventTracker(
            event: EventType.Impression,
            methods: [EventTracking.Image, EventTracking.js]
        )
        request.eventtrackers = [tracker]

        return request
    }

    private static func truthy(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "yes", "on"].contains(s.lowercased())
        default: return false
        }
    }

    /// Coerce a remote value to a positive CGFloat (accepts numbers or numeric
    /// strings); returns nil for anything non-positive or unparseable.
    private static func numeric(_ value: Any?) -> CGFloat? {
        let n: CGFloat?
        switch value {
        case let d as Double: n = CGFloat(d)
        case let i as Int: n = CGFloat(i)
        case let num as NSNumber: n = CGFloat(truncating: num)
        case let s as String: n = Double(s).map { CGFloat($0) }
        default: n = nil
        }
        guard let n, n > 0 else { return nil }
        return n
    }
}
