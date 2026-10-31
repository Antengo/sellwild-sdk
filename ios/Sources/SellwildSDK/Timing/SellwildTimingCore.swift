import Foundation

/// sdkTiming pure core: a Swift port of contracts/reference/sdk-timing.mjs
/// (contracts/FAILURES.md section 18.1). Reproduces
/// contracts/golden/sdk-timing.vectors.json.
enum SellwildTimingCore {
    static let eventName = "sdkTiming"
    static let label = "timing"
    static let version = "1"

    static let steps = ["config.fetch", "listings.fetch", "listings.decode", "feed.firstListing", "ad.firstLoad"]
    static let attributeKeys = [
        "code", "client", "clientVersion", "tv", "step", "ms", "zoneId",
        "appId", "appVersion", "os", "device", "net", "seq"
    ]

    enum Limits {
        static let defaultRate = 0.1
        static let sessionTimings = 50
        static let maxMs = 600_000.0
        static let field = 64
        static let zoneId = 32
    }

    static let budgets: [String: Int] = ["config.fetch": 3000, "listings.fetch": 4000, "ad.firstLoad": 6000]
    static let budgetKeys: [String: String] = [
        "config.fetch": "TIMING_BUDGET_CONFIG_MS",
        "listings.fetch": "TIMING_BUDGET_LISTINGS_MS",
        "ad.firstLoad": "TIMING_BUDGET_AD_MS"
    ]
    static let slowCodes: [String: String] = [
        "config.fetch": "config.fetch.slow",
        "listings.fetch": "listings.fetch.slow",
        "ad.firstLoad": "ad.load.slow"
    ]

    struct Input {
        var step: Any?
        var ms: Any?
        var zoneId: Any?
    }

    struct Context {
        var partnerCode: Any?
        var client: Any?
        var clientVersion: Any?
        var appId: Any?
        var appVersion: Any?
        var os: Any?
        var device: Any?
        var net: Any?
        var eventsEnabled: Any?
        var timingEnabled: Any?
        var timingSampleRate: Any?
    }

    struct State: Equatable {
        var sessionCount = 0
    }

    struct Event: Equatable {
        var event: String
        var action: String
        var label: String
        var attributes: [String: String]
        var uid: String
        var createdTime: Int64
    }

    struct Decision {
        var state: State
        var event: Event?
        var reason: String?
    }

    private typealias Core = SellwildFailuresCore

    /// A positive whole number of ms from a remote value, else nil.
    static func parseBudgetMs(_ v: Any?) -> Int? {
        var n: Double?
        switch Core.value(v) {
        case .number(let d):
            n = d.isFinite ? d.rounded(.down) : nil
        case .string(let raw):
            let t = Core.trimAscii(raw)
            let digits = t.hasPrefix("+") ? String(t.dropFirst()) : t
            let isWhole = !digits.isEmpty && digits.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
            n = isWhole ? Double(digits) : nil
        default:
            n = nil
        }
        guard let value = n, value >= 1 else { return nil }
        return Int(value)
    }

    /// The budget of `step`: the remote override, else the default; nil for a step without one.
    static func budgetFor(_ step: Any?, remote: [String: Any]?) -> Int? {
        guard let step = step as? String, let fallback = budgets[step], let key = budgetKeys[step] else { return nil }
        return parseBudgetMs(remote?[key]) ?? fallback
    }

    /// Whether `ms` is over the budget of `step`.
    static func isSlow(_ step: Any?, ms: Any?, remote: [String: Any]?) -> Bool {
        guard let budget = budgetFor(step, remote: remote), case .number(let value) = Core.value(ms) else {
            return false
        }
        return value.isFinite && value > Double(budget)
    }

    /// TIMING_SAMPLE_RATE clamped to [0, 1]; unset or anything else → 0.1.
    static func timingRate(_ v: Any?) -> Double {
        guard let rate = Core.parseRate(v) else { return Limits.defaultRate }
        return min(1, max(0, rate))
    }

    /// fnv1a32(uid + ":timing") / 2^32 < rate.
    static func isTimingSampled(uid: Any?, rate: Double) -> Bool {
        if rate >= 1 { return true }
        if rate <= 0 { return false }
        return Double(Core.fnv1a32(((uid as? String) ?? "") + ":timing")) / 4_294_967_296 < rate
    }

    private static func cleanBounded(_ v: Any?, _ max: Int) -> String? {
        guard v is String else { return nil }
        let t = Core.cleanText(v)
        return t.isEmpty ? nil : Core.truncateUnicode(t, max)
    }

    /// The whole decision as a pure function (FAILURES.md 18.1).
    static func decide(state: State, input: Input, context: Context, uid: Any?, now: Int64) -> Decision {
        func drop(_ reason: String) -> Decision { Decision(state: state, event: nil, reason: reason) }

        if !Core.coerceFlag(context.eventsEnabled, true) { return drop("events_disabled") }
        if !Core.coerceFlag(context.timingEnabled, true) { return drop("timing_disabled") }
        guard case .string(let step) = Core.value(input.step), steps.contains(step) else { return drop("invalid_step") }
        guard case .number(let ms) = Core.value(input.ms), ms.isFinite, ms >= 0, ms <= Limits.maxMs else {
            return drop("invalid_ms")
        }
        if !isTimingSampled(uid: uid, rate: timingRate(context.timingSampleRate)) { return drop("sampled_out") }
        if state.sessionCount >= Limits.sessionTimings { return drop("session_capped") }

        let seq = state.sessionCount + 1
        var a: [String: String] = [
            "code": cleanBounded(context.partnerCode, Limits.field) ?? "unknown",
            "client": cleanBounded(context.client, Limits.field) ?? "unknown",
            "clientVersion": cleanBounded(context.clientVersion, Limits.field) ?? "unknown",
            "tv": version,
            "step": step,
            "ms": String(Int64(ms.rounded(.toNearestOrAwayFromZero))),
            "seq": String(seq)
        ]
        a["zoneId"] = cleanBounded(input.zoneId, Limits.zoneId)
        a["appId"] = cleanBounded(context.appId, Limits.field)
        a["appVersion"] = cleanBounded(context.appVersion, Limits.field)
        a["os"] = cleanBounded(context.os, Limits.field)
        a["device"] = cleanBounded(context.device, Limits.field)
        a["net"] = cleanBounded(context.net, Limits.field)
        return Decision(
            state: State(sessionCount: seq),
            event: Event(event: eventName, action: step, label: label, attributes: a,
                         uid: (uid as? String) ?? "", createdTime: now),
            reason: nil
        )
    }
}
