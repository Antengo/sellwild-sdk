import Foundation

/// A GrowthCode Signal Resolve sync response, schema `growthcode-sync-response`.
enum GrowthCodeFactory {

    static let schema = "growthcode-sync-response"
    static let defaultVariant = "full"

    /// A full sync response (gc_id, an `eb` EID blob as JSON text, idi, kv)
    /// with `overrides` applied.
    static func syncResponse(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        try variant(defaultVariant, overrides)
    }

    static func variant(_ name: String, _ overrides: [String: Any] = [:]) throws -> [String: Any] {
        let payload = Factory.merge(try Factory.object("fixtures/\(schema)/valid/\(name).json"), overrides)
        return overrides.isEmpty ? payload : try Factory.used(payload, schema: schema)
    }

    /// A sync response whose `eb` is `eids` as JSON text, the way the API sends it.
    static func syncResponse(eids: [[String: Any]], _ overrides: [String: Any] = [:]) throws -> [String: Any] {
        let text = String(decoding: try Factory.data(eids), as: UTF8.self)
        return try syncResponse(Factory.merge(["eb": text], overrides))
    }

    static func variantNames() throws -> [String] { try Factory.fixtureVariants(schema) }
}
