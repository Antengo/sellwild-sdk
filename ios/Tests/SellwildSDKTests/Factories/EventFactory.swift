import Foundation

/// Existing analytics events as the queue posts them, schema `events-batch`
/// (a JSON array of events).
enum EventFactory {

    static let schema = "events-batch"
    static let defaultVariant = "ios-ad-error"

    /// The iOS adError event with `overrides` applied.
    static func event(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        guard let first = try batchVariant(defaultVariant).first else { throw Factory.Failure.emptyArray(defaultVariant) }
        return Factory.merge(first, overrides)
    }

    /// A batch: `events`, or one default event.
    static func batch(_ events: [[String: Any]]? = nil) throws -> [[String: Any]] {
        try events ?? [event()]
    }

    static func batchVariant(_ name: String) throws -> [[String: Any]] {
        try Factory.array("fixtures/\(schema)/valid/\(name).json")
    }

    static func variantNames() throws -> [String] { try Factory.fixtureVariants(schema) }
}
