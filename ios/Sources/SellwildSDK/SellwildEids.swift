// SellwildEids.swift — partner-supplied external/extended user IDs (user.ext.eids).
//
// Login-based universal IDs (UID2, LiveRamp RampID, …) are minted from the user's
// email / login, which only the host app holds — the SDK cannot generate them. The
// partner obtains those from their identity provider and hands them to the SDK via
// `SellwildPrebidMobile.setExternalUserIds(_:)`.
//
// ID5 is different: it mints from first-party / probabilistic signals with just a
// partner id (no login), so the SDK CAN resolve it automatically — see
// `SellwildID5`, which feeds this registry's `id5` bucket like GrowthCode feeds
// its own. Either way, the SDK formats the union into OpenRTB `user.ext.eids` on
// every native Prebid auction.

import Foundation
import SellwildPrebidSDK

/// One id value within a `SellwildEid` source.
public struct SellwildEidUID {
    /// The raw ID token from the provider.
    public let id: String
    /// OpenRTB agent type (`user.ext.eids[].uids[].atype`). Common values:
    /// 1 = cookie/web, 2 = in-app device id, 3 = person-based (authenticated).
    public let atype: Int
    /// Optional provider-specific extension, e.g. `["rtiPartner": "TDID"]`.
    public let ext: [String: Any]?

    public init(id: String, atype: Int, ext: [String: Any]? = nil) {
        self.id = id
        self.atype = atype
        self.ext = ext
    }
}

/// One identity source for `user.ext.eids` (e.g. `uidapi.com`, `id5-sync.com`,
/// `liveramp.com`), carrying one or more id values.
public struct SellwildEid {
    public let source: String
    public let uids: [SellwildEidUID]

    public init(source: String, uids: [SellwildEidUID]) {
        self.source = source
        self.uids = uids
    }
}

public extension SellwildPrebidMobile {
    /// Set partner-supplied external/extended user IDs, emitted as OpenRTB
    /// `user.ext.eids` on every native Prebid auction.
    ///
    /// - Call once per user session, after `bootstrap(with:)` / the SDK is
    ///   configured and before (or at) the first `SellwildAdView.load()`.
    /// - Prebid Mobile does NOT persist eids across app restarts — re-set them on
    ///   each launch (typically right after you resolve the user's identity).
    /// - Delivery to each bidder is additionally governed by eid permissions in
    ///   the Prebid Server stored request; by default Prebid Server forwards eids.
    /// - Pass an empty array to clear previously set eids (e.g. on logout).
    /// - These "consumer" eids are merged with any SDK-resolved identity (e.g.
    ///   GrowthCode Signal Resolve); on a source conflict, THESE win.
    static func setExternalUserIds(_ eids: [SellwildEid]) {
        SellwildEidRegistry.setConsumer(eids)
    }
}

/// Merges the two eid sources the SDK can carry — partner-supplied ("consumer")
/// eids from `setExternalUserIds`, and SDK-resolved eids (GrowthCode) — and
/// pushes the union to Prebid's global targeting on every change.
///
/// Prebid's `Targeting.setExternalUserIds` is last-write-wins (it REPLACES the
/// whole set), so neither source can call it directly without clobbering the
/// other. This registry holds both buckets and re-emits the merge, with the
/// consumer bucket winning on a source conflict (a source present in `consumer`
/// fully suppresses GrowthCode's entry for that same source).
enum SellwildEidRegistry {
    private static let lock = NSLock()
    private static var consumer: [SellwildEid] = []
    private static var id5: [SellwildEid] = []
    private static var growthCode: [SellwildEid] = []

    /// Partner-supplied eids (from the public `setExternalUserIds`).
    static func setConsumer(_ eids: [SellwildEid]) {
        lock.lock(); consumer = eids; lock.unlock()
        push()
    }

    /// SDK-resolved ID5 eids. Internal — set by `SellwildID5`.
    static func setId5(_ eids: [SellwildEid]) {
        lock.lock(); id5 = eids; lock.unlock()
        push()
    }

    /// SDK-resolved eids (GrowthCode). Internal — set by `SellwildGrowthCode`.
    static func setGrowthCode(_ eids: [SellwildEid]) {
        lock.lock(); growthCode = eids; lock.unlock()
        push()
    }

    private static func push() {
        lock.lock()
        // Precedence on a source conflict: consumer > id5 > growthCode. First
        // bucket to claim a source wins; later buckets' same-source entries drop.
        var seen = Set<String>()
        var merged: [SellwildEid] = []
        for bucket in [consumer, id5, growthCode] {
            for eid in bucket where !seen.contains(eid.source) {
                merged.append(eid)
                seen.insert(eid.source)
            }
        }
        lock.unlock()

        let mapped: [ExternalUserId] = merged.map { eid in
            ExternalUserId(
                source: eid.source,
                uids: eid.uids.map {
                    UserUniqueID(
                        uniqueId: $0.id,
                        aType: NSNumber(value: $0.atype),
                        ext: $0.ext
                    )
                }
            )
        }
        Targeting.shared.setExternalUserIds(mapped)
    }
}
