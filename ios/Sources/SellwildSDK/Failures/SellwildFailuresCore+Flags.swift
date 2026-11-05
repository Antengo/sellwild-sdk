import Foundation

/// Kill switches, sample rates and session sampling (FAILURES.md 5.3-5.5).
extension SellwildFailuresCore {

    // MARK: Flags and sampling

    static let falseWords = ["false", "0", "no", "off"]

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
    static func rateText(_ s: String) -> String? {
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
        guard let rate = parseRate(v) else { return 1 }
        return min(1, max(0, rate))
    }

    /// A finite number, or a plain decimal string, unclamped; anything else nil.
    static func parseRate(_ v: Any?) -> Double? {
        switch value(v) {
        case .number(let d):
            return d.isFinite ? d : nil
        case .string(let s):
            return rateText(trimAscii(s)).flatMap { Double($0) }
        default:
            return nil
        }
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
}
