// SellwildID5.swift — ID5 Universal ID (identity) on iOS, auto-resolved.
//
// ID5 is an identity provider that mints a Universal ID from first-party /
// probabilistic signals with just a partner id — NO user login/email — so unlike
// UID2/LiveRamp the SDK can resolve it automatically (like GrowthCode). Once per
// launch (subject to a persisted throttle), the SDK fetches an ID5 id and merges
// it into every Prebid auction via `SellwildEidRegistry.setId5` (source
// `id5-sync.com`, so it coexists with GrowthCode and partner-supplied eids).
//
// Toggled from remote config, OFF by default, so it ships dormant and turns on/off
// from the CMS with no app release:
//   - Global:   ID5_ENABLED          (bool / "1" / "true")
//   - Per-zone: ID5_ENABLED_BY_ZONE  ({ "<zoneId>": true })
// Params (partner id, endpoint, TTL) resolve from remote `ID5_*`, else defaults.
//
// Privacy: like GrowthCode we NEVER prompt for ATT. We pass the IDFA only when the
// host app already holds authorization (else nil); ID5 works without it.
//
// ‼️ VERIFY BEFORE ENABLING (off by default until then):
//   1. Partner id — set ID5_PARTNER_ID in the CMS to the real ID5 partner number.
//   2. Fetch contract — the request/response below follow ID5's public Fetch API
//      (GET g/v2/{partner}.json -> { universal_uid, signature, link_type }).
//      Confirm against ID5's CURRENT mobile spec; ID5 may require the /gm/v3 POST
//      with the previously-stored `signature` for id continuity, plus gdpr params.
//   3. atype — confirm the OpenRTB agent type ID5 expects (1 used below).

import Foundation
#if canImport(AdSupport)
import AdSupport
#endif

public enum SellwildID5 {

    static let defaultEndpoint = "https://id5-sync.com/g/v2"
    static let defaultTtlHours: Double = 24
    static let eidSource = "id5-sync.com"

    struct Settings {
        let enabled: Bool
        let partnerId: String?
        let endpoint: String
        let ttlHours: Double
    }

    private static let lock = NSLock()
    private static var didAttempt = false

    /// Resolve ID5 settings from remote config. `enabled` honours the per-zone map
    /// when the global flag is falsy (same shape as GrowthCode / video).
    static func resolve(config: SellwildConfig, zoneId: String?) -> Settings {
        let remote = config.remoteValues

        let enabled: Bool
        if truthy(remote?["ID5_ENABLED"]) {
            enabled = true
        } else if let zoneId,
                  let byZone = remote?["ID5_ENABLED_BY_ZONE"] as? [String: Any],
                  let perZone = byZone[zoneId] {
            enabled = truthy(perZone)
        } else {
            enabled = false
        }

        return Settings(
            enabled: enabled,
            partnerId: nonEmpty(remote?["ID5_PARTNER_ID"]),
            endpoint: nonEmpty(remote?["ID5_ENDPOINT"]) ?? defaultEndpoint,
            ttlHours: numeric(remote?["ID5_TTL_HOURS"]) ?? defaultTtlHours
        )
    }

    /// Entry point — call from an ad load. Idempotent per launch. Replays the
    /// cached ID5 id immediately, then (subject to the throttle) refreshes it in
    /// the background. No-op unless enabled with a partner id.
    static func resolveIfNeeded(config: SellwildConfig, zoneId: String?) {
        let settings = resolve(config: config, zoneId: zoneId)
        guard settings.enabled,
              let pid = settings.partnerId, !pid.isEmpty else { return }

        lock.lock()
        if didAttempt { lock.unlock(); return }
        didAttempt = true
        lock.unlock()

        // 1. Replay the cached id so the auction has ID5 signal inside the throttle
        //    window (we only pay for the network call every ttlHours).
        if let cached = nonEmpty(defaults.string(forKey: uidKey(pid))) {
            SellwildEidRegistry.setId5([eid(uid: cached, linkType: linkTypeCached(pid))])
        }

        // 2. Throttle the (billed) fetch.
        let lastSync = defaults.object(forKey: syncedAtKey(pid)) as? Double
        guard shouldSync(uid: nonEmpty(defaults.string(forKey: uidKey(pid))), lastSyncMs: lastSync, ttlHours: settings.ttlHours) else { return }

        performFetch(settings: settings, pid: pid)
    }

