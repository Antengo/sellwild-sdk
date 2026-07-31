// SellwildGrowthCode.swift — GrowthCode Signal Resolve (identity) on iOS.
//
// GrowthCode is an identity provider. Once per session (subject to a persisted
// throttle), the SDK POSTs a "sync" to GrowthCode carrying a stored GCID and
// — when the host app already holds ad-tracking permission — the device IDFA.
// GrowthCode returns a GCID we persist and an EID blob we merge into every
// Prebid auction via `SellwildEidRegistry` (partner-set eids win on conflict).
//
// Toggled from remote config, OFF by default, so it ships dormant and turns
// on/off from the CMS with no app release:
//   - Global:   GROWTHCODE_ENABLED          (bool / "1" / "true")
//   - Per-zone: GROWTHCODE_ENABLED_BY_ZONE  ({ "<zoneId>": true })
// Keys / params (partner id, endpoint, sync url, MAID policy, TTL) resolve
// local `config.growthCode.*` → remote `GROWTHCODE_*` → default, mirroring the
// S2S-config resolution precedence.
//
// Privacy: we NEVER trigger the ATT prompt. We only READ the IDFA the system
// already grants — without authorization iOS hands back the zeroed id, which
// we treat as "no device id". So we take on none of the host app's ad-tracking
// regulatory surface: if they haven't set up ATT, GrowthCode is called without
// a MAID (or skipped entirely when GROWTHCODE_SEND_MAID is off).
//
// This file is platform-specific but mirrors `core/src/growthcode.ts` — the
// canonical, web-shareable reference for the same request/parse/merge/throttle
// logic. It touches NO Prebid fork API directly (it feeds the already-shipping
// `SellwildEid` / `setExternalUserIds` path), so there is nothing here to
// verify against the shaded fork.

import Foundation
#if canImport(AdSupport)
import AdSupport
#endif

public enum SellwildGrowthCode {

    static let defaultEndpoint = "https://ids.api.gcprivacy.id/v4/sync/api"
    static let defaultTtlHours: Double = 48

    // Resolved settings for a placement/session.
    struct Settings {
        let enabled: Bool
        let partnerId: String?
        let endpoint: String
        let syncUrl: String?
        let sendMaid: Bool
        let ttlHours: Double
    }

    // Session guard — the sync runs at most once per process launch. `load()`
    // is called per ad view, so without this every placement would re-trigger.
    private static let lock = NSLock()
    private static var didAttempt = false

    /// Resolve GrowthCode settings: local `config.growthCode.*` wins, else the
    /// raw remote `GROWTHCODE_*` value, else a default. `enabled` also honours
    /// the per-zone map when the global remote flag is falsy (video/native shape).
    static func resolve(config: SellwildConfig, zoneId: String?) -> Settings {
        let local = config.growthCode
        let remote = config.remoteValues

        let enabled: Bool
        if let e = local?.enabled {
            enabled = e
        } else if truthy(remote?["GROWTHCODE_ENABLED"]) {
            enabled = true
        } else if let zoneId,
                  let byZone = remote?["GROWTHCODE_ENABLED_BY_ZONE"] as? [String: Any],
                  let perZone = byZone[zoneId] {
            enabled = truthy(perZone)
        } else {
            enabled = false
        }

        let sendMaid: Bool
        if let s = local?.sendMaid {
            sendMaid = s
        } else if let raw = remote?["GROWTHCODE_SEND_MAID"] {
            sendMaid = truthy(raw)
        } else {
            sendMaid = true
        }

        return Settings(
            enabled: enabled,
            partnerId: local?.partnerId ?? nonEmpty(remote?["GROWTHCODE_PARTNER_ID"]),
            endpoint: local?.endpoint ?? nonEmpty(remote?["GROWTHCODE_ENDPOINT"]) ?? defaultEndpoint,
            syncUrl: local?.syncUrl ?? nonEmpty(remote?["GROWTHCODE_SYNC_URL"]),
            sendMaid: sendMaid,
            ttlHours: local?.ttlHours.map(Double.init) ?? numeric(remote?["GROWTHCODE_TTL_HOURS"]) ?? defaultTtlHours
        )
    }

    /// Entry point — call from an ad load. Idempotent per launch. Injects any
    /// cached eids immediately, then (subject to the throttle) refreshes them
    /// from GrowthCode in the background. No-op unless enabled with a partner id
    /// and sync url.
    static func resolveIfNeeded(config: SellwildConfig, zoneId: String?) {
        let settings = resolve(config: config, zoneId: zoneId)
        guard settings.enabled,
              let pid = settings.partnerId, !pid.isEmpty,
              let syncUrl = settings.syncUrl, !syncUrl.isEmpty else { return }

        lock.lock()
        if didAttempt { lock.unlock(); return }
        didAttempt = true
        lock.unlock()

        // 1. Replay cached eids right away so the auction has GrowthCode signal
        //    even inside the throttle window (we only PAY for the network call
        //    every ttlHours; the eids stay live in between).
        if let cached = nonEmpty(defaults.string(forKey: ebKey(pid))) {
            let eids = parseEidBlob(cached)
            if !eids.isEmpty { SellwildEidRegistry.setGrowthCode(eids) }
        }

        // 2. Decide whether to make the (billed) network call.
        let gcid = nonEmpty(defaults.string(forKey: gcidKey(pid)))
        let lastSync = defaults.object(forKey: syncedAtKey(pid)) as? Double
        guard shouldSync(gcid: gcid, lastSyncMs: lastSync, ttlHours: settings.ttlHours) else { return }

        // 3. Advertising id, honouring the MAID policy. A nil id means no usable
        //    IDFA (ATT not authorized). When sending is off, skip the whole call
        //    for such devices so we don't pay for a signal-less request.
        let maid = advertisingId()
        if maid == nil && !settings.sendMaid { return }

        performSync(settings: settings, pid: pid, syncUrl: syncUrl, gcid: gcid, maid: maid)
    }

