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
}
