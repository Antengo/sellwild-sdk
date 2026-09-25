import Foundation
@testable import SellwildSDK

/// clientFailure events, schema `client-failure-event` (and its queue-stamped
/// `wireEvent` form inside `events-batch`).
enum ClientFailureEventFactory {

    static let schema = "client-failure-event"
    static let defaultVariant = "listings-http"

    /// The iOS listings.fetch.http event. `attributes` overrides apply inside
    /// `attributes`.
    static func make(_ overrides: [String: Any] = [:], attributes: [String: Any] = [:]) throws -> [String: Any] {
        try variant(defaultVariant, overrides, attributes: attributes)
    }

    static func variant(_ name: String, _ overrides: [String: Any] = [:], attributes: [String: Any] = [:]) throws -> [String: Any] {
        var event = try Factory.object("fixtures/\(schema)/valid/\(name).json")
        if !attributes.isEmpty {
            event["attributes"] = Factory.merge(event["attributes"] as? [String: Any] ?? [:], attributes)
        }
        return Factory.merge(event, overrides)
    }

    /// An event built by the real iOS pure core, not by hand.
    static func fromCore(
        _ input: SellwildFailuresCore.Input,
        partnerCode: String = "weatherbug",
        wrapper: String? = nil,
        uid: String = FailureCapture.uid,
        now: Int64 = FailureCapture.now
    ) throws -> [String: Any] {
        let context = SellwildFailuresCore.Context(partnerCode: partnerCode, client: "ios",
                                                   clientVersion: SellwildSDK.sdkVersion, wrapper: wrapper)
        let decision = SellwildFailuresCore.decide(state: .init(), input: input, context: context, uid: uid, now: now)
        guard let event = decision.event else { throw Factory.Failure.dropped(String(describing: decision.reason)) }
        return json(event)
    }

    static func json(_ event: SellwildFailuresCore.Event) -> [String: Any] {
        ["event": event.event, "action": event.action, "label": event.label, "attributes": event.attributes,
         "uid": event.uid, "createdTime": event.createdTime]
    }

    static func variantNames() throws -> [String] { try Factory.fixtureVariants(schema) }
}
