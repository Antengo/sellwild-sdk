import Foundation

/// fv 2 of the pure core (FAILURES.md 3.3 item 4, 7.4, 7.7): the input cap
/// and the call-site context (`ctx.<key>`).
extension SellwildFailuresCore {

    /// The first `max` UTF-16 units of `text` (FAILURES.md 3.3 item 4). When
    /// the cut splits a surrogate pair, the text ends in U+FFFD: that is what
    /// cleanText makes of the lone high surrogate TS and Kotlin keep, and a
    /// Swift string cannot hold one.
    static func capInput(_ text: String, max: Int) -> String {
        guard text.utf16.count > max else { return text }
        var units = 0
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let width = scalar.utf16.count
            guard units + width <= max else {
                if units < max { kept.append("\u{FFFD}") }
                break
            }
            kept.append(scalar)
            units += width
        }
        return String(kept)
    }

    /// Up to 6 decimals, rounded half away from zero on the exact value (JS
    /// `toFixed(6)`), trailing zeros and a bare point removed; "-0" → "0".
    /// printf rounds an exact tie (0.0078125) to even, so it rounds by hand
    /// from 40 digits.
    static func formatDecimal(_ v: Double) -> String {
        let digits = String(format: "%.40f", abs(v))
        let parts = digits.split(separator: ".", maxSplits: 1)
        var number = Array(parts[0] + parts[1].prefix(6))
        // "%.40f" always writes 40 decimals, so the seventh is there.
        let roundUp = parts[1][parts[1].index(parts[1].startIndex, offsetBy: 6)] >= "5"
        var i = number.count - 1
        var carry = roundUp
        while carry && i >= 0 {
            if number[i] == "9" {
                number[i] = "0"
                i -= 1
            } else {
                number[i] = Character(UnicodeScalar(number[i].asciiValue! + 1))
                carry = false
            }
        }
        if carry { number.insert("1", at: 0) }
        let intPart = String(number.dropLast(6))
        var frac = String(number.suffix(6))
        while frac.hasSuffix("0") { frac.removeLast() }
        let body = frac.isEmpty ? intPart : intPart + "." + frac
        return v < 0 && body != "0" ? "-" + body : body
    }

    /// A call-site context value as text: a string is cut to 1000 UTF-16 units
    /// and sanitized like msg; a safe integer is written in decimal; another
    /// finite number with |v| < 1e15 is written with up to 6 decimals. Cut to
    /// 200 code points. Anything else, or empty, → nil.
    static func normalizeCtxValue(_ v: Any?) -> String? {
        let s: String?
        switch value(v) {
        case .string(let raw):
            s = sanitizeMessage(capInput(raw, max: Limits.ctxInput))
        case .number(let d) where d.isFinite:
            if d.rounded(.towardZero) == d && abs(d) <= 9_007_199_254_740_991 {
                s = String(Int64(d))
            } else if abs(d) < 1e15 {
                s = formatDecimal(d)
            } else {
                s = nil
            }
        default:
            s = nil
        }
        guard let s, !s.isEmpty else { return nil }
        return truncateUnicode(s, Limits.ctxValue)
    }

    /// The call-site context as attributes: keys matching
    /// `^[a-z][a-zA-Z0-9_]{0,31}$` whose value normalizes to text, sorted by
    /// key (code point order), the first 8 kept, each as `ctx.<key>`.
    /// Anything but a string-keyed dictionary → none.
    static func normalizeCtx(_ context: Any?) -> [(String, String)] {
        guard let map = context as? [String: Any] else { return [] }
        let keys = map.keys.filter(isCtxKey)
            .sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
        let pairs = keys.compactMap { key in normalizeCtxValue(map[key]).map { (ctxPrefix + key, $0) } }
        return Array(pairs.prefix(Limits.ctxKeys))
    }

    private static func isCtxKey(_ key: String) -> Bool {
        let scalars = Array(key.unicodeScalars)
        guard let first = scalars.first, ("a"..."z").contains(first), scalars.count <= 32 else { return false }
        return scalars.dropFirst().allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_"
        }
    }
}
