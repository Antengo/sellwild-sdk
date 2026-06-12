import Foundation

// MARK: - Data Models

public struct SellwildPhoto: Codable {
    // Only `url` is guaranteed by the static cache; `thumbUrl` is only
    // populated by the legacy RPC endpoint. Keep both optional so a single
    // missing field doesn't drop the whole listing during decode.
    public let url: String
    public let thumbUrl: String?
    public let background: String?
}

public struct SellwildUser: Codable {
    // The cache trims this down to {id, firstName, lastName, trustLevel}.
    // The legacy RPC adds {username, membershipType}. Everything except `id`
    // is optional so a partial payload still decodes.
    public let id: String
    public let firstName: String?
    public let lastName: String?
    public let username: String?
    public let membershipType: String?
    public let trustLevel: String?
}

public struct SellwildListing: Codable, Identifiable {
    public let id: String
    public let status: String
    public let title: String
    public let text: String?
    public let url: String?
    public let categoryId: String?
    public let currency: String?
    public let price: String?
    public let strikePrice: String?
    public let has_photo: Bool?
    public let photos: [SellwildPhoto]?
    public let createdDate: String?
    /// `shippable` arrives as `Bool` on the cache endpoint and `String`
    /// ("0"/"1") on the legacy RPC endpoint. We surface it as `Bool?` and
    /// coerce both shapes in the custom decoder below.
    public let shippable: Bool?
    public let dataSourceId: String?
    public let user: SellwildUser?
    public let distance: Double?
    /// Off-platform destination ("remote_url" on the cache payload). When set
    /// this is the URL the listing card should open. Falls back to `url`, then
    /// to a Sellwild item-detail link built from `id`.
    public let remoteUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, status, title, text, url, categoryId, currency, price,
             strikePrice, has_photo, photos, createdDate, shippable,
             dataSourceId, user, distance
        case remoteUrl = "remote_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` and `status` ship as strings on RPC but sometimes as ints on
        // the cache — accept either to avoid silent drops.
        self.id        = try Self.decodeFlexibleString(c, key: .id) ?? ""
        self.status    = try Self.decodeFlexibleString(c, key: .status) ?? ""
        self.title     = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.text      = try c.decodeIfPresent(String.self, forKey: .text)
        self.url       = try c.decodeIfPresent(String.self, forKey: .url)
        self.categoryId   = try Self.decodeFlexibleString(c, key: .categoryId)
        self.currency     = try c.decodeIfPresent(String.self, forKey: .currency)
        self.price        = try Self.decodeFlexibleString(c, key: .price)
        self.strikePrice  = try Self.decodeFlexibleString(c, key: .strikePrice)
        self.has_photo    = try c.decodeIfPresent(Bool.self, forKey: .has_photo)
        self.photos       = try c.decodeIfPresent([SellwildPhoto].self, forKey: .photos)
        self.createdDate  = try c.decodeIfPresent(String.self, forKey: .createdDate)
        self.shippable    = try Self.decodeFlexibleBool(c, key: .shippable)
        self.dataSourceId = try Self.decodeFlexibleString(c, key: .dataSourceId)
        self.user         = try c.decodeIfPresent(SellwildUser.self, forKey: .user)
        self.distance     = try c.decodeIfPresent(Double.self, forKey: .distance)
        self.remoteUrl    = try c.decodeIfPresent(String.self, forKey: .remoteUrl)
    }

    /// The URL a listing card should open when tapped. Prefers `remoteUrl`
    /// (off-platform partner URL), then `url`, then a Sellwild deep link
    /// derived from `id`.
    public var tapURL: String? {
        if let s = remoteUrl, !s.isEmpty { return s }
        if let s = url, !s.isEmpty { return s }
        return id.isEmpty ? nil : "https://sellwild.com/itemDetail/\(id)"
    }

    private static func decodeFlexibleString(
        _ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
    ) throws -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let n = try? c.decodeIfPresent(Int.self,    forKey: key) { return String(n) }
        if let n = try? c.decodeIfPresent(Double.self, forKey: key) { return String(n) }
        return nil
    }

    private static func decodeFlexibleBool(
        _ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
    ) throws -> Bool? {
        if let b = try? c.decodeIfPresent(Bool.self, forKey: key)  { return b }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            return s == "1" || s.lowercased() == "true"
        }
        if let n = try? c.decodeIfPresent(Int.self, forKey: key)   { return n != 0 }
        return nil
    }

    public var displayPrice: String? {
        guard let priceStr = price,
              let value = Double(priceStr),
              value > 0 else { return nil }
        return String(format: "%.0f", value)
    }

    public var primaryPhoto: SellwildPhoto? {
        photos?.first
    }
}