    static func shouldSync(uid: String?, lastSyncMs: Double?, ttlHours: Double) -> Bool {
        if uid == nil { return true }
        guard let last = lastSyncMs else { return true }
        return Date().timeIntervalSince1970 * 1000 - last >= ttlHours * 3_600_000
    }

    // MARK: Network

    // ‼️ Implements ID5's public Fetch API shape — VERIFY against ID5's current
    // mobile spec (see file header) before enabling. Off by default until then.
    private static func performFetch(settings: Settings, pid: String) {
        var comps = URLComponents(string: "\(settings.endpoint)/\(pid).json")
        var items = comps?.queryItems ?? []
        // GDPR: 0 = not in scope (default). When a CMP is present the host should
        // surface a TCF string; ID5 also reads IAB storage. Kept minimal here.
        items.append(URLQueryItem(name: "gdpr", value: "0"))
        // Carry the prior signature for id continuity when we have one.
        if let sig = nonEmpty(defaults.string(forKey: sigKey(pid))) {
            items.append(URLQueryItem(name: "s", value: sig))
        }
        if let (idfa, _) = advertisingId() {
            items.append(URLQueryItem(name: "ifa", value: idfa))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { return }

        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

            defaults.set(Date().timeIntervalSince1970 * 1000, forKey: syncedAtKey(pid))

            guard let uid = nonEmpty(json["universal_uid"]) else { return }
            defaults.set(uid, forKey: uidKey(pid))
            if let sig = nonEmpty(json["signature"]) { defaults.set(sig, forKey: sigKey(pid)) }
            let linkType = Int(numeric(json["link_type"]) ?? 0)
            defaults.set(linkType, forKey: linkTypeKey(pid))

            SellwildEidRegistry.setId5([eid(uid: uid, linkType: linkType)])
        }.resume()
    }

    /// Build the OpenRTB eid for an ID5 id. atype 1 (cookie/first-party); ID5's
    /// `link_type` (0/1/2 = anon/probabilistic/deterministic) rides in ext.
    private static func eid(uid: String, linkType: Int) -> SellwildEid {
        SellwildEid(source: eidSource, uids: [
            SellwildEidUID(id: uid, atype: 1, ext: ["linkType": linkType])
        ])
    }

    private static func linkTypeCached(_ pid: String) -> Int {
        defaults.object(forKey: linkTypeKey(pid)) as? Int ?? 0
    }

    // MARK: Advertising id (read-only, ATT-gated; never prompts)

    private static func advertisingId() -> (String, String)? {
        #if canImport(AdSupport)
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        if idfa.lowercased() != "00000000-0000-0000-0000-000000000000" {
            return (idfa, "IDFA")
        }
        #endif
        return nil
    }

    // MARK: Persistence (UserDefaults, per partner id)

    private static var defaults: UserDefaults { .standard }
    private static func uidKey(_ pid: String) -> String { "_sw_id5_uid.\(pid)" }
    private static func sigKey(_ pid: String) -> String { "_sw_id5_sig.\(pid)" }
    private static func linkTypeKey(_ pid: String) -> String { "_sw_id5_lt.\(pid)" }
    private static func syncedAtKey(_ pid: String) -> String { "_sw_id5_synced_at.\(pid)" }

    // MARK: Coercion helpers

    private static func truthy(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "yes", "on"].contains(s.lowercased())
        default: return false
        }
    }

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
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    /// Test seam — reset the once-per-launch latch.
    static func resetForTesting() {
        lock.lock(); didAttempt = false; lock.unlock()
    }
}
