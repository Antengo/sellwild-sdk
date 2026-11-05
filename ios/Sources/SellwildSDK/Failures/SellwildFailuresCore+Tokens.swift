import Foundation

/// The email and JavaScriptCore-frame alternatives of the sanitizing patterns
/// (FAILURES.md 7.4, 7.5), matched by hand with the regex's greedy semantics.
extension SellwildFailuresCore {

    private static func isLocalChar(_ c: Unicode.Scalar) -> Bool {
        isAsciiLetter(c) || isDigit(c) || "._%+-".unicodeScalars.contains(c)
    }

    private static func isDomainChar(_ c: Unicode.Scalar) -> Bool {
        isAsciiLetter(c) || isDigit(c) || c == "." || c == "-"
    }

    /// `[A-Za-z0-9._%+-]+@` then the greedy `[A-Za-z0-9.-]*` run after it:
    /// (index after "@", end of the run), or nil.
    private static func localAndDomain(_ s: [Unicode.Scalar], at start: Int) -> (domain: Int, end: Int)? {
        var i = start
        while i < s.count && isLocalChar(s[i]) { i += 1 }
        guard i > start, i < s.count, s[i] == "@" else { return nil }
        let domain = i + 1
        i = domain
        while i < s.count && isDomainChar(s[i]) { i += 1 }
        return (domain, i)
    }

    /// email `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}`: the end
    /// (exclusive) of the match at `start`, or nil.
    static func matchEmail(_ s: [Unicode.Scalar], at start: Int) -> Int? {
        guard let (domain, end) = localAndDomain(s, at: start) else { return nil }
        // Backtrack to the last "." that has a domain character before it
        // and two letters after it; the letters then run on greedily.
        var dot = end - 3
        while dot > domain {
            if s[dot] == ".", isAsciiLetter(s[dot + 1]), isAsciiLetter(s[dot + 2]) {
                var i = dot + 1
                while i < s.count && isAsciiLetter(s[i]) { i += 1 }
                return i
            }
            dot -= 1
        }
        return nil
    }

    /// React Native JavaScriptCore frame (stacks only, kept as is):
    /// `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(?:js)?bundle(?![A-Za-z0-9.-])(?::[0-9]+){0,2}`.
    /// The lookahead means "bundle" must end the greedy domain run, after "."
    /// or ".js" and at least one domain character.
    static func matchJSCFrame(_ s: [Unicode.Scalar], at start: Int) -> Int? {
        guard let (domain, end) = localAndDomain(s, at: start),
              (end - 7 > domain && hasPrefix(s, ".bundle", at: end - 7))
                || (end - 9 > domain && hasPrefix(s, ".jsbundle", at: end - 9)) else { return nil }
        var i = end
        for _ in 0..<2 {
            guard i + 1 < s.count, s[i] == ":", isDigit(s[i + 1]) else { break }
            i += 1
            while i < s.count && isDigit(s[i]) { i += 1 }
        }
        return i
    }
}
