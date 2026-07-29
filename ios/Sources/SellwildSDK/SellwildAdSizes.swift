// SellwildAdSizes.swift — multi-size banner support.
//
// A placement can request more than one banner size in a single auction/imp so
// demand falls back to a smaller size when the primary doesn't fill (e.g. no
// 300x250 → take 320x50). Sizes are remote-config driven, per-zone, so they're
// tuned from the CDN with no app release:
//   - Global:   BANNER_SIZES           (["300x250","320x50"] or [[300,250],[320,50]])
//   - Per-zone: BANNER_SIZES_BY_ZONE   ({ "<zoneId>": ["300x250","320x50"] })
//
// The primary size (the `AdSize` the host passes to SellwildAdView) is always
// included and always first; remote entries are additional. Applied to all
// three stacks (.both / .gamOnly / .prebidOnly).
//
// PARSING is pure and verifiable here. The per-stack APPLY helpers touch the
// GAM SDK (solid) and the shaded Prebid fork (verify-on-build) — this is the
// single place to confirm the fork's multi-size API, mirroring SellwildVideo /
// SellwildNative.

import Foundation
import GoogleMobileAds
import SellwildPrebidSDK

enum SellwildAdSizes {

    /// Ordered, de-duplicated size set for a placement: `primary` first, then any
    /// remote `BANNER_SIZES` / `BANNER_SIZES_BY_ZONE` entries (per-zone overrides
    /// global). Returns `[primary]` when nothing is configured.
    static func resolve(remoteValues: [String: Any]?, zoneId: String?, primary: CGSize) -> [CGSize] {
        var seen = Set<String>()
        var out: [CGSize] = []
        func add(_ s: CGSize) {
            guard s.width > 0, s.height > 0 else { return }
            let key = "\(Int(s.width))x\(Int(s.height))"
            if seen.insert(key).inserted { out.append(s) }
        }
        add(primary)

        let raw: Any?
        if let zoneId,
           let byZone = remoteValues?["BANNER_SIZES_BY_ZONE"] as? [String: Any],
           let perZone = byZone[zoneId] {
            raw = perZone
        } else {
            raw = remoteValues?["BANNER_SIZES"]
        }
        parseList(raw).forEach(add)
        return out
    }

    /// The smallest box that contains every size in the set — `max(width) ×
    /// max(height)`. Used to reserve a slot that fits the widest/tallest
    /// creative the auction may return, so a fallback never clips (including on
    /// the prebidOnly path, where the winning creative size isn't surfaced).
    static func boundingSize(_ sizes: [CGSize]) -> CGSize {
        CGSize(
            width: sizes.map { $0.width }.max() ?? 0,
            height: sizes.map { $0.height }.max() ?? 0
        )
    }

    // MARK: Apply (per stack)

    /// GAM multi-size: primary `adSize` + `validAdSizes` for the rest. Solid GMA
    /// API — this is what delivers fallback fill on the .both / .gamOnly paths.
    static func applyGAM(_ sizes: [CGSize], to banner: AdManagerBannerView) {
        guard let primary = sizes.first else { return }
        banner.adSize = adSizeFor(cgSize: primary)
        guard sizes.count > 1 else { return }
        // NOTE (verify on build): `NSValueFromGADAdSize` is the GMA multi-size
        // helper; confirm the spelling in the pinned GoogleMobileAds version.
        banner.validAdSizes = sizes.map { NSValueFromGADAdSize(adSizeFor(cgSize: $0)) }
    }

    /// Attach additional sizes to a transactional Prebid `BannerAdUnit` (the
    /// .both bid). Primary is set at construction; this adds the rest.
    ///
    /// NOTE (verify on build): `addAdditionalSize(width:height:)` is the Prebid
    /// Mobile multi-size API. If the shaded fork does not expose it on iOS,
    /// remove this call — GAM `validAdSizes` above still covers .both fallback.
    static func applyPrebid(_ sizes: [CGSize], to unit: BannerAdUnit) {
        for s in sizes.dropFirst() {
            unit.addAdditionalSize(width: Int(s.width), height: Int(s.height))
        }
    }

    /// Attach additional sizes to the rendering `BannerView` (.prebidOnly).
    ///
    /// NOTE (verify on build): the rendering BannerView multi-size API is
    /// fork-dependent; confirm `addAdditionalSize` (or the fork equivalent).
    static func applyRendering(_ sizes: [CGSize], to banner: SellwildPrebidSDK.BannerView) {
        for s in sizes.dropFirst() {
            banner.addAdditionalSize(width: Int(s.width), height: Int(s.height))
        }
    }

    // MARK: Parsing (pure)

    private static func parseList(_ raw: Any?) -> [CGSize] {
        switch raw {
        case let arr as [Any]:
            return arr.compactMap(parseOne)
        case let s as String:
            // A JSON string (["300x250", ...]) or a single "300x250".
            if let data = s.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return arr.compactMap(parseOne)
            }
            return [parseOne(s)].compactMap { $0 }
        default:
            return []
        }
    }

    private static func parseOne(_ e: Any) -> CGSize? {
        if let s = e as? String {
            let parts = s.lowercased().split(separator: "x").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else { return nil }
            return CGSize(width: parts[0], height: parts[1])
        }
        if let pair = e as? [Any], pair.count == 2 {
            let nums = pair.compactMap { v -> Double? in
                if let d = v as? Double { return d }
                if let i = v as? Int { return Double(i) }
                if let n = v as? NSNumber { return n.doubleValue }
                if let str = v as? String { return Double(str) }
                return nil
            }
            guard nums.count == 2 else { return nil }
            return CGSize(width: nums[0], height: nums[1])
        }
        return nil
    }
}
