import Foundation

/// A message the widget page's bridge script posts to
/// `window.webkit.messageHandlers.sellwildWidget`, schema `bridge-message`.
///
///     let body = try BridgeMessageFactory.text(BridgeMessageFactory.variant("error"))
///     widget.handleMessage(body: body)
enum BridgeMessageFactory {

    static let schema = "bridge-message"
    static let defaultVariant = "widget-loaded"

    /// A WIDGET_LOADED message with `overrides` applied.
    static func make(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        try variant(defaultVariant, overrides)
    }

    /// A fixture from `fixtures/bridge-message/valid` (e.g. "listing-click-url").
    static func variant(_ name: String, _ overrides: [String: Any] = [:]) throws -> [String: Any] {
        let payload = Factory.merge(try Factory.object("fixtures/\(schema)/valid/\(name).json"), overrides)
        return overrides.isEmpty ? payload : try Factory.used(payload, schema: schema)
    }

    static func variantNames() throws -> [String] { try Factory.fixtureVariants(schema) }

    /// The message as the JSON text the bridge script posts.
    static func text(_ message: [String: Any]) throws -> String {
        String(decoding: try Factory.data(message), as: UTF8.self)
    }
}
