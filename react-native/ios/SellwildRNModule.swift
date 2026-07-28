import Foundation
import SellwildSDK

/// React Native method module for the native Sellwild SDK's runtime setters.
///
/// The RN ad surface is otherwise view-manager-only (config flows as a prop);
/// this module is the one callable bridge for imperative, session-scoped calls
/// like `setGeo`. Registered on iOS via `RCT_EXTERN_MODULE` (see the paired
/// `SellwildRNModule.m`); no manual package wiring is needed.
@objc(SellwildRNModule)
final class SellwildRNModule: NSObject {

    /// Off-main is fine — the setters just update process-wide state.
    @objc static func requiresMainQueueSetup() -> Bool { false }

    /// JS: `SellwildRNModule.setGeo({ state: "NY", zip: "10001", ... })`.
    /// Pass an empty object to clear. Mirrors the native
    /// `SellwildPrebidMobile.setGeo(_:)` — updates the Prebid auction geo AND the
    /// shared `SellwildGeoStore`.
    @objc(setGeo:)
    func setGeo(_ geo: NSDictionary) {
        let map = geo as? [String: Any] ?? [:]
        SellwildPrebidMobile.setGeo(SellwildGeo(bridged: map))
    }

    /// JS: `SellwildRNModule.setExternalUserIds([{ source, uids: [{ id, atype, ext? }] }])`.
    /// Pass `[]` to clear. Mirrors `SellwildPrebidMobile.setExternalUserIds(_:)`.
    @objc(setExternalUserIds:)
    func setExternalUserIds(_ eids: NSArray) {
        let mapped: [SellwildEid] = (eids as? [[String: Any]] ?? []).compactMap { dict in
            guard let source = dict["source"] as? String,
                  let rawUids = dict["uids"] as? [[String: Any]] else { return nil }
            let uids: [SellwildEidUID] = rawUids.compactMap { u in
                guard let id = u["id"] as? String else { return nil }
                let atype = (u["atype"] as? NSNumber)?.intValue ?? 0
                return SellwildEidUID(id: id, atype: atype, ext: u["ext"] as? [String: Any])
            }
            return SellwildEid(source: source, uids: uids)
        }
        SellwildPrebidMobile.setExternalUserIds(mapped)
    }
}
