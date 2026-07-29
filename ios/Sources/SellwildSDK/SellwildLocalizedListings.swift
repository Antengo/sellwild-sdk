// SellwildLocalizedListings.swift — geo-based secondary-listings on iOS.
//
// When enabled, the feed loads a SECOND listings cache keyed by the user's
// state and disperses those listings into the primary feed at a configured
// frequency (every Nth slot). This file is the single verify point for the
// native iOS logic: config resolution, state resolution, URL templating, and
// the every-Nth de-duped merge. It performs no I/O — the feed view drives the
// fetch through `SellwildAPIClient.fetchCacheListings`.
//
// State resolution order (highest first):
//   1. integration.forceState  (remote/CMS force — a known-Alabama site, etc.)
//   2. geo state (SellwildGeoStore.current?.state — seeded from partner geo or
//      the CloudFront viewer-country-region header off the primary fetch)
//   3. none → skip the localized cache entirely
//
// The cache payload is identical to the primary feed (`result.rs` of listings),
// so `SellwildAPIClient` reuses `parseListingsResponse`; a 404 on the templated
// URL (a state we have no data for) is a normal skip.
//
// Mirrors the platform-neutral reference `core/src/localized-listings.ts`.
// Touches NO Prebid fork API.

import Foundation

public enum SellwildLocalizedListings {

    /// A fully-resolved localized-listings integration (config validated).
    struct Integration {
        /// Optional label for the source, e.g. "sportserver".
        let source: String?
        /// Cache base URL (required).
        let baseUrl: String
        /// Filename template with a `{state}` token (required).
        let urlTemplate: String
        /// Dispersion percent (25 → every 4th slot).
        let frequency: Int
        /// Forced state (2-letter upper), or nil.
        let forceState: String?
    }

    /// Resolve the active integration: local `config.localizedListings` wins
    /// entirely, else the raw remote `LOCALIZED_LISTINGS` object (which may be a
    /// `[String: Any]` or a JSON `String`). Returns nil when disabled (explicit
    /// `enabled == false`) or missing a baseUrl / urlTemplate.
    static func resolve(config: SellwildConfig) -> Integration? {
        if let local = config.localizedListings {
            if local.enabled == false { return nil } // explicit off; absent = on
            return make(
                source: local.source,
                baseUrl: local.baseUrl,
                urlTemplate: local.urlTemplate,
                frequency: local.frequency,
                forceState: local.forceState
            )
        }

        guard let raw = safeParseObject(config.remoteValues?["LOCALIZED_LISTINGS"]) else { return nil }
        if (raw["enabled"] as? Bool) == false { return nil }
        return make(
            source: nonEmpty(raw["source"]),
            baseUrl: nonEmpty(raw["baseUrl"]),
            urlTemplate: nonEmpty(raw["urlTemplate"]),
            frequency: numeric(raw["frequency"]).map { Int($0) },
            forceState: nonEmpty(raw["forceState"])
        )
    }

    private static func make(source: String?, baseUrl: String?, urlTemplate: String?,
                             frequency: Int?, forceState: String?) -> Integration? {
        guard let base = nonEmpty(baseUrl), let tmpl = nonEmpty(urlTemplate) else { return nil }
        return Integration(
            source: nonEmpty(source),
            baseUrl: base,
            urlTemplate: tmpl,
            frequency: frequency ?? 0,
            forceState: normState(forceState)
        )
    }

    /// Forced state wins, then the resolved geo state, else nil.
    static func resolveState(_ integration: Integration, geoState: String?) -> String? {
        return integration.forceState ?? normState(geoState)
    }

    /// Normalize to a 2-letter uppercase state/region code, or nil. A
    /// CloudFront viewer-country-region can be "GA" or a longer subdivision;
    /// take the trailing 2-letter token when present, else the raw upper value.
    static func normState(_ value: Any?) -> String? {
        guard let str = value as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let code = trimmed.uppercased()
        if code.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil { return code }
        if let m = code.range(of: "[A-Z]{2}$", options: .regularExpression) { return String(code[m]) }
        return code
    }

    /// Build the cache URL by filling `{state}` (case-insensitive, lowercased)
    /// into the template and joining to `baseUrl` with exactly one slash.
    static func buildCacheURL(_ integration: Integration, state: String) -> URL? {
        let path = integration.urlTemplate.replacingOccurrences(
            of: "{state}", with: state.lowercased(), options: [.caseInsensitive]
        )
        let base = integration.baseUrl
        let joined: String
        if base.hasSuffix("/") && path.hasPrefix("/") {
            joined = base + String(path.dropFirst())
        } else if !base.hasSuffix("/") && !path.hasPrefix("/") {
            joined = base + "/" + path
        } else {
            joined = base + path
        }
        return URL(string: joined)
    }

    /// Slots between localized listings for a given percent. 25 → 4 (every 4th
    /// slot). 0/absent → 0 (disabled); >= 100 → 1 (every slot).
    static func everyN(frequencyPercent: Int) -> Int {
        if frequencyPercent <= 0 { return 0 }
        if frequencyPercent >= 100 { return 1 }
        return max(1, Int((100.0 / Double(frequencyPercent)).rounded()))
    }

    /// Replace every Nth slot of `primary` with a localized listing, keeping the
    /// total count unchanged. Secondary listings are first de-duped against
    /// primary ids, then shuffled (random pick "from whatever was returned"),
    /// then cycled so every Nth slot is filled. Returns `primary` unchanged when
    /// there's nothing to disperse.
    static func merge(primary: [SellwildListing], secondary: [SellwildListing], everyN: Int) -> [SellwildListing] {
        if everyN <= 0 || secondary.isEmpty || primary.isEmpty { return primary }
        let primaryIds = Set(primary.map { $0.id })
        let pool = secondary.filter { !primaryIds.contains($0.id) }.shuffled()
        if pool.isEmpty { return primary }

        var out: [SellwildListing] = []
        out.reserveCapacity(primary.count)
        var s = 0
        for i in 0..<primary.count {
            if (i + 1) % everyN == 0 {
                out.append(pool[s % pool.count])
                s += 1
            } else {
                out.append(primary[i])
            }
        }
        return out
    }

    // MARK: Remote parsing

    /// The remote `LOCALIZED_LISTINGS` value may arrive as a JSON object or as a
    /// JSON string; coerce both into `[String: Any]`, else nil.
    private static func safeParseObject(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        if let s = value as? String,
           let data = s.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return obj
        }
        return nil
    }

    // MARK: Coercion helpers

    private static func numeric(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
