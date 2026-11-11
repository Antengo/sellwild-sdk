import Foundation

/// Adds the reader's id to a sellwild.com link as `sw_wuid`, so sellwild.com
/// can match an app reader to their visit (next-sellwild
/// utils/identity-bridge.ts linkWidgetToBrowser). The same rule as the web
/// widget's `withWidgetUid` (sellwild-widget src/core/customizations/urls.ts)
/// and Android's `ReaderLink` (pure).
enum SellwildReaderLink {

    static let param = "sw_wuid"

    /// Unreserved bytes (RFC 3986): every other byte of the id is
    /// percent-encoded.
    private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

    /// `url` with `sw_wuid=<readerId>` as its last query param, any earlier
    /// `sw_wuid` dropped and the #fragment kept. Only https links to
    /// sellwild.com or www.sellwild.com change; any other host, a relative
    /// link or an empty id come back as is. The rest of the URL is kept byte
    /// for byte (no decode and re-encode).
    static func withReaderId(_ url: String, readerId: String?) -> String {
        guard let readerId, !readerId.isEmpty, isSellwildLink(url) else { return url }
        let (beforeFragment, fragment) = split(url, at: "#")
        let (base, query) = split(beforeFragment, at: "?")
        let kept = query.dropFirst().split(separator: "&").filter { pair in
            pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) != param
        }
        let encoded = readerId.utf8.map { byte in
            unreserved.contains(byte) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
        }.joined()
        let params = kept.map(String.init) + ["\(param)=\(encoded)"]
        return "\(base)?\(params.joined(separator: "&"))\(fragment)"
    }

    /// `https://sellwild.com` or `https://www.sellwild.com`, any case, then the
    /// end or one of `/`, `?` or `#`.
    private static func isSellwildLink(_ url: String) -> Bool {
        let lower = url.lowercased()
        for host in ["https://sellwild.com", "https://www.sellwild.com"] where lower.hasPrefix(host) {
            let rest = lower.dropFirst(host.count)
            return rest.first.map { "/?#".contains($0) } ?? true
        }
        return false
    }

    /// The text before the first `separator`, and the rest from it on ("" when
    /// there is none).
    private static func split(_ text: String, at separator: Character) -> (String, String) {
        guard let at = text.firstIndex(of: separator) else { return (text, "") }
        return (String(text[..<at]), String(text[at...]))
    }
}