    /// Sync only when there's no stored GCID or the TTL window has elapsed.
    static func shouldSync(gcid: String?, lastSyncMs: Double?, ttlHours: Double) -> Bool {
        if gcid == nil { return true }
        guard let last = lastSyncMs else { return true }
        return Date().timeIntervalSince1970 * 1000 - last >= ttlHours * 3_600_000
    }

    // MARK: Network

    private static func performSync(settings: Settings, pid: String, syncUrl: String, gcid: String?, maid: (String, String)?) {
        var comps = URLComponents(string: settings.endpoint)
        // pid + u ride the query string (per the GrowthCode contract).
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "pid", value: pid))
        items.append(URLQueryItem(name: "u", value: syncUrl))
        comps?.queryItems = items
        guard let url = comps?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(gcid: gcid, host: syncHost(syncUrl), maid: maid).data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

            // Persist the throttle timestamp regardless, so a fill-less response
            // still holds off the next billed call for the TTL window.
            defaults.set(Date().timeIntervalSince1970 * 1000, forKey: syncedAtKey(pid))

            if let newGcid = nonEmpty(json["gc_id"]) {
                defaults.set(newGcid, forKey: gcidKey(pid))
            }
            if let eb = nonEmpty(json["eb"]) {
                defaults.set(eb, forKey: ebKey(pid))
                let eids = parseEidBlob(eb)
                if !eids.isEmpty { SellwildEidRegistry.setGrowthCode(eids) }
            }
        }.resume()
    }

    /// Form body: gcid (omitted on first sync), h (host), maid + maid_type
    /// (only when a real device id is available).
    private static func formBody(gcid: String?, host: String?, maid: (String, String)?) -> String {
        var parts: [String] = []
        func add(_ k: String, _ v: String?) {
            guard let v, !v.isEmpty,
                  let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed),
                  let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return }
            parts.append("\(ek)=\(ev)")
        }
        add("gcid", gcid)
        add("h", host)
        if let (id, type) = maid {
            add("maid", id)
            add("maid_type", type)
        }
        return parts.joined(separator: "&")
    }

    // MARK: Advertising id

    /// The device IDFA when the host app already holds ATT authorization, else
    /// nil. We never prompt: without authorization iOS returns the zeroed id,
    /// which we map to nil ("no device id").
    private static func advertisingId() -> (String, String)? {
        #if canImport(AdSupport)
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        if idfa.lowercased() != "00000000-0000-0000-0000-000000000000" {
            return (idfa, "IDFA")
        }
        #endif
        return nil
    }

    // MARK: Parsing

    /// Parse the GrowthCode `eb` (a JSON string of
    /// `[{ source, uids: [{ id, atype?, stype? }] }]`) into `[SellwildEid]`.
    /// Provider-only `inserter`/`matcher` are dropped; a uid `stype` (with no
    /// atype) is preserved in `ext`. Never throws — returns [] on bad input.
    static func parseEidBlob(_ eb: String) -> [SellwildEid] {
        guard let data = eb.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }

        var eids: [SellwildEid] = []
        for entry in arr {
            guard let source = nonEmpty(entry["source"]),
                  let rawUids = entry["uids"] as? [[String: Any]] else { continue }
            var uids: [SellwildEidUID] = []
            for u in rawUids {
                guard let id = nonEmpty(u["id"]) else { continue }
                let atype = Int(numeric(u["atype"]) ?? 0)
                if let stype = nonEmpty(u["stype"]) {
                    uids.append(SellwildEidUID(id: id, atype: atype, ext: ["stype": stype]))
                } else {
                    uids.append(SellwildEidUID(id: id, atype: atype))
                }
            }
            if !uids.isEmpty { eids.append(SellwildEid(source: source, uids: uids)) }
        }
        return eids
    }

    // MARK: Persistence (UserDefaults, per partner id)

    private static var defaults: UserDefaults { .standard }
    private static func gcidKey(_ pid: String) -> String { "_sw_gc_id.\(pid)" }
    private static func syncedAtKey(_ pid: String) -> String { "_sw_gc_synced_at.\(pid)" }
    private static func ebKey(_ pid: String) -> String { "_sw_gc_eb.\(pid)" }

    /// The host param `h` — the sync url's host, or the raw value if it isn't a URL.
    private static func syncHost(_ syncUrl: String) -> String {
        URLComponents(string: syncUrl)?.host ?? syncUrl
    }

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

    // Test seam — reset the once-per-launch latch.
    static func resetForTesting() {
        lock.lock(); didAttempt = false; lock.unlock()
    }
}

private extension CharacterSet {
    /// Form-body-safe set: alphanumerics plus the unreserved URL chars, so
    /// values are percent-encoded for `application/x-www-form-urlencoded`.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
