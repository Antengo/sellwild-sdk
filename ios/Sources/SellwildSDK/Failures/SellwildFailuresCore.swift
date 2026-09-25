import Foundation

/// Pure core of logFailure: a port of contracts/reference/log-failure.mjs
/// (contracts/FAILURES.md sections 5–7). No clock, no uid, no I/O and no
/// shared state. `SellwildFailures` reads those, calls `decide`, and pushes
/// the event it returns.
///
/// Each function mirrors the reference function of the same name, and
/// `SellwildFailuresCoreTests` replays contracts/golden/log-failure.vectors.json
/// against them. Lengths are Unicode scalars (code points), sizes are UTF-8
/// bytes, times are epoch milliseconds.
///
/// Values arrive as `Any?` so the core reads them the way the reference's
/// `typeof` checks do: nil and NSNull are the same, a boolean is never a
/// number (JSONSerialization hands both over as NSNumber), and anything else
/// falls back to the default. Strings are compared scalar by scalar, never
/// with Swift's `==`, which treats canonically equivalent strings as equal.
enum SellwildFailuresCore {

    static let contractVersion = "1"
    static let eventName = "clientFailure"
    static let invalidCode = "client.code.invalid"
    static let unknown = "unknown"

    static let components = [
        "configure", "remoteConfig", "listings", "localized", "feed", "banner", "native",
        "video", "house", "bridge", "webview", "widget", "shorts", "tv", "flipcard",
        "growthcode", "geo", "storage",
    ]
    static let severities = ["fatal", "error", "warn"]
    static let wrappers = ["react-native", "flutter"]

    /// Wire order of attribute keys. This is also the allowlist.
    static let attributeKeys = [
        "code", "client", "clientVersion", "severity", "fv", "errName", "msg", "stack",
        "httpStatus", "host", "zoneId", "wrapper", "release", "seq", "repeat", "capped",
    ]

    enum Limits {
        static let codeMax = 64
        static let errName = 64
        static let msg = 200
        static let msgBudget = 80
        static let msgKey = 64
        static let stack = 800
        static let stackFrames = 5
        static let zoneId = 32
        static let host = 253
        static let partnerCode = 64
        static let clientVersion = 32
        static let release = 64
        static let eventBytes = 2048
        static let dedupeWindowMs: Int64 = 60_000
        static let lruSize = 50
        static let perKeyEmits = 3
        static let sessionEmits = 20
    }

    // MARK: Types

    /// The pure-core input. Fields other than these never reach the event.
    struct Input {
        var code: Any?
        var component: Any?
        var severity: Any?
        var errName: Any?
        var errMessage: Any?
        var message: Any?
        var stack: Any?
        var httpStatus: Any?
        var url: Any?
        var zoneId: Any?
    }

    /// Context values as the shell holds them. The flags are raw remote values;
    /// the core coerces them.
    struct Context {
        var partnerCode: Any?
        var client: Any?
        var clientVersion: Any?
        var wrapper: Any?
        var release: Any?
        var eventsEnabled: Any?
        var failuresEnabled: Any?
        var failuresSampleRate: Any?
    }

    struct KeyEntry: Equatable {
        var key: String
        var lastEmitAt: Int64
        var suppressed: Int
        var emits: Int
    }

    /// `keys` is ordered least to most recently used.
    struct State: Equatable {
        var sessionCount = 0
        var keys: [KeyEntry] = []
    }

    struct Event: Equatable {
        var event: String
        var action: String
        var label: String
        var attributes: [String: String]
        var uid: String
        var createdTime: Int64
    }

    /// Why `decide` dropped a failure.
    enum Reason: String {
        case eventsDisabled = "events_disabled"
        case failuresDisabled = "failures_disabled"
        case sampledOut = "sampled_out"
        case sessionCapped = "session_capped"
        case keyCapped = "key_capped"
        case deduped
    }

    struct Decision {
        var state: State
        /// nil when dropped.
        var event: Event?
        var flushNow: Bool
        /// nil when emitted.
        var reason: Reason?
    }

    // MARK: Values

    /// A value as the reference's `typeof` sees it.
    enum Value {
        case string(String)
        case number(Double)
        case bool(Bool)
        /// null, undefined, object or array.
        case other
    }

