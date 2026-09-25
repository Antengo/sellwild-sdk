import Foundation

/// Tolerant reader for the CDN `S2S_CONFIG` key (the Prebid.js `s2sConfig`).
///
/// The CMS ships it as a JS object-literal STRING, e.g.
/// `"[{ accountId: 'weatherbug', endpoint: { p1Consent: 'https://…' }, timeout: 1300, }]"`
/// — unquoted keys, single quotes, maybe trailing commas — so a plain
/// `[String: Any]` cast / `JSONSerialization` parse always failed. This accepts
/// an already-decoded object or array, a real JSON string, or that JS-literal
/// form, and extracts the first entry's account id, auction endpoint and timeout.
struct SellwildS2SConfig: Equatable {
    let accountId: String?
    /// Prebid Server auction URL. Prebid.js allows `endpoint` to be a string or
    /// `{ p1Consent, noP1Consent }`; the consented URL wins.
    let endpoint: String?
    /// S2S auction timeout in ms.
    let timeout: Int?

    /// Parse the raw `S2S_CONFIG` value. Returns nil when it is absent, not
    /// parseable, or carries none of the fields we read.
    static func parse(_ raw: Any?) -> SellwildS2SConfig? {
        var value = raw
        if let s = raw as? String {
            guard let data = jsLiteralToJSON(s).data(using: .utf8) else { return nil }
            value = try? JSONSerialization.jsonObject(with: data)
        }
        let entry: [String: Any]?
        switch value {
        case let d as [String: Any]: entry = d
        case let a as [Any]: entry = a.first as? [String: Any]
        default: entry = nil
        }
        guard let entry else { return nil }

        let result = SellwildS2SConfig(
            accountId: nonEmpty(entry["accountId"]) ?? nonEmpty(entry["account"]),
            endpoint: endpointURL(entry["endpoint"]) ?? nonEmpty(entry["url"]),
            timeout: positiveInt(entry["timeout"])
        )
        if result.accountId == nil, result.endpoint == nil, result.timeout == nil { return nil }
        return result
    }

    private static func nonEmpty(_ v: Any?) -> String? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func endpointURL(_ v: Any?) -> String? {
        if let d = v as? [String: Any] {
            return nonEmpty(d["p1Consent"]) ?? nonEmpty(d["noP1Consent"])
        }
        return nonEmpty(v)
    }

    private static func positiveInt(_ v: Any?) -> Int? {
        let n: Int?
        switch v {
        case let x as NSNumber: n = x.intValue
        case let s as String: n = Int(s)
        default: n = nil
        }
        guard let n, n > 0 else { return nil }
        return n
    }

    /// Rewrite a JS object/array literal into JSON: quote bare keys, turn
    /// single-quoted strings into double-quoted ones (re-escaping as needed),
    /// map `undefined` → `null`, and drop trailing commas and comments. Valid
    /// JSON passes through unchanged. Not a full JS parser — just enough for
    /// CMS-authored config literals; anything else fails the JSON parse after.
    static func jsLiteralToJSON(_ s: String) -> String {
        let c = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        func isIdentStart(_ ch: Unicode.Scalar) -> Bool {
            ch == "_" || ch == "$" || CharacterSet.letters.contains(ch)
        }
        func isIdentPart(_ ch: Unicode.Scalar) -> Bool {
            isIdentStart(ch) || CharacterSet.decimalDigits.contains(ch)
        }
        func nextSignificant(from j: Int) -> Int {
            var k = j
            while k < c.count, CharacterSet.whitespacesAndNewlines.contains(c[k]) { k += 1 }
            return k
        }
        while i < c.count {
            let ch = c[i]
            if ch == "\"" || ch == "'" {
                // String literal → double-quoted JSON string.
                out.append("\"")
                i += 1
                while i < c.count, c[i] != ch {
                    let x = c[i]
                    if x == "\\", i + 1 < c.count {
                        // `\'` isn't a JSON escape; everything else carries over.
                        if c[i + 1] == "'" { out.append("'") } else { out.append(x); out.append(c[i + 1]) }
                        i += 2
                        continue
                    }
                    switch x {
                    case "\"": out.append(contentsOf: "\\\"".unicodeScalars)
                    case "\n": out.append(contentsOf: "\\n".unicodeScalars)
                    case "\r": out.append(contentsOf: "\\r".unicodeScalars)
                    case "\t": out.append(contentsOf: "\\t".unicodeScalars)
                    default: out.append(x)
                    }
                    i += 1
                }
                out.append("\"")
                i += 1
            } else if ch == "/", i + 1 < c.count, c[i + 1] == "/" {
                while i < c.count, c[i] != "\n" { i += 1 }
            } else if ch == "/", i + 1 < c.count, c[i + 1] == "*" {
                i += 2
                while i + 1 < c.count, !(c[i] == "*" && c[i + 1] == "/") { i += 1 }
                i += 2
            } else if ch == "," {
                let k = nextSignificant(from: i + 1)
                if k < c.count, c[k] == "}" || c[k] == "]" {
                    i += 1  // trailing comma
                } else {
                    out.append(ch)
                    i += 1
                }
            } else if CharacterSet.decimalDigits.contains(ch) {
                // Number: copy through (keeps `1e3` from being read as a key).
                while i < c.count, isIdentPart(c[i]) || c[i] == "." ||
                        ((c[i] == "+" || c[i] == "-") && (c[i - 1] == "e" || c[i - 1] == "E")) {
                    out.append(c[i])
                    i += 1
                }
            } else if isIdentStart(ch) {
                var j = i
                while j < c.count, isIdentPart(c[j]) { j += 1 }
                let word = String(String.UnicodeScalarView(c[i..<j]))
                let k = nextSignificant(from: j)
                if k < c.count, c[k] == ":" {
                    out.append(contentsOf: "\"\(word)\"".unicodeScalars)
                } else if word == "undefined" {
                    out.append(contentsOf: "null".unicodeScalars)
                } else {
                    out.append(contentsOf: word.unicodeScalars)  // true / false / null
                }
                i = j
            } else {
                out.append(ch)
                i += 1
            }
        }
        return String(out)
    }
}
