import Foundation

/// The pure half of `SellwildPrebidMobile`: which Prebid Server to use, the
/// publisher id, and the one global ORTB object (`app.publisher.id`,
/// `app.cat`, `device.devicetype`, `device.geo`). No I/O and no logging.
enum SellwildPrebidConfig {

    /// Sellwild's hosted Prebid Server.
    static let defaultEndpoint = "https://prebid.sellwild.com/openrtb2/auction"

    /// The Prebid Server timeout when the config sets none, in ms.
    static let defaultTimeoutMillis = 1500

    /// Per-config Prebid fields `bootstrap` applies (and re-applies when a
    /// later config differs). nil = "this config doesn't specify it".
    struct Fields: Equatable {
        var serverURL: String?
        var accountId: String?
        var timeout: Int?
        var storeURL: String?
        var publisherId: String?
        var cats: [String]?

        /// Fill fields this value leaves nil from `base`.
        func overlaying(_ base: Fields?) -> Fields {
            guard let base else { return self }
            return Fields(
                serverURL: serverURL ?? base.serverURL,
                accountId: accountId ?? base.accountId,
                timeout: timeout ?? base.timeout,
                storeURL: storeURL ?? base.storeURL,
                publisherId: publisherId ?? base.publisherId,
                cats: cats ?? base.cats
            )
        }
    }

    /// The fields `config` specifies. IAB content categories (IAB_CATS) become
    /// ORTB app.cat: a content signal, not consent, so it is always attached
    /// when the CMS provides it.
    static func fields(of config: SellwildConfig) -> Fields {
        let server = specifiedServer(typed: config.prebidServer, remoteValues: config.remoteValues)
        return Fields(
            serverURL: server?.endpoint,
            accountId: server?.accountId,
            timeout: server?.timeout,
            storeURL: config.appStoreUrl,
            publisherId: publisherId(remoteValues: config.remoteValues),
            cats: config.iabCats.isEmpty ? nil : config.iabCats
        )
    }

    /// What the first bootstrap applies: `fields(of:)` over Sellwild's hosted
    /// Prebid Server, the partner code as the account and the default timeout,
    /// so the SDK still does something on partial CMS config.
    static func initialFields(of config: SellwildConfig) -> Fields {
        fields(of: config).overlaying(Fields(serverURL: defaultEndpoint, accountId: config.partnerCode,
                                             timeout: defaultTimeoutMillis))
    }

    /// The Prebid Server fields the config actually specifies: the typed
    /// `PrebidServerConfig` wins, else the CDN `S2S_CONFIG` (an object, an
    /// array, JSON text or the CMS's JS object-literal text; see
    /// `SellwildS2SConfig`). nil when neither is usable.
    static func specifiedServer(typed: PrebidServerConfig?, remoteValues: [String: Any]?) -> SellwildS2SConfig? {
        if let typed {
            return SellwildS2SConfig(accountId: typed.accountId, endpoint: typed.endpoint, timeout: typed.timeout)
        }
        return SellwildS2SConfig.parse(remoteValues?["S2S_CONFIG"])
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

    /// Why the global ORTB object could not be written as JSON
    /// (`ad.ortb_config.exception`).
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