    static func value(_ v: Any?) -> Value {
        switch v {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            // Swift Bool bridges to the CFBoolean singletons, as JSON booleans do.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        default:
            return .other
        }
    }

    private static func string(_ v: Any?) -> String? {
        if case .string(let s) = value(v) { return s }
        return nil
    }

    /// Code-point equality (JS `===`).
    static func same(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.elementsEqual(b.unicodeScalars)
    }

    /// `v` when it is a string in `list` (exact match), else nil.
    private static func member(_ v: Any?, of list: [String]) -> String? {
        guard let s = string(v), list.contains(where: { same($0, s) }) else { return nil }
        return s
    }

    private static func text<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    // MARK: Code points

    private static func isExtender(_ cp: UInt32) -> Bool {
        (0x0300...0x036F).contains(cp) ||
            (0x1AB0...0x1AFF).contains(cp) ||
            (0x1DC0...0x1DFF).contains(cp) ||
            (0x20D0...0x20FF).contains(cp) ||
            (0xFE00...0xFE0F).contains(cp) ||
            (0xFE20...0xFE2F).contains(cp) ||
            cp == 0x200D ||
            (0x1F3FB...0x1F3FF).contains(cp) ||
            (0xE0020...0xE007F).contains(cp) ||
            (0xE0100...0xE01EF).contains(cp)
    }

    private static func isRegionalIndicator(_ cp: UInt32) -> Bool {
        (0x1F1E6...0x1F1FF).contains(cp)
    }

    /// Cut `s` to at most `max` code points. When a cut happens the result
    /// ends in "…", which counts toward `max`. Never leaves a combining mark,
    /// variation selector, skin tone, tag or ZWJ without its base, and never
    /// splits a flag pair.
    static func truncateUnicode(_ s: String, _ max: Int) -> String {
        let cps = Array(s.unicodeScalars)
        if cps.count <= max { return s }
        var k = Swift.max(max - 1, 0)
        while k > 0 && (isExtender(cps[k].value) || cps[k - 1].value == 0x200D) { k -= 1 }
        if k > 0 && isRegionalIndicator(cps[k].value) {
            let run = cps[..<k].reversed().prefix { isRegionalIndicator($0.value) }.count
            if run % 2 == 1 { k -= 1 }
        }
        return text(cps[..<k]) + "…"
    }

    private static func firstCodePoints(_ s: String, _ n: Int) -> String {
        s.unicodeScalars.count <= n ? s : text(s.unicodeScalars.prefix(n))
    }

    // MARK: Text cleanup

    private static func isSpaceLike(_ cp: UInt32) -> Bool {
        cp <= 0x1F || (0x7F...0x9F).contains(cp) || cp == 0x20 || cp == 0xA0 ||
            cp == 0x1680 || (0x2000...0x200A).contains(cp) || cp == 0x2028 || cp == 0x2029 ||
            cp == 0x202F || cp == 0x205F || cp == 0x3000 || cp == 0xFEFF
    }

    /// Control and space-like code points become one space, runs collapse and
    /// the ends are trimmed. Non-strings give "". (Swift strings cannot hold
    /// the lone surrogates the reference replaces with U+FFFD.)
    static func cleanText(_ v: Any?) -> String {
        guard let s = string(v) else { return "" }
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for cp in s.unicodeScalars {
            if isSpaceLike(cp.value) {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace { out.append(" ") }
            pendingSpace = false
            out.append(cp)
        }
        return String(out)
    }

    private static func isAsciiSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || (0x09...0x0D).contains(c.value)
    }

    /// Trims U+0009–U+000D and U+0020 only.
    static func trimAscii(_ s: String) -> String {
        let cps = Array(s.unicodeScalars)
        guard let first = cps.firstIndex(where: { !isAsciiSpace($0) }),
              let last = cps.lastIndex(where: { !isAsciiSpace($0) })
        else { return "" }
        return text(cps[first...last])
    }

    private static func asciiLower(_ s: String) -> String {
        text(s.unicodeScalars.map { c in
            ("A"..."Z").contains(c) ? Unicode.Scalar(UInt8(truncatingIfNeeded: c.value + 32)) : c
        })
    }

