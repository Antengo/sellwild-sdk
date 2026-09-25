import Foundation

/// Remote app config (`widget.sellwild.com/app/<partner>/<slug>.json`),
/// schema `app-config`.
///
///     let raw = try AppConfigFactory.make(["FAILURES_SAMPLE_RATE": "0.5"])
///     StubURLProtocol.handler = { _ in try .json(raw) }
enum AppConfigFactory {

    static let schema = "app-config"
    /// The real weatherbug config captured from the CDN.
    static let defaultSample = "weatherbug_weatherbug-weatherbug"

    /// The real weatherbug config with `overrides` applied.
    static func make(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        try sample(defaultSample, overrides)
    }

    /// A captured config from `samples/app-config`.
    static func sample(_ name: String, _ overrides: [String: Any] = [:]) throws -> [String: Any] {
        try built(Factory.merge(try Factory.object("samples/\(schema)/\(name).json"), overrides), overrides)
    }

    /// A hand-made edge case from `fixtures/app-config/valid` (e.g. "minimal").
    static func variant(_ name: String, _ overrides: [String: Any] = [:]) throws -> [String: Any] {
        try built(Factory.merge(try Factory.object("fixtures/\(schema)/valid/\(name).json"), overrides), overrides)
    }

    /// A payload built with overrides is emitted for the validator (`Factory.used`).
    private static func built(_ payload: [String: Any], _ overrides: [String: Any]) throws -> [String: Any] {
        overrides.isEmpty ? payload : try Factory.used(payload, schema: schema)
    }

    static func variantNames() throws -> [String] { try Factory.fixtureVariants(schema) }
    static func sampleNames() throws -> [String] { try Factory.sampleNames(schema) }

    /// The body a missing config really returns (403 AccessDenied XML).
    static func missingBody() throws -> Data {
        try Fixtures.data("samples/\(schema)/weatherbug_weatherbug-main.403.xml")
    }
}
