import UIKit
import GoogleMobileAds
import SellwildPrebidSDK

// SellwildAdView's ad-quality monitoring, first-load timing and render
// events, apart so the view's own file stays within its size budget.
extension SellwildAdView {

    // MARK: Boltive (ad quality)

    /// Monitor this render with Boltive when the policy allows it.
    func monitorWithBoltive(_ bannerView: UIView, network: SellwildBoltive.Network,
                            tag: SellwildBoltiveController.Tag, source: String) {
        let monitored = boltive.renderDidSucceed(
            bannerView: bannerView,
            network: network,
            remoteValues: config.remoteValues,
            zoneId: zoneId,
            tag: tag
        ) { [weak self] blocked in
            self?.handleBoltiveBlock(blocked)
        }
        if monitored { boltiveSource = source }
    }

    /// Boltive blanked a flagged creative. Hide it, show the house backdrop
    /// instead of a blank slot, report it, then re-auction if the refresh cap
    /// has budget (the reload counts against the cap). The next successful
    /// render un-hides the banner.
    func handleBoltiveBlock(_ blocked: UIView) {
        // Ignore a late callback for a banner we've since torn down.
        guard blocked === gamBanner || blocked === prebidBanner else { return }
        SellwildLog.debug("[SellwildBoltive] creative blocked — zone \(zoneLabel), source \(boltiveSource)")
        blocked.isHidden = true
        houseView?.isHidden = false
        delegate?.sellwildAdView?(self, didBlockAdForZoneId: zoneLabel)
        environment.events.sendEvent(SellwildEvent(event: "adBlocked", action: boltiveSource, label: zoneLabel))
        recordHouseImpressionIfShowing()
        guard !isPausedForDetach else { return }
        if blocked === gamBanner {
            refreshTimer?.cancel()
            refreshTimer = nil
            guard effectiveRefreshMax > 0, refreshCount < effectiveRefreshMax else { return }
            refreshCount += 1
            load()
        } else if hasPrebidRefreshBudget {
            // Through the network seam, as every other Prebid request here.
            // `blocked` is the Prebid banner (the guard above).
            _ = prebidBanner.map(environment.network.loadPrebid)
        }
    }

    // MARK: ad.firstLoad timing (FAILURES.md 18.1)

    /// From the first load() to the first render, once per zone per process.
    func startFirstLoadTimer() {
        if firstLoadTimer == nil && !firstLoadTimed {
            firstLoadTimer = SellwildTiming.start("ad.firstLoad", zoneId: zoneLabel)
        }
    }

    func recordFirstLoad() {
        guard let timer = firstLoadTimer else { return }
        firstLoadTimer = nil
        firstLoadTimed = true
        if SellwildTiming.claimOnce("ad.firstLoad:\(zoneLabel)") { _ = timer() }
    }

    // MARK: Render and house-ad events

    /// The zone as an event label: "" when there is none.
    var zoneLabel: String {
        zoneId ?? ""
    }

    /// Emit the per-render `adRenderSucceeded` (every render/refresh, unchanged)
    /// plus — once per ad surface — the web-parity `firstAdViewed`. The latter
    /// carries the same `attributes.code` (stamped in `sendEvent`) but no label,
    /// matching the web widget, and is deduped by `firstAdViewedGuard`.
    func emitAdRender() {
        recordFirstLoad()
        let zone = zoneLabel
        environment.events.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: zone))
        firstAdViewedGuard.fireOnce {
            environment.events.sendEvent(SellwildEvent(event: "firstAdViewed"))
            SellwildLog.debug("[SellwildEvents] firstAdViewed fired once for this ad surface (zone \(zone))")
        }
    }

    /// Fire the house-impression callback when the backdrop is actually visible.
    func recordHouseImpressionIfShowing() {
        guard let houseView, !houseView.isHidden else { return }
        delegate?.sellwildAdView?(self, didRecordHouseImpressionForZoneId: zoneLabel)
    }
}