    private static func isAsciiLetter(_ c: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(c) || ("A"..."Z").contains(c)
    }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(c)
    }

    private static func isHex(_ c: Unicode.Scalar) -> Bool {
        isDigit(c) || ("a"..."f").contains(c) || ("A"..."F").contains(c)
    }

    private static func hasPrefix(_ s: [Unicode.Scalar], _ prefix: String, at i: Int) -> Bool {
        let p = Array(prefix.unicodeScalars)
        return i + p.count <= s.count && s[i..<(i + p.count)].elementsEqual(p)
    }

    // MARK: Host extraction

    private static func isSchemeChar(_ c: Unicode.Scalar) -> Bool {
        isAsciiLetter(c) || isDigit(c) || c == "+" || c == "." || c == "-"
    }

    private static func isAuthorityChar(_ c: Unicode.Scalar) -> Bool {
        c.value >= 0x80 || isAsciiLetter(c) || isDigit(c) || ".-_~%!$&'*+,;=:@[]".unicodeScalars.contains(c)
    }

    /// `^[0-9]{1,3}(\.[0-9]{1,3}){3}$`
    private static func isIPv4(_ s: String) -> Bool {
        let parts = s.unicodeScalars.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { (1...3).contains($0.count) && $0.allSatisfy(isDigit) }
    }

    /// Hostname of an absolute (`scheme://`) or protocol-relative (`//`) URL,
    /// lower case, without userinfo, port or trailing dots. IP literals become
    /// "<ip>". nil when there is no host.
    static func hostOf(_ url: Any?) -> String? {
        guard let raw = string(url) else { return nil }
        let s = Array(trimAscii(raw).unicodeScalars)
        let rest: ArraySlice<Unicode.Scalar>
        if let i = (0..<s.count).first(where: { hasPrefix(s, "://", at: $0) }), i > 0,
           isAsciiLetter(s[0]), s[1..<i].allSatisfy(isSchemeChar) {
            rest = s[(i + 3)...]
        } else if hasPrefix(s, "//", at: 0) {
            rest = s[2...]
        } else {
            return nil
        }
        var auth = Array(rest.prefix { c in c != "/" && c != "?" && c != "#" && isAuthorityChar(c) })
        if let at = auth.lastIndex(of: "@") { auth = Array(auth[(at + 1)...]) }
        if auth.first == "[" { return auth.contains("]") ? "<ip>" : nil }
        if let colon = auth.firstIndex(of: ":") { auth = Array(auth[..<colon]) }
        while auth.last == "." { auth.removeLast() }
        let host = asciiLower(text(auth))
        if host.isEmpty { return nil }
        return isIPv4(host) ? "<ip>" : host
    }

    // MARK: Message and stack sanitizing

    /// The alternatives of the two sanitizing patterns (FAILURES.md 7.4, 7.5),
    /// matched by hand with the same greedy, ordered semantics:
    ///
    ///     url       [A-Za-z][A-Za-z0-9+.-]*://[^ "'<>()]*
    ///     relative  //[A-Za-z0-9-]+\.[^ "'<>()]*
    ///     email     [A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}
    ///     uuid      [0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}
    ///     ipv4      [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}
    ///     digits    [0-9]{6,}          (messages)
    ///     path      [^ ():]*/          (stack frames)
    ///     query     \?[^ :()]*         (stack frames)
    enum Token {
        case url, relative, email, uuid, ipv4, digits, path, query
    }

    private static let messageTokens: [Token] = [.url, .relative, .email, .uuid, .ipv4, .digits]
    private static let frameTokens: [Token] = [.url, .relative, .email, .uuid, .ipv4, .path, .query]

    private static func isURLChar(_ c: Unicode.Scalar) -> Bool {
        !" \"'<>()".unicodeScalars.contains(c)
    }

    /// The end (exclusive) of `token` matched at `start`, or nil.
    static func match(_ token: Token, _ s: [Unicode.Scalar], at start: Int) -> Int? {
        var i = start
        func run(_ accept: (Unicode.Scalar) -> Bool) {
            while i < s.count && accept(s[i]) { i += 1 }
        }
        func take(_ c: Unicode.Scalar) -> Bool {
            guard i < s.count, s[i] == c else { return false }
            i += 1
            return true
        }
        switch token {
        case .url:
            guard i < s.count, isAsciiLetter(s[i]) else { return nil }
            i += 1
            run(isSchemeChar)
            guard hasPrefix(s, "://", at: i) else { return nil }
            i += 3
            run(isURLChar)
            return i
        case .relative:
            guard hasPrefix(s, "//", at: i) else { return nil }
            i += 2
            let label = i
            run { isAsciiLetter($0) || isDigit($0) || $0 == "-" }
            guard i > label, take(".") else { return nil }
            run(isURLChar)
            return i
        case .email:
            run { isAsciiLetter($0) || isDigit($0) || "._%+-".unicodeScalars.contains($0) }
            guard i > start, take("@") else { return nil }
            let domain = i
            run { isAsciiLetter($0) || isDigit($0) || $0 == "." || $0 == "-" }
            // Backtrack to the last "." that has a domain character before it
            // and two letters after it; the letters then run on greedily.
            var dot = i - 3
            while dot > domain {
                if s[dot] == ".", isAsciiLetter(s[dot + 1]), isAsciiLetter(s[dot + 2]) {
                    i = dot + 1
                    run(isAsciiLetter)
                    return i
                }
                dot -= 1
            }
            return nil
        case .uuid:
            for (n, width) in [8, 4, 4, 4, 12].enumerated() {
                if n > 0 && !take("-") { return nil }
                for _ in 0..<width {
                    guard i < s.count, isHex(s[i]) else { return nil }
                    i += 1
                }
            }
            return i
        case .ipv4:
            for n in 0..<4 {
                if n > 0 && !take(".") { return nil }
                let digits = i
                while i - digits < 3 && i < s.count && isDigit(s[i]) { i += 1 }
                if i == digits { return nil }
            }
            return i
        case .digits:
            run(isDigit)
            return i - start >= 6 ? i : nil
        case .path:
            var end: Int?
            while i < s.count && !" ():".unicodeScalars.contains(s[i]) {
                if s[i] == "/" { end = i + 1 }
                i += 1
            }
            return end
        case .query:
            guard take("?") else { return nil }
            run { !" :()".unicodeScalars.contains($0) }
            return i
        }
    }

    /// One left-to-right pass: at each position the first token that matches
    /// wins, is replaced, and scanning resumes after it.
    private static func replacing(_ input: String, _ tokens: [Token], _ replace: (Token, String) -> String) -> String {
        let s = Array(input.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        scan: while i < s.count {
            for token in tokens {
                if let end = match(token, s, at: i) {
                    out.append(contentsOf: replace(token, text(s[i..<end])).unicodeScalars)
                    i = end
                    continue scan
                }
            }
            out.append(s[i])
            i += 1
        }
        return String(out)
    }

    /// cleanText, then URLs become their host (or "<url>"), emails "<email>",
    /// UUIDs "<id>", IPv4 "<ip>", and runs of 6+ digits "<n>". Not truncated.
    static func sanitizeMessage(_ v: Any?) -> String {
        replacing(cleanText(v), messageTokens) { token, m in
            switch token {
            case .email: return "<email>"
            case .uuid: return "<id>"
            case .ipv4: return "<ip>"
            case .digits: return "<n>"
            default: return hostOf(m) ?? "<url>"
            }
        }
    }

    /// The text after the last "/" of the path (before any "?" or "#").
    private static func basenameOfURL(_ u: String) -> String {
        let path = u.unicodeScalars.prefix { $0 != "?" && $0 != "#" }
        return text(path.reversed().prefix { $0 != "/" }.reversed())
    }

    private static func sanitizeFrame(_ line: String) -> String {
        replacing(cleanText(line), frameTokens) { token, m in
            switch token {
            case .url, .relative:
                if let host = hostOf(m) { return host }
                let base = basenameOfURL(m)
                return base.isEmpty ? "<url>" : base
            case .email: return "<email>"
            case .uuid: return "<id>"
            case .ipv4: return "<ip>"
            default: return ""  // directory prefix or query string
            }
        }
    }

    /// First 5 frames, one per line: the engine header line (`errName` or
    /// `errName: …`) is dropped, URLs become hosts, directories and query
    /// strings are removed, emails, UUIDs and IPs are masked. At most 800 code
    /// points; nil when nothing is left.
    static func sanitizeStack(_ stack: Any?, errName: String?) -> String? {
        guard let raw = string(stack) else { return nil }
        var lines = raw.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimAscii(text($0.filter { $0 != "\r" })) }
            .filter { !$0.isEmpty }
        if let name = errName, !name.isEmpty, let first = lines.first,
           same(first, name) || first.unicodeScalars.starts(with: (name + ":").unicodeScalars) {
            lines.removeFirst()
        }
        let frames = lines.prefix(Limits.stackFrames).map(sanitizeFrame).filter { !$0.isEmpty }
        if frames.isEmpty { return nil }
        return truncateUnicode(frames.joined(separator: "\n"), Limits.stack)
    }

    // MARK: Field normalizers

    /// A code that fails the registry format becomes "client.code.invalid".
    static func normalizeCode(_ code: Any?) -> String {
        guard let s = string(code), s.utf16.count <= Limits.codeMax else { return invalidCode }
        let parts = s.unicodeScalars.split(separator: ".", omittingEmptySubsequences: false)
        let valid = parts.count == 3 && parts.enumerated().allSatisfy { n, part in
            guard let first = part.first, ("a"..."z").contains(first) else { return false }
            return part.dropFirst().allSatisfy { c in
                ("a"..."z").contains(c) || isDigit(c) || (n > 0 && c == "_")
            }
        }
        return valid ? s : invalidCode
    }

    /// Exact match against the component list, else "unknown".
    static func normalizeComponent(_ component: Any?) -> String {
        member(component, of: components) ?? unknown
    }

    /// Exact match against fatal | error | warn, else "error".
    static func normalizeSeverity(_ severity: Any?) -> String {
        member(severity, of: severities) ?? "error"
    }

    private static func isInteger(_ d: Double) -> Bool {
        d.isFinite && d.rounded(.towardZero) == d
    }

    /// HTTP status as exactly three digits, else nil.
    static func normalizeHttpStatus(_ v: Any?) -> String? {
        switch value(v) {
        case .number(let d):
            return isInteger(d) && (100...999).contains(d) ? String(Int(d)) : nil
        case .string(let s):
            let t = trimAscii(s)
            return t.unicodeScalars.count == 3 && t.unicodeScalars.allSatisfy(isDigit) ? t : nil
        default:
            return nil
        }
    }

    /// Integer numbers or strings; cleaned and cut to 32 code points.
    static func normalizeZoneId(_ v: Any?) -> String? {
        let s: String
        switch value(v) {
        case .number(let d):
            // Number.isSafeInteger
            guard isInteger(d), abs(d) <= 9_007_199_254_740_991 else { return nil }
            s = String(Int64(d))
        case .string(let raw):
            s = raw
        default:
            return nil
        }
        return cleanBounded(s, Limits.zoneId)
    }

    private static func cleanBounded(_ v: Any?, _ max: Int) -> String? {
        guard string(v) != nil else { return nil }
        let t = cleanText(v)
        return t.isEmpty ? nil : truncateUnicode(t, max)
    }

    // MARK: Flags and sampling

    private static let falseWords = ["false", "0", "no", "off"]

    /// Kill-switch coercion (FAILURES.md 5.3): a boolean as is; a number is on
    /// unless 0; a string is on unless false/0/no/off after ASCII trim and
    /// ASCII lower case; anything else gives `dflt`.
    static func coerceFlag(_ v: Any?, _ dflt: Bool = true) -> Bool {
        switch value(v) {
        case .bool(let b): return b
        case .number(let d): return d != 0
        case .string(let s): return !falseWords.contains { same($0, asciiLower(trimAscii(s))) }
        case .other: return dflt
        }
    }

    /// The digits of a rate that matches `^\+?([0-9]+(\.[0-9]*)?|\.[0-9]+)$`,
    /// as "<int>.<frac>" with no sign and no empty side, else nil.
    private static func rateText(_ s: String) -> String? {
        var cps = Array(s.unicodeScalars)
        if cps.first == "+" { cps.removeFirst() }
        let parts = cps.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(isDigit) }),
              !parts[0].isEmpty || parts.count == 2 && !parts[1].isEmpty
        else { return nil }
        let whole = parts[0].isEmpty ? "0" : text(parts[0])
        let fraction = parts.count == 2 && !parts[1].isEmpty ? text(parts[1]) : "0"
        return whole + "." + fraction
    }

    /// FAILURES_SAMPLE_RATE (FAILURES.md 5.4): a finite number, or a plain
    /// decimal string, clamped to [0, 1]. Anything else is 1.
    static func coerceRate(_ v: Any?) -> Double {
        var n: Double?
        switch value(v) {
        case .number(let d):
            n = d.isFinite ? d : nil
        case .string(let s):
            n = rateText(trimAscii(s)).flatMap { Double($0) }
        default:
            n = nil
        }
        guard let rate = n else { return 1 }
        return min(1, max(0, rate))
    }

    /// FNV-1a 32-bit over the UTF-8 bytes of a string ("" for non-strings).
    static func fnv1a32(_ v: Any?) -> UInt32 {
        var h: UInt32 = 0x811C_9DC5
        for b in (string(v) ?? "").utf8 {
            h ^= UInt32(b)
            h = h &* 0x0100_0193
        }
        return h
    }

    /// Session sampling: fnv1a32(uid + ":failures") / 2^32 < rate.
    static func isSampled(uid: Any?, rate: Double) -> Bool {
        if rate >= 1 { return true }
        if rate <= 0 { return false }
        return Double(fnv1a32((string(uid) ?? "") + ":failures")) / 4_294_967_296 < rate
    }

    // MARK: Dedupe

    /// action|label|errName|first 64 code points of the sanitized, uncut message.
    static func dedupeKey(action: String, label: String, errName: String?, msgFull: String) -> String {
        [action, label, errName ?? "", firstCodePoints(msgFull, Limits.msgKey)].joined(separator: "|")
    }

    /// The sanitized `message` and error message joined with ": ", the error
    /// message left out when it equals the message (FAILURES.md 7.5).
    static func fullMessage(_ input: Input) -> String {
        let fromMessage = sanitizeMessage(input.message)
        let fromError = sanitizeMessage(input.errMessage)
        let parts = same(fromError, fromMessage) ? [fromMessage] : [fromMessage, fromError]
        return parts.filter { !$0.isEmpty }.joined(separator: ": ")
    }

    // MARK: Event building

    private static func jsonString(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0..<0x20:
                let hex = String(c.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }

    /// Canonical JSON of the event (fixed key order, no whitespace, minimal
    /// escaping, "/" and non-ASCII literal). Its UTF-8 length is what the
    /// 2048-byte budget measures. Never use JSONSerialization for this: it
    /// escapes "/".
    static func canonicalJson(_ event: Event) -> String {
        let attributes = attributeKeys.compactMap { key in
            event.attributes[key].map { jsonString(key) + ":" + jsonString($0) }
        }
        return "{\"event\":" + jsonString(event.event)
            + ",\"action\":" + jsonString(event.action)
            + ",\"label\":" + jsonString(event.label)
            + ",\"attributes\":{" + attributes.joined(separator: ",") + "}"
            + ",\"uid\":" + jsonString(event.uid)
            + ",\"createdTime\":" + String(event.createdTime) + "}"
    }

    static func eventByteSize(_ event: Event) -> Int {
        canonicalJson(event).utf8.count
    }

    /// Normalized fields of one emitted failure.
    struct Fields {
        var action: String
        var label: String
        var severity: String
        var errName: String?
        var msg: String?
        var stack: String?
        var httpStatus: String?
        var host: String?
        var zoneId: String?
        var seq: Int
        var repeatCount: Int
        var capped: Bool
    }

    /// Builds the wire event and applies the size budget: over 2048 bytes drop
    /// the stack, then cut msg to 80, then drop msg, then send it as is.
    static func buildFailureEvent(_ fields: Fields, context: Context, uid: Any?, now: Int64) -> Event {
        var a: [String: String] = [
            "code": cleanBounded(context.partnerCode, Limits.partnerCode) ?? unknown,
            "client": string(context.client).flatMap { $0.isEmpty ? nil : $0 } ?? unknown,
            "clientVersion": cleanBounded(context.clientVersion, Limits.clientVersion) ?? unknown,
            "severity": fields.severity,
            "fv": contractVersion,
            "seq": String(fields.seq),
            "repeat": String(fields.repeatCount),
        ]
        a["errName"] = fields.errName
        a["msg"] = fields.msg
        a["stack"] = fields.stack
        a["httpStatus"] = fields.httpStatus
        a["host"] = fields.host
        a["zoneId"] = fields.zoneId
        a["wrapper"] = member(context.wrapper, of: wrappers)
        a["release"] = cleanBounded(context.release, Limits.release)
        a["capped"] = fields.capped ? "1" : nil

        var event = Event(event: eventName, action: fields.action, label: fields.label,
                          attributes: a, uid: string(uid) ?? "", createdTime: now)
        let over = { eventByteSize(event) > Limits.eventBytes }
        if over() && event.attributes["stack"] != nil { event.attributes["stack"] = nil }
        if over(), let msg = event.attributes["msg"] { event.attributes["msg"] = truncateUnicode(msg, Limits.msgBudget) }
        if over() && event.attributes["msg"] != nil { event.attributes["msg"] = nil }
        return event
    }

    // MARK: The gate

    private static func touch(_ keys: [KeyEntry], _ entry: KeyEntry) -> [KeyEntry] {
        keys.filter { !same($0.key, entry.key) } + [entry]
    }

    /// The whole decision (FAILURES.md 5.2) as a pure function. `event` is nil
    /// when dropped, and `reason` names the gate that dropped it.
    static func decide(state: State, input: Input, context: Context, uid: Any?, now: Int64) -> Decision {
        func drop(_ reason: Reason, _ next: State = state) -> Decision {
            Decision(state: next, event: nil, flushNow: false, reason: reason)
        }

        if !coerceFlag(context.eventsEnabled, true) { return drop(.eventsDisabled) }
        if !coerceFlag(context.failuresEnabled, true) { return drop(.failuresDisabled) }

        let action = normalizeCode(input.code)
        let label = normalizeComponent(input.component)
        let severity = normalizeSeverity(input.severity)

        if severity != "fatal" && !isSampled(uid: uid, rate: coerceRate(context.failuresSampleRate)) {
            return drop(.sampledOut)
        }
        if state.sessionCount >= Limits.sessionEmits { return drop(.sessionCapped) }

        let errName = cleanBounded(input.errName, Limits.errName)
        let msgFull = fullMessage(input)
        let key = dedupeKey(action: action, label: label, errName: errName, msgFull: msgFull)
        let existing = state.keys.first { same($0.key, key) }
        if let existing = existing {
            if existing.emits >= Limits.perKeyEmits {
                return drop(.keyCapped, State(sessionCount: state.sessionCount, keys: touch(state.keys, existing)))
            }
            // In doubles, as the reference does: no overflow for any clock value.
            if Double(now) - Double(existing.lastEmitAt) < Double(Limits.dedupeWindowMs) {
                var bumped = existing
                bumped.suppressed += 1
                return drop(.deduped, State(sessionCount: state.sessionCount, keys: touch(state.keys, bumped)))
            }
        }

        let seq = state.sessionCount + 1
        let entry = KeyEntry(key: key, lastEmitAt: now, suppressed: 0, emits: (existing?.emits ?? 0) + 1)
        let keys = Array(touch(state.keys, entry).suffix(Limits.lruSize))

        let fields = Fields(
            action: action,
            label: label,
            severity: severity,
            errName: errName,
            msg: msgFull.isEmpty ? nil : truncateUnicode(msgFull, Limits.msg),
            stack: sanitizeStack(input.stack, errName: errName),
            httpStatus: normalizeHttpStatus(input.httpStatus),
            host: hostOf(input.url).map { truncateUnicode($0, Limits.host) },
            zoneId: normalizeZoneId(input.zoneId),
            seq: seq,
            repeatCount: (existing?.suppressed ?? 0) + 1,
            capped: seq == Limits.sessionEmits
        )
        return Decision(
            state: State(sessionCount: seq, keys: keys),
            event: buildFailureEvent(fields, context: context, uid: uid, now: now),
            flushNow: seq == 1 || severity == "fatal",
            reason: nil
        )
    }

    /// The debug echo line (FAILURES.md 2):
    /// `[Sellwild] failure <action> <label> <severity> <reason or "sent"> <msg>`.
    static func echoLine(input: Input, decision: Decision) -> String {
        let msg = truncateUnicode(fullMessage(input), Limits.msg)
        let parts = [
            "[Sellwild] failure", normalizeCode(input.code), normalizeComponent(input.component),
            normalizeSeverity(input.severity), decision.reason?.rawValue ?? "sent",
        ]
        return (msg.isEmpty ? parts : parts + [msg]).joined(separator: " ")
    }
}
