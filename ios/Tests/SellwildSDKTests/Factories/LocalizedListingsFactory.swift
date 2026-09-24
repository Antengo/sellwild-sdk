import Foundation

/// The localized (per-state) listings integration: the `LOCALIZED_LISTINGS`
/// config object (schema `localized-listings-config`) and a state cache
/// payload (schema `localized-listings-response`).
enum LocalizedListingsFactory {

    static let configSchema = "localized-listings-config"
    static let responseSchema = "localized-listings-response"
    static let defaultConfig = "full"
    /// The real Georgia cache from the sports cache bucket.
    static let defaultResponse = "sports-img-data-sm-webp-ga"

    static func config(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        try configVariant(defaultConfig, overrides)
    }

    static func configVariant(_ name: String, _ overrides: [String: Any] = [:]) throws -> [String: Any] {
        Factory.merge(try Factory.object("fixtures/\(configSchema)/valid/\(name).json"), overrides)
    }

    /// The real state cache. `state` and `listings` replace `result.state`
    /// and `result.rs`.
    static func response(state: String? = nil, listings: [[String: Any]]? = nil) throws -> [String: Any] {
        try responseSample(defaultResponse, state: state, listings: listings)
    }

    static func responseSample(_ name: String, state: String? = nil, listings: [[String: Any]]? = nil) throws -> [String: Any] {
        replacing(try Factory.object("samples/\(responseSchema)/\(name).json"), state: state, listings: listings)
    }

    static func responseVariant(_ name: String, state: String? = nil, listings: [[String: Any]]? = nil) throws -> [String: Any] {
        replacing(try Factory.object("fixtures/\(responseSchema)/valid/\(name).json"), state: state, listings: listings)
    }

    static func configVariantNames() throws -> [String] { try Factory.fixtureVariants(configSchema) }
    static func responseVariantNames() throws -> [String] { try Factory.fixtureVariants(responseSchema) }
    static func responseSampleNames() throws -> [String] { try Factory.sampleNames(responseSchema) }

    private static func replacing(_ payload: [String: Any], state: String?, listings: [[String: Any]]?) -> [String: Any] {
        var result = payload["result"] as? [String: Any] ?? [:]
        if let state = state { result["state"] = state }
        if let listings = listings { result["rs"] = listings }
        return Factory.merge(payload, ["result": result])
    }
}
