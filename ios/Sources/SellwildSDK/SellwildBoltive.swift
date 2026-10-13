// SellwildBoltive.swift — Boltive ad-quality monitoring for rendered banners.
//
// Boltive watches the creative WKWebView inside a rendered banner and blanks a
// creative it flags as malicious/offensive, then calls us back. It runs AFTER
// render (it does not filter bids before the auction), so every render we
// skip is unmonitored. The policy below decides which renders get a monitor.
//
// Remote config (all default OFF / unlimited):
//   MOBILE_BOLTIVE_ENABLED          bool — master switch (default false)
//   MOBILE_BOLTIVE_ENABLED_IOS      bool or "on"/"off" — platform override; off
//                                   is a hard kill, on turns it on everywhere on
//                                   iOS. Blank (the CMS select's default) = unset
//   MOBILE_BOLTIVE_ENABLED_BY_ZONE  {zoneId: bool} — per-zone opt-in when the
//                                   global switch is off
//   MOBILE_BOLTIVE_CLIENT_ID        string — Boltive client id; empty ⇒ off
//   MOBILE_BOLTIVE_SAMPLE_RATE      0–1 — share of renders monitored (default 1)
//   MOBILE_BOLTIVE_MAX_PER_SESSION  int — monitored renders per app launch
//                                   (0/absent = unlimited)
//   MOBILE_BOLTIVE_MAX_PER_SLOT     int — monitored renders per ad view
//                                   (0/absent = unlimited)
//
// On a block, SellwildAdView hides the paid creative, shows the house backdrop,
// emits `adBlocked`, and re-auctions if the refresh cap has budget.

import UIKit
#if canImport(Boltive)
import Boltive
#endif

enum SellwildBoltive {

    /// Resolved settings for one placement. `nil` from `policy` means off.
    struct Policy: Equatable {
        let clientId: String
        let sampleRate: Double
        let maxPerSession: Int
        let maxPerSlot: Int
    }

    /// Which ad server rendered the creative; maps to Boltive's ad network.
    enum Network: Equatable {
        case gam
        case prebid
    }

    /// Whether Boltive is enabled for this placement. See the file header for
    /// the key precedence.
    static func isEnabled(remoteValues: [String: Any]?, zoneId: String?) -> Bool {
        if let platform = remoteValues?["MOBILE_BOLTIVE_ENABLED_IOS"], !isBlank(platform) {
            return truthy(platform)
        }
        if truthy(remoteValues?["MOBILE_BOLTIVE_ENABLED"]) { return true }
        if let zoneId,
           let byZone = remoteValues?["MOBILE_BOLTIVE_ENABLED_BY_ZONE"] as? [String: Any],
           let perZone = byZone[zoneId] {
            return truthy(perZone)
        }
        return false
    }

    /// The monitoring policy for this placement, or `nil` when Boltive is off
    /// (disabled, or no client id).
    static func policy(remoteValues: [String: Any]?, zoneId: String?) -> Policy? {
        guard isEnabled(remoteValues: remoteValues, zoneId: zoneId) else { return nil }
        guard let clientId = (remoteValues?["MOBILE_BOLTIVE_CLIENT_ID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !clientId.isEmpty else { return nil }
        let rate = number(remoteValues?["MOBILE_BOLTIVE_SAMPLE_RATE"]) ?? 1
        return Policy(
            clientId: clientId,
            sampleRate: min(max(rate, 0), 1),
            maxPerSession: max(Int(number(remoteValues?["MOBILE_BOLTIVE_MAX_PER_SESSION"]) ?? 0), 0),
            maxPerSlot: max(Int(number(remoteValues?["MOBILE_BOLTIVE_MAX_PER_SLOT"]) ?? 0), 0)
        )
    }

    /// Whether this render gets a monitor. Caps are checked before the sample
    /// roll; `roll` is in [0, 1).
    static func shouldMonitor(policy: Policy, slotCount: Int, sessionCount: Int, roll: Double) -> Bool {
        if policy.maxPerSlot > 0, slotCount >= policy.maxPerSlot { return false }
        if policy.maxPerSession > 0, sessionCount >= policy.maxPerSession { return false }
        return roll < policy.sampleRate
    }

    /// Monitored renders this app launch (main thread only).
    static var sessionCount = 0

    private static func truthy(_ v: Any?) -> Bool {
        switch v {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "yes", "on"].contains(s.lowercased())
        default: return false
        }
    }

    private static func isBlank(_ v: Any) -> Bool {
        (v as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? false
    }

    private static func number(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}

/// Per-ad-view Boltive monitor. Created once per `SellwildAdView`; holds at most
/// one live `BoltiveMonitor`, dropped whenever a render isn't monitored so a
/// sampled-out render costs nothing. Main thread only.
final class SellwildBoltiveController {

    /// Details Boltive attaches to a block report.
    struct Tag {
        var adUnitId: String?
        var advertiserId: String?
        var creativeId: String?
        var campaignId: String?
        var sspRefreshCode: String?
    }

    /// Monitored renders for this ad view.
    private(set) var slotCount = 0

    #if canImport(Boltive)
    private var monitor: BoltiveMonitor?
    private var monitorKey: String?
    #endif

    /// Decide whether to monitor this render and, if so, capture `bannerView`.
    /// `onBlocked` runs on the main thread with `bannerView` when it's blocked.
    /// Returns whether a monitor was attached.
    @discardableResult
    func renderDidSucceed(
        bannerView: UIView,
        network: SellwildBoltive.Network,
        remoteValues: [String: Any]?,
        zoneId: String?,
        tag: Tag,
        roll: Double = Double.random(in: 0..<1),
        onBlocked: @escaping (UIView) -> Void
    ) -> Bool {
        guard let policy = SellwildBoltive.policy(remoteValues: remoteValues, zoneId: zoneId),
              SellwildBoltive.shouldMonitor(
                policy: policy,
                slotCount: slotCount,
                sessionCount: SellwildBoltive.sessionCount,
                roll: roll
              ) else {
            stop()
            return false
        }
        #if canImport(Boltive)
        let key = "\(policy.clientId)|\(network)"
        if monitor == nil || monitorKey != key {
            let adNetwork: BoltiveAdNetwork = network == .gam
                ? .GoogleAdManager
                : .customAdNetwork(adNetworkName: "Prebid")
            monitor = BoltiveMonitor(configuration: BoltiveConfiguration(clientId: policy.clientId, adNetwork: adNetwork))
            monitorKey = key
        }
        let details = BoltiveTagDetails(
            adUnitId: tag.adUnitId,
            advertiserId: tag.advertiserId,
            campaignId: tag.campaignId,
            creativeId: tag.creativeId,
            sspRefreshCode: tag.sspRefreshCode
        )
        // Report the view we captured, not whatever subview Boltive hands back,
        // so the ad view can match it against its current banner.
        monitor?.capture(bannerView: bannerView, tagDetails: details) { [weak bannerView] _ in
            let deliver = { if let bannerView { onBlocked(bannerView) } }
            if Thread.isMainThread {
                deliver()
            } else {
                DispatchQueue.main.async(execute: deliver)
            }
        }
        slotCount += 1
        SellwildBoltive.sessionCount += 1
        #if DEBUG
        print("[SellwildBoltive] monitoring render — zone \(zoneId ?? "?"), \(network), slot #\(slotCount), session #\(SellwildBoltive.sessionCount)")
        #endif
        return true
        #else
        return false
        #endif
    }

    /// Drop the live monitor (if any). Boltive stops monitoring on deinit.
    func stop() {
        #if canImport(Boltive)
        monitor = nil
        monitorKey = nil
        #endif
    }
}
