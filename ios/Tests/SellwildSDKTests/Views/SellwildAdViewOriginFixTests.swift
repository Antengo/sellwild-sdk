import XCTest
import UIKit
import GoogleMobileAds
@_spi(SWPBMInternal) import SellwildPrebidSDK
@testable import SellwildSDK

/// SellwildAdView behavior that origin/main fixed (PRs #74-#81), with the same
/// fakes as SellwildAdViewTests: fake GMA and Prebid, manual timers and a
/// captured events queue.
final class SellwildAdViewOriginFixTests: ViewTestCase {

    private func adConfig(_ overrides: [String: Any] = [:]) throws -> SellwildConfig {
        var config = try AppConfigFactory.config(overrides, partnerCode: "minimal")
        config.gamTag = "/1/app/mrec"
        return config
    }

    private func makeView(_ config: SellwildConfig) -> (SellwildAdView, AdViewDelegateRecorder) {
        let view = SellwildAdView(config: config, adSize: .mrec300x250, zoneId: "43")
        let recorder = AdViewDelegateRecorder()
        view.delegate = recorder
        // The view holds its delegate weakly; keep the recorder alive with it.
        objc_setAssociatedObject(view, &Self.delegateKey, recorder, .OBJC_ASSOCIATION_RETAIN)
        return (view, recorder)
    }

    private static var delegateKey: UInt8 = 0

    private func gam(_ view: SellwildAdView) -> AdManagerBannerView? {
        view.subviews.compactMap { $0 as? AdManagerBannerView }.first
    }

    private func prebid(_ view: SellwildAdView) -> PrebidBannerView? {
        view.subviews.compactMap { $0 as? PrebidBannerView }.first
    }

    func testAPrebidOnlyClickIsReportedOnceEvenWhenItLeavesTheAppFromItsModal() throws {
        // origin 2725d3d, 1847555
        network.ready = true
        let (view, delegate) = makeView(try adConfig(["AD_STACK": "prebidOnly"]))
        view.load()
        let banner = try XCTUnwrap(prebid(view))

        view.bannerViewWillPresentModal(banner)
        view.bannerViewWillLeaveApplication(banner)
        view.bannerViewDidDismissModal(banner)
        view.bannerViewWillLeaveApplication(banner)

        XCTAssertEqual(delegate.calls, ["click", "click"], "the modal and the leave after it are one click")
        XCTAssertEqual(recorder.events().map { $0["event"] as? String }, ["click", "click"])
        XCTAssertEqual(recorder.events().first?["label"] as? String, "43")
    }

    func testTearingDownThePrebidBannerForgetsAnOpenClickModal() throws {
        // origin 1847555: didDismissModal may never arrive after a teardown.
        network.ready = true
        let plain = try adConfig()
        let (view, delegate) = makeView(plain)
        func load(_ stack: SellwildAdStack, _ config: SellwildConfig) {
            view.adStackOverride = stack
            view.config = config
            view.load()
        }
        load(.prebidOnly, plain)
        view.bannerViewWillPresentModal(try XCTUnwrap(prebid(view)))
        load(.both, plain)
        load(.prebidOnly, plain)
        view.bannerViewWillLeaveApplication(try XCTUnwrap(prebid(view)))
        load(.prebidOnly, try adConfig(["NATIVE_ENABLED": true]))
        load(.prebidOnly, plain)
        view.bannerViewWillPresentModal(try XCTUnwrap(prebid(view)))
        load(.prebidOnly, try adConfig(["NATIVE_ENABLED": true]))
        load(.prebidOnly, plain)
        view.bannerViewWillLeaveApplication(try XCTUnwrap(prebid(view)))
        XCTAssertEqual(delegate.calls, ["click", "click", "click", "click"],
                       "a new banner does not inherit the old one's modal")
    }

    func testAPrebidOnlyBannerWithRefreshCapZeroNeverAutoRefreshes() throws {
        // origin 75b65f8: the fork clamps 0 up to 15 s, so cap 0 stores a negative interval.
        network.ready = true
        let (off, _) = makeView(try adConfig(["AD_STACK": "prebidOnly"]))
        off.load()
        XCTAssertEqual(try XCTUnwrap(prebid(off)).refreshInterval, 0)
    }

    func testAGAMLoadThatLandsWhileDetachedDoesNotRearmRefresh() throws {
        // origin 7a07be8
        network.ready = true
        var config = try adConfig()
        config.adRefreshMaxMobile = 5
        let (view, _) = makeView(config)
        let host = Host()
        host.add(view)
        view.load()
        view.removeFromSuperview()
        view.bannerViewDidReceiveAd(try XCTUnwrap(gam(view)))
        XCTAssertEqual(scheduler.pending, [], "no refresh while paused for detach")
        host.add(view)
        XCTAssertEqual(scheduler.pending, [30], "the reattach restarts it")
    }
}
