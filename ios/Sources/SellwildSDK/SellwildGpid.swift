import Foundation

// MARK: - SellwildGpid
//
// Client-side GPID (Global Placement ID) for the Prebid impression. The SAME
// string is written to BOTH `imp.ext.gpid` and `imp.ext.data.pbadslot` on every
// auction, per placement — gpid identifies the placement to DSPs; pbadslot
// carries the same value as Prebid's ad-slot signal. They are always
// constructed together, from a single builder, so they can never drift apart.
//
// The base string is authored in remote CMS config per zone (like AD_STACK):
//   - Per-zone `GPID_BASE_BY_ZONE[zoneId]` wins when present.
//   - Otherwise the top-level string `GPID_BASE`.
//   - Neither present → nil, and the SDK sets NO gpid/pbadslot at all.
//
// The emitted VALUE is `base` normally, or `base#n` (1-based) when the same base
// is used by more than one ad slot on one feed screen — see SellwildFeedView,
// which disambiguates with `disambiguate(_:)`. A standalone `SellwildAdView`
// always emits the bare base (a single placement can't collide with itself).

public enum SellwildGpid {

    /// Resolve the GPID base for a placement from remote config.
    ///
    /// Precedence (mirrors `SellwildAdStack.resolve`):
    ///   1. Per-zone `GPID_BASE_BY_ZONE[zoneId]`.
    ///   2. Global `GPID_BASE`.
    ///   3. `nil` — no base configured, so the SDK sends no gpid/pbadslot.
    ///
    /// Accepts either a JSON string or a JSON number for the base value.
    public static func resolveBase(
        remoteValues: [String: Any]?,
        zoneId: String?
    ) -> String? {
        if let zoneId,
           let byZone = remoteValues?["GPID_BASE_BY_ZONE"] as? [String: Any],
           let base = baseString(byZone[zoneId]) {
            return base
        }
        return baseString(remoteValues?["GPID_BASE"])
    }

    /// Build the `imp.ext` JSON string shared by BOTH ad-stack paths (the
    /// `.both` Prebid-then-GAM auction and the `.prebidOnly` rendering banner),
    /// so gpid + pbadslot are constructed at exactly one point.
    ///
    /// Shape:
    /// ```
    /// { "ext": { "gpid": "<v>", "data": { "pbadslot": "<v>" },
    ///            "prebid": { "bidder": { ...bidderParams... } } } }
    /// ```
    /// `ext.gpid` + `ext.data.pbadslot` are emitted only when `gpid` is non-empty;
    /// `ext.prebid.bidder` only when `bidderParams` is non-empty. Bidder names are
    /// lowercased (imp.ext expects lowercase; the CDN ships CONSTANT_CASE). Built
    /// via `JSONSerialization` (never string interpolation) so a base string with
    /// quotes/backslashes can't break the JSON. Returns nil when there is nothing
    /// to emit or the object can't be serialized.
    public static func impExtJSON(
        gpid: String?,
        bidderParams: [String: Any] = [:]
    ) -> String? {
        var ext: [String: Any] = [:]
        if let gpid, !gpid.isEmpty {
            ext["gpid"] = gpid
            ext["data"] = ["pbadslot": gpid]
        }
        if !bidderParams.isEmpty {
            var bidders: [String: Any] = [:]
            for (k, v) in bidderParams {
                bidders[k.lowercased()] = v
            }
            ext["prebid"] = ["bidder": bidders]
        }
        guard !ext.isEmpty else { return nil }
        let imp: [String: Any] = ["ext": ext]
        guard JSONSerialization.isValidJSONObject(imp),
              let data = try? JSONSerialization.data(withJSONObject: imp),
              let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    /// Disambiguate a list of GPID bases in row order: a base used exactly once
    /// stays bare; a base used by k>1 slots becomes `base#1`, `base#2`, … in the
    /// order given. `nil` entries (no base for that slot) stay nil. Used by
    /// `SellwildFeedView` so two ad slots that share a base on one screen still
    /// produce a unique gpid/pbadslot per placement.
    public static func disambiguate(_ bases: [String?]) -> [String?] {
        var counts: [String: Int] = [:]
        for case let base? in bases { counts[base, default: 0] += 1 }
        var seen: [String: Int] = [:]
        return bases.map { base in
            guard let base else { return nil }
            if counts[base] == 1 { return base }
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            return "\(base)#\(n)"
        }
    }

    /// Coerce a remote value into a non-empty base string, accepting either a
    /// JSON string or a JSON number. Returns nil for absent / empty / other.
    private static func baseString(_ raw: Any?) -> String? {
        switch raw {
        case let s as String where !s.trimmingCharacters(in: .whitespaces).isEmpty:
            return s
        case let n as NSNumber:
            return n.stringValue
        default:
            return nil
        }
    }
}
