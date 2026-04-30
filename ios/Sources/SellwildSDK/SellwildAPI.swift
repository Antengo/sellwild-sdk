import Foundation

// MARK: - Data Models

public struct SellwildPhoto: Codable {
    public let url: String
    public let thumbUrl: String
    public let background: String?
}

public struct SellwildUser: Codable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let username: String
    public let membershipType: String
    public let trustLevel: String
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
    public let shippable: String?
    public let dataSourceId: String?
    public let user: SellwildUser?
    public let distance: Double?

    public var displayPrice: String? {
        guard let priceStr = price,
              let value = Double(priceStr),
              value > 0 else { return nil }
        return value.formatted(.number.precision(.fractionLength(0)))
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
        guard let url = URL(string: config.listingsUrl) else {
            completion(.failure(SellwildError.invalidURL(config.listingsUrl)))
            return
        }

        let cacheKey = url.absoluteString + "|" + config.partnerCode as NSString
        if let cached = listingCache.object(forKey: cacheKey) {
            completion(.success(cached.response))
            return
        }

        // Sellwild's listings endpoint is a Zend\Json\Server JSON-RPC endpoint
        // (POST /supplyListing/rpc). The SDK targets that contract directly —
        // this couples it to Sellwild's RPC surface. Other publishers hosting
        // their own GET JSON endpoint won't be served by this client.
        var request = URLRequest(url: url)
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
