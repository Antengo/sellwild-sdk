import Foundation
import SellwildPrebidSDK

/// A winning native bid in the Prebid fork's local cache, so
/// `NativeAd.create(cacheId:)` returns a real `NativeAd`.
///
/// This is an OpenRTB bid, a Prebid Server shape the fork parses. No schema in
/// contracts/schemas covers it (the contracts describe Sellwild's own
/// payloads), so it cannot be emitted for the validator like the other
/// factories. It is the smallest bid the fork accepts: an id, an impid, a
/// price and native markup with no assets. No `nurl`, `burl` or event URLs,
/// so creating and registering the ad sends nothing.
enum NativeBidFactory {

    static func bid() -> [String: Any] {
        ["id": "bid-1", "impid": "imp-1", "price": 1.25, "adm": #"{"assets":[]}"#]
    }

    /// Saves `bid()` in the fork's cache and returns its local cache id.
    static func cachedBidId() throws -> String? {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: bid()), as: UTF8.self)
        return CacheManager.shared.save(content: text)
    }
}
