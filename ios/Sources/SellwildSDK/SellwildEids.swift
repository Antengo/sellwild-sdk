// SellwildEids.swift — partner-supplied external/extended user IDs (user.ext.eids).
//
// Authenticated universal IDs (UID2, ID5, LiveRamp RampID, …) are minted from the
// user's email / login / consent, which only the host app holds — the SDK cannot
// generate them. The partner obtains the ID(s) from their identity provider and
// hands them to the SDK via `SellwildPrebidMobile.setExternalUserIds(_:)`; the SDK
// formats them into OpenRTB `user.ext.eids` on every native Prebid auction.

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
    static func setExternalUserIds(_ eids: [SellwildEid]) {
        let mapped: [ExternalUserId] = eids.map { eid in
            ExternalUserId(
                source: eid.source,
                uids: eid.uids.map { UserUniqueID(id: $0.id, aType: $0.atype, ext: $0.ext) }
            )
        }
        Targeting.shared.setExternalUserIds(mapped)
    }
}
