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

    // MARK: Environment

    /// What the sync talks to. Partners always get `live`; tests swap
    /// `environment` for a recording transport, a fixed clock, their own
    /// defaults suite and a chosen advertising id.
    struct Environment {
        /// Sends the sync POST.
        var send: (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void
        /// Now, in epoch milliseconds.
        var nowMs: () -> Double
        /// Where the gcid, the eid blob and the last sync time are kept.
        var defaults: UserDefaults
        /// The device IDFA and its type, or nil when there is no usable one.
        var advertisingId: () -> (String, String)?

        static var live: Environment {
            Environment(
                send: sender(.shared),
                nowMs: { Date().timeIntervalSince1970 * 1000 },
                defaults: .standard,
                advertisingId: SellwildGrowthCode.liveAdvertisingId
            )
        }

        /// A transport that runs each request as a data task on `session`.
        static func sender(_ session: URLSession) -> (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void {
            { request, completion in session.dataTask(with: request, completionHandler: completion).resume() }
        }
    }

    static var environment = Environment.live

    /// Entry point — call from an ad load. Idempotent per launch. Injects any
    /// cached eids immediately, then (subject to the throttle) refreshes them
    /// from GrowthCode in the background. No-op unless enabled with a partner id
    /// and sync url; enabled without them is reported (`growthcode.config.missing`)
    /// once per launch. That report does not use up the sync: a config that
    /// gains the settings later in the launch still syncs, as before.
    static func resolveIfNeeded(config: SellwildConfig, zoneId: String?) {
        let settings = resolve(config: config, zoneId: zoneId)
        guard settings.enabled else { return }
        guard let pid = nonEmpty(settings.partnerId), let syncUrl = nonEmpty(settings.syncUrl) else {
            if SellwildReportOnce.first(.growthcodeConfigMissing) {
                SellwildFailures.log(code: .growthcodeConfigMissing, component: .growthcode, severity: .warn,
                                     message: "GrowthCode is enabled but its partner id or sync URL is missing")
            }
            return
        }

        lock.lock()
        if didAttempt { lock.unlock(); return }
        didAttempt = true
        lock.unlock()

        let env = environment
        // 1. Replay cached eids right away so the auction has GrowthCode signal
        //    even inside the throttle window (we only PAY for the network call
        //    every ttlHours; the eids stay live in between).
        if let cached = nonEmpty(env.defaults.string(forKey: ebKey(pid))) {
            let eids = parseEidBlob(cached)
            if !eids.isEmpty { SellwildEidRegistry.setGrowthCode(eids) }
        }

        // 2. Decide whether to make the (billed) network call.
        let gcid = nonEmpty(env.defaults.string(forKey: gcidKey(pid)))
        let lastSync = env.defaults.object(forKey: syncedAtKey(pid)) as? Double
        guard shouldSync(gcid: gcid, lastSyncMs: lastSync, ttlHours: settings.ttlHours, nowMs: env.nowMs()) else { return }

        // 3. Advertising id, honouring the MAID policy. A nil id means no usable
        //    IDFA (ATT not authorized). When sending is off, skip the whole call
        //    for such devices so we don't pay for a signal-less request. A
        //    missing id is the user's privacy choice, never a failure.
        let maid = env.advertisingId()
        if maid == nil && !settings.sendMaid { return }

        performSync(env: env, endpoint: settings.endpoint, pid: pid, syncUrl: syncUrl, gcid: gcid, maid: maid)
    }

    /// Sync only when there's no stored GCID or the TTL window has elapsed.
    static func shouldSync(gcid: String?, lastSyncMs: Double?, ttlHours: Double, nowMs: Double) -> Bool {
        if gcid == nil { return true }
        guard let last = lastSyncMs else { return true }
        return nowMs - last >= ttlHours * 3_600_000
    }

    // MARK: Network

    private static func performSync(env: Environment, endpoint: String, pid: String, syncUrl: String,
                                    gcid: String?, maid: (String, String)?) {
        guard let request = syncRequest(endpoint: endpoint, pid: pid, syncUrl: syncUrl, gcid: gcid, maid: maid) else {
            SellwildFailures.log(code: .growthcodeUrlInvalid, component: .growthcode, severity: .warn,
                                 message: "GrowthCode endpoint URL could not be built")
            return
        }
        env.send(request) { data, response, error in
            let json: [String: Any]
            switch syncOutcome(data: data, response: response, error: error) {
            case .failure(let failure):
                report(failure, url: endpoint)
                return
            case .success(let body):
                json = body
            }

            // Persist the throttle timestamp regardless, so a fill-less response
            // still holds off the next billed call for the TTL window.
            env.defaults.set(env.nowMs(), forKey: syncedAtKey(pid))

            if let newGcid = nonEmpty(json["gc_id"]) {
                env.defaults.set(newGcid, forKey: gcidKey(pid))
            }
            if let eb = nonEmpty(json["eb"]) {
                env.defaults.set(eb, forKey: ebKey(pid))
                let eids = parseEidBlob(eb)
                if !eids.isEmpty { SellwildEidRegistry.setGrowthCode(eids) }
            }
        }
    }

    /// The sync POST (pure): `pid` and `u` ride the query string (per the
    /// GrowthCode contract), the rest is a form body. nil when `endpoint` is
    /// not a URL.
    static func syncRequest(endpoint: String, pid: String, syncUrl: String,
                            gcid: String?, maid: (String, String)?) -> URLRequest? {
        let url = URLComponents(string: endpoint).flatMap { components -> URL? in
            var components = components
            components.queryItems = (components.queryItems ?? []) + [
                URLQueryItem(name: "pid", value: pid),
                URLQueryItem(name: "u", value: syncUrl),
            ]
            return components.url
        }
        guard let url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formBody(gcid: gcid, host: syncHost(syncUrl), maid: maid).utf8)
        return request
    }

    /// Why a sync answer cannot be used. The throttle is not saved, so the
    /// sync runs again next launch.
    enum SyncFailure: Error {
        case transport(Error)
        case http(Int)
        case parse(Error?, String)
    }

    /// A finished sync request as its JSON object, or why not (pure).
    static func syncOutcome(data: Data?, response: URLResponse?, error: Error?) -> Result<[String: Any], SyncFailure> {
        if let error { return .failure(.transport(error)) }
        if let status = SellwildLoadFailure.httpFailureStatus(response) { return .failure(.http(status)) }
        guard let data, !data.isEmpty else { return .failure(.parse(nil, "GrowthCode sync response has no body")) }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.parse(nil, "GrowthCode sync response is not a JSON object"))
            }
            return .success(json)
        } catch {
            return .failure(.parse(error, "GrowthCode sync response is not valid JSON"))
        }
    }

    private static func report(_ failure: SyncFailure, url: String) {
        switch failure {
        case .transport(let error):
            switch SellwildLoadFailure.transport(error) {
            case .cancelled:
                SellwildLog.debug("[SellwildGrowthCode] sync cancelled")
            case .timeout:
                SellwildFailures.log(code: .growthcodeSyncTimeout, component: .growthcode, severity: .warn, error: error, url: url)
            case .network:
                SellwildFailures.log(code: .growthcodeSyncNetwork, component: .growthcode, severity: .warn, error: error, url: url)
            }
        case .http(let status):
            SellwildFailures.log(code: .growthcodeSyncHttp, component: .growthcode, severity: .warn,
                                 message: "HTTP \(status)", httpStatus: status, url: url)
        case .parse(let error, let message):
            SellwildFailures.log(code: .growthcodeSyncParse, component: .growthcode, severity: .warn,
                                 error: error, message: message, url: url)
        }
    }

    /// Form body: gcid (omitted on first sync), h (host), maid + maid_type
    /// (only when a real device id is available).
    static func formBody(gcid: String?, host: String?, maid: (String, String)?) -> String {
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
    static func liveAdvertisingId() -> (String, String)? {
        #if canImport(AdSupport)
        return maid(fromIDFA: ASIdentifierManager.shared().advertisingIdentifier.uuidString)
        #else
        return nil
        #endif
    }

    /// `(idfa, "IDFA")`, or nil for the zeroed id iOS hands out without ATT
    /// authorization.
    static func maid(fromIDFA idfa: String) -> (String, String)? {
        idfa.lowercased() == "00000000-0000-0000-0000-000000000000" ? nil : (idfa, "IDFA")
    }

    // MARK: Parsing

    /// Parse the GrowthCode `eb` (a JSON string of
    /// `[{ source, uids: [{ id, atype?, stype? }] }]`) into `[SellwildEid]`.
    /// Provider-only `inserter`/`matcher` are dropped; a uid `stype` (with no
    /// atype) is preserved in `ext`. Never throws — returns [] on bad input,
    /// and reports a blob that is not a list, or entries it had to drop
    /// (`growthcode.eid.invalid`).
    static func parseEidBlob(_ eb: String) -> [SellwildEid] {
        let parsed = eidBlob(eb)
        if let problem = parsed.problem {
            SellwildFailures.log(code: .growthcodeEidInvalid, component: .growthcode, severity: .warn, message: problem)
        }
        return parsed.eids
    }

    /// `parseEidBlob` without the report (pure): the eids, and what was wrong.
    static func eidBlob(_ eb: String) -> (eids: [SellwildEid], problem: String?) {
        let entries: [[String: Any]]
        do {
            guard let list = try JSONSerialization.jsonObject(with: Data(eb.utf8)) as? [[String: Any]] else {
                return ([], "eid blob is not a list of objects")
            }
            entries = list
        } catch {
            return ([], "eid blob is not valid JSON")
        }

        var eids: [SellwildEid] = []
        var dropped = 0
        for entry in entries {
            guard let source = nonEmpty(entry["source"]),
                  let rawUids = entry["uids"] as? [[String: Any]], !rawUids.isEmpty else {
                dropped += 1
                continue
            }
            var uids: [SellwildEidUID] = []
            for u in rawUids {
                guard let id = nonEmpty(u["id"]) else {
                    dropped += 1
                    continue
                }
                // clampedInt: `Int(_:)` traps on "inf", "nan" and text longer than Int allows.
                let atype = numeric(u["atype"]).flatMap(SellwildNumber.clampedInt) ?? 0
                if let stype = nonEmpty(u["stype"]) {
                    uids.append(SellwildEidUID(id: id, atype: atype, ext: ["stype": stype]))
                } else {
                    uids.append(SellwildEidUID(id: id, atype: atype))
                }
            }
            if !uids.isEmpty { eids.append(SellwildEid(source: source, uids: uids)) }
        }
        return (eids, dropped > 0 ? "\(dropped) eid entries or uids without a source, uids or id were dropped" : nil)
    }

    // MARK: Persistence (UserDefaults, per partner id)

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

    /// A number, or numeric text. A JSON number is an NSNumber: `as Double`
    /// reads it unless it is an integer a Double cannot hold exactly, then
    /// `as Int`, and one too large for an Int is read through NSNumber.
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
