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

    override init() {
        super.init()
        SellwildRNWrapper.install()
    }

    /// Off-main is fine — the setters just update process-wide state.
    @objc static func requiresMainQueueSetup() -> Bool { false }

    /// JS: `SellwildRNModule.setGeo({ state: "NY", zip: "10001", ... })`.
    /// Pass an empty object to clear. Mirrors the native
    /// `SellwildPrebidMobile.setGeo(_:)` — updates the Prebid auction geo AND the
    /// shared `SellwildGeoStore`. A payload that is not an object clears geo; a
    /// field of the wrong type is dropped and the others are set, as before.
    /// Both are reported (`bridge.geo.invalid`), with the same text as Android.
    @objc(setGeo:)
    func setGeo(_ geo: NSDictionary) {
        let parsed = SellwildRNBridgeRules.geoMap(geo)
        if let problem = parsed.problem {
            SellwildFailures.log(code: .bridgeGeoInvalid, component: .bridge, severity: .warn, message: problem)
        }
        SellwildPrebidMobile.setGeo(SellwildGeo(bridged: parsed.map))
    }

    /// JS: `SellwildRNModule.setExternalUserIds([{ source, uids: [{ id, atype, ext? }] }])`.
    /// Pass `[]` to clear. Mirrors `SellwildPrebidMobile.setExternalUserIds(_:)`.
    @objc(setExternalUserIds:)
    func setExternalUserIds(_ eids: NSArray) {
        let parsed = SellwildRNBridgeRules.eids(eids)
        if let problem = parsed.problem {
            SellwildFailures.log(code: .bridgeEidsInvalid, component: .bridge, severity: .warn, message: problem)
        }
        let mapped = parsed.eids.map { eid in
            SellwildEid(source: eid.source, uids: eid.uids.map { SellwildEidUID(id: $0.id, atype: $0.atype, ext: $0.ext) })
        }
        SellwildPrebidMobile.setExternalUserIds(mapped)
    }

    /// JS: `SellwildRNModule.prewarm(nativeConfig)`. Pre-initializes the native ad
    /// stack before the first ad view mounts so the first impression doesn't incur
    /// cold-start init latency. Idempotent. Reuses the banner manager's config
    /// mapping so the payload matches `<SellwildBanner config=...>`. iOS bootstraps
    /// inside `configure()` too; this is the explicit early opt-in for parity with
    /// Android's `SellwildSDK.prewarm`.
    @objc(prewarm:)
    func prewarm(_ config: NSDictionary) {
        // The mapping is a static on the banner's host view.
        let cfg = SellwildBannerHostView.configFromMap(config)
        DispatchQueue.main.async {
            _ = SellwildPrebidMobile.bootstrap(with: cfg)
        }
    }
}

/// Marks every failure the native SDK reports as coming from React Native
/// (`wrapper: react-native`, contracts/FAILURES.md 3.1). The native SDK logs
/// its own failures; the bridge only adds the wrapper and never logs them
/// again (FAILURES.md 9).
///
/// This module and both view managers call `install()` from `init`, so the
/// wrapper is set before any native SDK code runs, whichever class React
/// Native creates first. The `static let` runs once, thread-safely.
enum SellwildRNWrapper {
    private static let installed: Void = {
        SellwildFailures.setWrapper("react-native")
    }()

    static func install() {
        _ = installed
    }
}
