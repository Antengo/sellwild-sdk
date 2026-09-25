import Foundation

/// A listings feed (`{ result: { rs: [...] } }`), schema `listings-response`.
enum ListingsResponseFactory {

    static let schema = "listings-response"
    /// The real general cache (`cache.sellwild.com/listings-img-data-sm`).
    static let defaultSample = "listings-img-data-sm"

    /// The real cache payload. `listings` replaces `result.rs`; `result`
    /// overrides apply inside `result`.
    static func make(listings: [[String: Any]]? = nil, result overrides: [String: Any] = [:]) throws -> [String: Any] {
        try sample(defaultSample, listings: listings, result: overrides)
    }

    static func sample(_ name: String, listings: [[String: Any]]? = nil, result overrides: [String: Any] = [:]) throws -> [String: Any] {
        try replacing(try Factory.object("samples/\(schema)/\(name).json"), listings: listings, overrides: overrides)
    }

    /// A fixture from `fixtures/listings-response/valid` (e.g. "rpc-envelope").
    static func variant(_ name: String, listings: [[String: Any]]? = nil, result overrides: [String: Any] = [:]) throws -> [String: Any] {
        try replacing(try Factory.object("fixtures/\(schema)/valid/\(name).json"), listings: listings, overrides: overrides)
    }

    static func variantNames() throws -> [String] { try Factory.fixtureVariants(schema) }
    static func sampleNames() throws -> [String] { try Factory.sampleNames(schema) }

    static func data(listings: [[String: Any]]? = nil, result overrides: [String: Any] = [:]) throws -> Data {
        try Factory.data(make(listings: listings, result: overrides))
    }

    /// A payload built with listings or overrides is emitted for the
    /// validator (`Factory.used`).
    private static func replacing(_ payload: [String: Any], listings: [[String: Any]]?, overrides: [String: Any]) throws -> [String: Any] {
        guard listings != nil || !overrides.isEmpty else { return payload }
        var result = payload["result"] as? [String: Any] ?? [:]
        if let listings = listings { result["rs"] = listings }
        result = Factory.merge(result, overrides)
        return try Factory.used(Factory.merge(payload, ["result": result]), schema: schema)
    }
}
