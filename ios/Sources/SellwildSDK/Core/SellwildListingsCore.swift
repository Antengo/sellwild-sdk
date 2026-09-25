import Foundation

/// The pure half of the listings fetches in `SellwildAPIClient`: building the
/// request and parsing the body. No I/O and no logging; the client reports
/// what these return, under its own component (`listings` for the primary
/// feed, `localized` for the per-state cache).
enum SellwildListingsCore {

    // MARK: Request

    /// `true` for the static CDN cache (`cache.sellwild.com`), which is a GET.
    /// Every other host gets the legacy JSON-RPC POST.
    static func isStaticCache(_ url: URL) -> Bool {
        (url.host ?? "").contains("cache.sellwild.com")
    }

    /// The JSON-RPC envelope the legacy `supplyListing/rpc` endpoint expects.
    static func rpcEnvelope(partnerCode: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "method": "getFeaturedListingsForPartnerWidget",
            "params": [partnerCode, "regular"],
            "id": 1,
        ]
    }

    /// The listings request for `url`: a GET for the static cache, else the
    /// JSON-RPC POST whose body `encode` writes. Throws what `encode` throws.
    static func request(
        url: URL,
        partnerCode: String,
        encode: ([String: Any]) throws -> Data
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        if isStaticCache(url) {
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        } else {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encode(rpcEnvelope(partnerCode: partnerCode))
        }
        return request
    }

    /// The in-memory cache key: the same URL for another partner is another
    /// entry.
    static func cacheKey(url: URL, partnerCode: String) -> String {
        url.absoluteString + "|" + partnerCode
    }

    // MARK: Parse

    /// Why a body could not be used at all.
    enum ParseFailure: Error {
        /// Not valid JSON (for example an HTML or XML error page).
        case notJSON(Error)
        /// Valid JSON, but not an object.
        case notAnObject
    }

    /// A body that parsed, and what was wrong inside it.
    struct Parsed {
        let response: SellwildListingsResponse
        /// Set when `result.rs` is missing or is not a list of objects. The
        /// response then has no listings, as it always had.
        let rsProblem: String?
        /// Items that could not be decoded (they are left out).
        let dropped: Int
        /// The decode error of the first dropped item.
        let firstDropError: Error?
    }

    /// Parses the cache form `{ "result": { "rs": [...], "config": {...},
    /// "widgetCacheVersionId": "..." } }`, the JSON-RPC envelope (the same
    /// `result`) or a bare `{ "rs": [...] }`. An item that fails to decode is
    /// dropped and counted; the rest are kept in order.
    static func parse(_ data: Data) -> Result<Parsed, ParseFailure> {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .failure(.notJSON(error))
        }
        guard let root = json as? [String: Any] else { return .failure(.notAnObject) }

        let result = (root["result"] as? [String: Any]) ?? root
        let items = result["rs"] as? [[String: Any]]
        let rsProblem: String?
        if items != nil {
            rsProblem = nil
        } else if result["rs"] == nil {
            rsProblem = "result.rs is missing"
        } else {
            rsProblem = "result.rs is not a list of objects"
        }

        let decoder = JSONDecoder()
        var listings: [SellwildListing] = []
        var dropped = 0
        var firstDropError: Error?
        for item in items ?? [] {
            do {
                let itemData = try JSONSerialization.data(withJSONObject: item)
                listings.append(try decoder.decode(SellwildListing.self, from: itemData))
            } catch {
                dropped += 1
                firstDropError = firstDropError ?? error
            }
        }

        let response = SellwildListingsResponse(
            listings: listings,
            config: result["config"] as? [String: Any] ?? [:],
            widgetCacheVersionId: result["widgetCacheVersionId"] as? String
        )
        return .success(Parsed(response: response, rsProblem: rsProblem, dropped: dropped, firstDropError: firstDropError))
    }

    /// The empty response a released client delivers, as it always has.
    static let empty = SellwildListingsResponse(listings: [], config: [:], widgetCacheVersionId: nil)
}
