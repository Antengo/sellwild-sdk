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
        let payload = Factory.merge(try Factory.object("fixtures/\(configSchema)/valid/\(name).json"), overrides)
        return overrides.isEmpty ? payload : try Factory.used(payload, schema: configSchema)
    }

    /// The real state cache. `state` and `listings` replace `result.state`
    /// and `result.rs`.
    static func response(state: String? = nil, listings: [[String: Any]]? = nil) throws -> [String: Any] {
        try responseSample(defaultResponse, state: state, listings: listings)
    }

    /// The real state cache with `overrides` merged into `result`
    /// (`Factory.remove` drops a key: `response(result: ["rs": Factory.remove])`).
    static func response(result overrides: [String: Any]) throws -> [String: Any] {
        let payload = try response()
        let merged = Factory.merge(payload, ["result": Factory.merge(payload["result"] as? [String: Any] ?? [:], overrides)])
        return overrides.isEmpty ? merged : try Factory.used(merged, schema: responseSchema)
    }

    static func responseSample(_ name: String, state: String? = nil, listings: [[String: Any]]? = nil) throws -> [String: Any] {
        try replacing(try Factory.object("samples/\(responseSchema)/\(name).json"), state: state, listings: listings)
    }

    static func responseVariant(_ name: String, state: String? = nil, listings: [[String: Any]]? = nil) throws -> [String: Any] {
        try replacing(try Factory.object("fixtures/\(responseSchema)/valid/\(name).json"), state: state, listings: listings)
    }

    static func configVariantNames() throws -> [String] { try Factory.fixtureVariants(configSchema) }
    static func responseVariantNames() throws -> [String] { try Factory.fixtureVariants(responseSchema) }
    static func responseSampleNames() throws -> [String] { try Factory.sampleNames(responseSchema) }

    /// A payload built with a state or listings is emitted for the validator
    /// (`Factory.used`).
    private static func replacing(_ payload: [String: Any], state: String?, listings: [[String: Any]]?) throws -> [String: Any] {
        guard state != nil || listings != nil else { return payload }
        var result = payload["result"] as? [String: Any] ?? [:]
        if let state = state { result["state"] = state }
        if let listings = listings { result["rs"] = listings }
        return try Factory.used(Factory.merge(payload, ["result": result]), schema: responseSchema)
    }
}
