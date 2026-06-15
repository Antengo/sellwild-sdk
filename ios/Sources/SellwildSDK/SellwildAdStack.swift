import Foundation

// MARK: - SellwildAdStack
//
// Which ad SDK stack a placement runs. Toggled remotely via the CDN keys
// `AD_STACK` (global) and `AD_STACK_BY_ZONE` (per-zone) so GAM (Google Ad
// Manager / Google Ads) and Prebid can be segmented without an SDK release.
//
//  - .both       — Prebid auction fetches demand, then GAM renders (default).
//  - .gamOnly    — plain GAM request, no Prebid auction.
//  - .prebidOnly — Prebid's own rendering path; NO GAM ad request is made, so
//                  no GAM request/serving fees are incurred.

public enum SellwildAdStack: String {
    case both
    case gamOnly
    case prebidOnly

    /// Parse a CDN string into a stack. Case- and alias-tolerant. Returns nil
    /// for unknown values so callers fall back to their default.
    public static func parse(_ raw: Any?) -> SellwildAdStack? {
        guard let s = raw as? String else { return nil }
        let k = s.lowercased().filter { !" _-".contains($0) }
        switch k {
        case "both", "all", "default":
            return .both
        case "gam", "gamonly", "google", "gads", "googleads":
            return .gamOnly
        case "prebid", "prebidonly", "prebidsdk":
            return .prebidOnly
        default:
            return nil
        }
    }

    /// Resolve the effective stack for a placement.
    ///
    /// Precedence (matches all platforms):
    ///   1. `override` (code-level, e.g. set on `SellwildAdView` for QA).
    ///   2. Global `AD_STACK` — hard-wins for every placement.
    ///   3. Per-zone `AD_STACK_BY_ZONE[zoneId]`.
    ///   4. `.both` (today's default behavior).
    public static func resolve(
        remoteValues: [String: Any]?,
        zoneId: String?,
        override: SellwildAdStack? = nil
    ) -> SellwildAdStack {
        if let override { return override }
        if let global = parse(remoteValues?["AD_STACK"]) { return global }
        if let zoneId,
           let byZone = remoteValues?["AD_STACK_BY_ZONE"] as? [String: Any],
           let perZone = parse(byZone[zoneId]) {
            return perZone
        }
        return .both
    }
}
