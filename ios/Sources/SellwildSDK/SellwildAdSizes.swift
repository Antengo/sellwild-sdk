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
    /// global). Returns `[primary]` when nothing is configured. Remote entries
    /// that do not parse, are not positive or do not fit an Int are dropped
    /// and reported (`config.banner_sizes.invalid`). The ad view resolves its
    /// sizes several times per load, so the same drop is reported once per
    /// launch per zone.
    static func resolve(remoteValues: [String: Any]?, zoneId: String?, primary: CGSize) -> [CGSize] {
        var seen = Set<String>()
        var out: [CGSize] = []
        func add(_ s: CGSize) {
            // fitsAnInt: positive, and `Int(_:)` below cannot trap.
            guard fitsAnInt(s.width), fitsAnInt(s.height) else { return }
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
        let parsed = parseSizes(raw)
        parsed.sizes.forEach(add)
        let message = "\(parsed.dropped) banner size entr\(parsed.dropped == 1 ? "y was" : "ies were") dropped"
        if parsed.dropped > 0, SellwildReportOnce.first(.configBannerSizesInvalid, "\(zoneId ?? "")|\(message)") {
            SellwildFailures.log(code: .configBannerSizesInvalid, component: .remoteConfig, severity: .warn,
                                 message: message, zoneId: zoneId)
        }
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
        // GMA 12.x renamed `NSValueFromGADAdSize(_:)` to `nsValue(for:)`.
        banner.validAdSizes = sizes.map { nsValue(for: adSizeFor(cgSize: $0)) }
    }

    /// Attach additional sizes to a transactional Prebid `BannerAdUnit` (the
    /// .both bid). Primary is set at construction; this adds the rest.
    ///
    /// Shaded fork exposes `addAdditionalSize(sizes: [CGSize])` on
    /// `BannerAdUnit` (Prebid Mobile 3.x).
    static func applyPrebid(_ sizes: [CGSize], to unit: BannerAdUnit) {
        let extras = Array(sizes.dropFirst())
        guard !extras.isEmpty else { return }
        unit.addAdditionalSize(sizes: extras)
    }

    /// Attach additional sizes to the rendering `BannerView` (.prebidOnly).
    ///
    /// The shaded rendering `BannerView` exposes `additionalSizes: [CGSize]?`
    /// as a settable property (see BannerView.swift). Primary is set at
    /// construction via `adSize:`; this appends the rest.
    static func applyRendering(_ sizes: [CGSize], to banner: SellwildPrebidSDK.BannerView) {
        let extras = Array(sizes.dropFirst())
        guard !extras.isEmpty else { return }
        banner.additionalSizes = extras
    }

    // MARK: Parsing (pure)

    /// The positive sizes in a remote size list, in order, and how many
    /// entries were dropped because they do not parse, are not positive, or
    /// are too large for an Int (the key `resolve` de-duplicates by; the
    /// schema allows any run of digits, and "inf" is Double text).
    /// Accepts a list, a JSON text of a list, or one "WxH" text. Absent, JSON
    /// null and blank text ('' is the CMS's "unset") are an empty list, not a
    /// drop. One "WxH" text is parsed as sent: each part is trimmed of spaces
    /// only, so "300x250\n" is dropped, as it always was (drift/ios.json
    /// `other`; Android trims line breaks too).
    static func parseSizes(_ raw: Any?) -> (sizes: [CGSize], dropped: Int) {
        let entries: [Any]
        switch raw {
        case nil, is NSNull:
            return ([], 0)
        case let arr as [Any]:
            entries = arr
        case let s as String:
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ([], 0) }
            entries = jsonList(s) ?? [s]
        default:
            return ([], 1)
        }
        let sizes = entries.compactMap(parseOne).filter { fitsAnInt($0.width) && fitsAnInt($0.height) }
        return (sizes, entries.count - sizes.count)
    }

    /// Positive, finite and below 2^63, so `Int(_:)` cannot trap on it.
    private static func fitsAnInt(_ dimension: CGFloat) -> Bool {
        dimension > 0 && dimension.isFinite && Double(dimension) < Double(Int.max)
    }

    /// `text` as a JSON list (["300x250", ...]), or nil when it is not one.
    /// nil is not a failure here: one "WxH" text is not JSON, and text that
    /// is neither is dropped as an entry that does not parse.
    private static func jsonList(_ text: String) -> [Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any]
    }

    private static func parseOne(_ e: Any) -> CGSize? {
        if let s = e as? String {
            let parts = s.lowercased().split(separator: "x").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else { return nil }
            return CGSize(width: parts[0], height: parts[1])
        }
        if let pair = e as? [Any], pair.count == 2 {
            // A JSON number is an NSNumber: `as? Double` reads it unless it is an
            // integer a Double cannot hold exactly, then `as? Int`, and one too
            // large for an Int is read through NSNumber.
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
