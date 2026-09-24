import Foundation
@testable import SellwildSDK

/// One listing (an element of `result.rs`), schema `listing`.
enum ListingFactory {

    static let schema = "listing"
    static let defaultVariant = "sellwild-cache-item"

    /// A Sellwild cache item with `overrides` applied.
    static func make(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        try variant(defaultVariant, overrides)
    }

    /// A fixture from `fixtures/listing/valid` (e.g. "rpc-item", "numeric-id").
    static func variant(_ name: String, _ overrides: [String: Any] = [:]) throws -> [String: Any] {
        Factory.merge(try Factory.object("fixtures/\(schema)/valid/\(name).json"), overrides)
    }

    static func variantNames() throws -> [String] { try Factory.fixtureVariants(schema) }

    /// The listing through the SDK's own decoder.
    static func decoded(_ listing: [String: Any]) throws -> SellwildListing {
        try JSONDecoder().decode(SellwildListing.self, from: Factory.data(listing))
    }
}
