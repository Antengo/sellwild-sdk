import Foundation

/// The pure half of `SellwildPrebidMobile`: which Prebid Server to use, the
/// publisher id, and the one global ORTB object (`app.publisher.id`,
/// `app.cat`, `device.devicetype`, `device.geo`). No I/O and no logging.
enum SellwildPrebidConfig {

    /// Sellwild's hosted Prebid Server.
    static let defaultEndpoint = "https://prebid.sellwild.com/openrtb2/auction"

    struct Server: Equatable {
        let url: String
        let accountId: String
    }

    /// The typed `PrebidServerConfig` wins; then the raw `S2S_CONFIG` when it
    /// is an object (`endpoint` or `url`, `accountId` or `account`); then the
    /// hosted default with the partner code as the account. The CMS ships
    /// `S2S_CONFIG` as text, which is not read (known drift, recorded in
    /// contracts/expectations/drift/ios.json).
    static func server(typed: PrebidServerConfig?, remoteValues: [String: Any]?, partnerCode: String) -> Server {
        if let typed {
            return Server(url: typed.endpoint, accountId: typed.accountId)
        }
        if let s2s = remoteValues?["S2S_CONFIG"] as? [String: Any] {
            return Server(url: firstText(s2s, "endpoint", "url") ?? defaultEndpoint,
                          accountId: firstText(s2s, "accountId", "account") ?? partnerCode)
        }
        return Server(url: defaultEndpoint, accountId: partnerCode)
    }

    private static func firstText(_ object: [String: Any], _ first: String, _ second: String) -> String? {
        if let value = object[first] as? String { return value }
        return object[second] as? String
    }

    /// `app.publisher.id` (the sellers.json seller id): the top-level
    /// `PUBLISHER_ID`, else `SELLER_ID`, as text or a number. nil when absent
    /// or empty. An empty `PUBLISHER_ID` does not fall back to `SELLER_ID`
    /// (known drift).
    static func publisherId(remoteValues: [String: Any]?) -> String? {
        guard let remoteValues else { return nil }
        switch remoteValues["PUBLISHER_ID"] ?? remoteValues["SELLER_ID"] {
        case let s as String where !s.isEmpty: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    /// The global ORTB object. `setGlobalORTBConfig` is last-write-wins, so
    /// everything lives in this one object. `device.devicetype` is always
    /// there (the iOS fork does not fill it; Android does).
    static func globalORTB(publisherId: String?, cats: [String]?, geo: [String: Any]?, deviceType: Int) -> [String: Any] {
        var app: [String: Any] = [:]
        if let publisherId, !publisherId.isEmpty { app["publisher"] = ["id": publisherId] }
        if let cats, !cats.isEmpty { app["cat"] = cats }
        var device: [String: Any] = ["devicetype": deviceType]
        if let geo, !geo.isEmpty { device["geo"] = geo }
        var root: [String: Any] = ["device": device]
        if !app.isEmpty { root["app"] = app }
        return root
    }

    /// `JSONSerialization`, compact.
    static func serializeJSON(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    /// Why a value could not be written as JSON (`ad.ortb_config.exception`
    /// for the global ORTB object, `widget.attributes.exception` for a widget
    /// attribute).
    enum JSONProblem: Error {
        /// It holds a value JSON cannot carry, such as a NaN latitude.
        case notJSON
        case serialization(Error)

        /// The serializer's error, when it threw.
        var error: Error? {
            if case .serialization(let error) = self { return error }
            return nil
        }
    }

    /// `object` (an array or an object) as JSON text. `serialize` is a seam
    /// for tests.
    static func json(_ object: Any, serialize: (Any) throws -> Data = serializeJSON) -> Result<String, JSONProblem> {
        guard JSONSerialization.isValidJSONObject(object) else { return .failure(.notJSON) }
        do {
            return .success(String(decoding: try serialize(object), as: UTF8.self))
        } catch {
            return .failure(.serialization(error))
        }
    }
}