public struct SellwildListingsResponse {
    public let listings: [SellwildListing]
    public let config: [String: Any]
    public let widgetCacheVersionId: String?
}

// MARK: - API Client

public final class SellwildAPIClient {

    private let session: URLSession
    private let listingCache = NSCache<NSString, ListingsCacheEntry>()

    public static let shared = SellwildAPIClient()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Fetch Listings

    public func fetchListings(
        config: SellwildConfig,
        completion: @escaping (Result<SellwildListingsResponse, Error>) -> Void
    ) {
        let listingsUrlString = config.effectiveListingsUrl
        guard let url = URL(string: listingsUrlString) else {
            completion(.failure(SellwildError.invalidURL(listingsUrlString)))
            return
        }

        let cacheKey = url.absoluteString + "|" + config.partnerCode as NSString
        if let cached = listingCache.object(forKey: cacheKey) {
            completion(.success(cached.response))
            return
        }

        // Two endpoint shapes are supported:
        //
        //   1. CDN cache (`cache.sellwild.com/listings-*` and any other URL
        //      that returns the cached `{ result: { rs: [...] } }` payload as
        //      static JSON). These are GETs and may come back gzip-encoded —
        //      `URLSession` handles `Accept-Encoding` and decompression for us
        //      when we don't override the header.
        //
        //   2. Legacy Zend\Json\Server JSON-RPC endpoint (`supplyListing/rpc`)
        //      which requires a POST with a JSON-RPC envelope.
        //
        // We pick by host: anything pointed at `cache.sellwild.com` is treated
        // as a static cache URL; everything else falls back to the RPC POST.
        var request = URLRequest(url: url)
        let isStaticCache = (url.host ?? "").contains("cache.sellwild.com")

        if isStaticCache {
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        } else {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let envelope: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "getFeaturedListingsForPartnerWidget",
                "params": [config.partnerCode, "regular"],
                "id": 1,
            ]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: envelope)
            } catch {
                completion(.failure(error))
                return
            }
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(SellwildError.noData)) }
                return
            }
            do {
                let parsed = try self?.parseListingsResponse(data: data)
                    ?? SellwildListingsResponse(listings: [], config: [:], widgetCacheVersionId: nil)

                let entry = ListingsCacheEntry(response: parsed)
                self?.listingCache.setObject(entry, forKey: cacheKey)

                DispatchQueue.main.async { completion(.success(parsed)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    @available(iOS 15, macOS 12, *)
    public func fetchListings(config: SellwildConfig) async throws -> SellwildListingsResponse {
        try await withCheckedThrowingContinuation { continuation in
            fetchListings(config: config) { result in
                continuation.resume(with: result)
            }
        }
    }

    // MARK: Send Analytics Event

    public func sendEvent(_ event: SellwildEvent) {
        let url = URL(string: "https://tbd4rmdvjk.execute-api.us-east-1.amazonaws.com/dev/events/queue")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let body = try? JSONEncoder().encode([event]) else { return }
        request.httpBody = body

        session.dataTask(with: request).resume()
    }

    // MARK: Private

    private func parseListingsResponse(data: Data) throws -> SellwildListingsResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SellwildError.invalidResponse
        }

        let result = (json["result"] as? [String: Any]) ?? json
        let rs = result["rs"] as? [[String: Any]] ?? []
        let config = result["config"] as? [String: Any] ?? [:]
        let versionId = result["widgetCacheVersionId"] as? String

        let decoder = JSONDecoder()
        let listings: [SellwildListing] = try rs.compactMap { dict in
            let itemData = try JSONSerialization.data(withJSONObject: dict)
            return try? decoder.decode(SellwildListing.self, from: itemData)
        }

        return SellwildListingsResponse(
            listings: listings,
            config: config,
            widgetCacheVersionId: versionId
        )
    }

    public func clearCache() {
        listingCache.removeAllObjects()
    }
}

// MARK: - Event

public struct SellwildEvent: Codable {
    public let event: String
    public let action: String?
    public let label: String?
    public let uid: String
    public let createdTime: Int64

    public init(event: String, action: String? = nil, label: String? = nil) {
        self.event = event
        self.action = action
        self.label = label
        self.uid = SellwildSession.shared.uid
        self.createdTime = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - Session

public final class SellwildSession {
    public static let shared = SellwildSession()
    private let key = "_sw_uid"

    public lazy var uid: String = {
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
}

// MARK: - Errors

public enum SellwildError: LocalizedError {
    case invalidURL(String)
    case noData
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .noData:              return "No data received from server"
        case .invalidResponse:     return "Invalid response format"
        }
    }
}

// MARK: - Cache Entry

private final class ListingsCacheEntry: NSObject {
    let response: SellwildListingsResponse
    init(response: SellwildListingsResponse) { self.response = response }
}
