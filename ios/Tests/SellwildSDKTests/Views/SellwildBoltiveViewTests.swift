import XCTest
import UIKit
import GoogleMobileAds
@_spi(SWPBMInternal) import SellwildPrebidSDK
@testable import SellwildSDK

/// A Boltive monitor as a test sees it: what it captured and the callback
/// Boltive would call when it blanks the creative.
final class FakeBoltiveSession: SellwildBoltiveSession {
    let clientId: String
    let network: SellwildBoltive.Network
    /// Weak, as Boltive holds it: the test can release the banner.
    private(set) weak var captured: UIView?
    private(set) var tag: SellwildBoltiveController.Tag?
    private var adBlocked: ((UIView) -> Void)?

    init(clientId: String, network: SellwildBoltive.Network) {
        self.clientId = clientId
        self.network = network
    }

    func capture(bannerView: UIView, tag: SellwildBoltiveController.Tag, adBlocked: @escaping (UIView) -> Void) {
        captured = bannerView
        self.tag = tag
        self.adBlocked = adBlocked
    }

    /// Boltive flagged the creative. It hands back a subview, not the banner.
    func block() {
        adBlocked?(UIView())
    }
}

/// The Boltive controller against fake monitors, and SellwildAdView's block
/// handling: hide the creative, show the house ad, tell the host, track
/// adBlocked and re-auction within the refresh cap.
final class SellwildBoltiveViewTests: ViewTestCase {

    private var sessions: [FakeBoltiveSession] = []
    private var savedSessionCount = 0
    private let zone = "43"
    private let on: [String: Any] = [
        "MOBILE_BOLTIVE_ENABLED": true,
        "MOBILE_BOLTIVE_CLIENT_ID": "boltive-fixture",
        "MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"
    ]

    override func setUp() {
        super.setUp()
        sessions = []
        savedSessionCount = SellwildBoltive.sessionCount
        SellwildBoltiveController.makeSession = { [weak self] clientId, network in
            let session = FakeBoltiveSession(clientId: clientId, network: network)
            self?.sessions.append(session)
            return session
        }
    }

    override func tearDown() {
        SellwildBoltiveController.makeSession = SellwildBoltiveController.liveSession
        SellwildBoltive.sessionCount = savedSessionCount
        super.tearDown()
    }

    // MARK: Controller

    func testAMonitoredRenderCapturesTheBannerWithItsTag() {
        let controller = SellwildBoltiveController()
        let banner = UIView()
        let tag = SellwildBoltiveController.Tag(adUnitId: "43", advertiserId: "brand.example",
                                                sspRefreshCode: "appnexus")

        XCTAssertTrue(controller.renderDidSucceed(bannerView: banner, network: .prebid, remoteValues: on,
                                                  zoneId: zone, tag: tag, roll: 0) { _ in })

        XCTAssertEqual(sessions.count, 1)
        let session = sessions.first
        XCTAssertEqual(session?.clientId, "boltive-fixture")
        XCTAssertEqual(session?.network, .prebid)
        XCTAssertTrue(session?.captured === banner)
        XCTAssertEqual(session?.tag?.advertiserId, "brand.example")
        XCTAssertEqual(session?.tag?.sspRefreshCode, "appnexus")
        XCTAssertEqual(controller.slotCount, 1)
        XCTAssertEqual(SellwildBoltive.sessionCount, savedSessionCount + 1)
    }

    func testABlockReachesTheMainThreadWithTheCapturedBanner() {
        let controller = SellwildBoltiveController()
        let banner = UIView()
        var blocked: [(view: UIView, onMain: Bool)] = []
        controller.renderDidSucceed(bannerView: banner, network: .gam, remoteValues: on, zoneId: zone,
                                    tag: .init(), roll: 0) { blocked.append(($0, Thread.isMainThread)) }

        sessions[0].block()
        XCTAssertEqual(blocked.count, 1, "on the main thread it is delivered at once")
        XCTAssertTrue(blocked[0].view === banner, "the banner, not the subview Boltive hands back")

        let done = expectation(description: "background block")
        DispatchQueue.global().async {
            self.sessions[0].block()
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        spin { blocked.count == 2 }
        XCTAssertEqual(blocked.count, 2)
        XCTAssertTrue(blocked[1].view === banner)
        XCTAssertTrue(blocked[1].onMain, "a block from another thread is posted to main")
    }

    func testABlockForABannerThatIsGoneIsDropped() {
        let controller = SellwildBoltiveController()
        var blocked = 0
        autoreleasepool {
            let banner = UIView()
            controller.renderDidSucceed(bannerView: banner, network: .gam, remoteValues: on, zoneId: zone,
                                        tag: .init(), roll: 0) { _ in blocked += 1 }
        }

        sessions[0].block()

        XCTAssertEqual(blocked, 0)
    }

    func testWithoutBoltiveLinkedNothingIsMonitored() {
        SellwildBoltiveController.makeSession = { _, _ in nil }
        let controller = SellwildBoltiveController()

        XCTAssertFalse(controller.renderDidSucceed(bannerView: UIView(), network: .gam, remoteValues: on,
                                                   zoneId: zone, tag: .init(), roll: 0) { _ in })
        XCTAssertEqual(controller.slotCount, 0)
        XCTAssertEqual(controller.monitorsCreated, 0)
    }

    func testTheLiveMonitorCapturesAGAMBanner() {
        SellwildBoltiveController.makeSession = SellwildBoltiveController.liveSession
        let controller = SellwildBoltiveController()

        XCTAssertTrue(controller.renderDidSucceed(bannerView: UIView(), network: .gam, remoteValues: on,
                                                  zoneId: zone, tag: .init(adUnitId: "/1/app/mrec"), roll: 0) { _ in })
        XCTAssertEqual(controller.monitorsCreated, 1)
        controller.stop()
    }

    // MARK: SellwildAdView

    private func adView(_ overrides: [String: Any], refreshMax: Int) throws -> (SellwildAdView,
                                                                                AdViewDelegateRecorder) {
        var config = try AppConfigFactory.config(on.merging(overrides) { $1 }, partnerCode: "minimal")
        config.gamTag = "/1/app/mrec"
        config.adRefreshMaxMobile = refreshMax
        config.adRefreshInterval = 30
        let view = SellwildAdView(config: config, adSize: .mrec300x250, zoneId: zone)
        let delegate = AdViewDelegateRecorder()
        view.delegate = delegate
        objc_setAssociatedObject(view, &Self.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        return (view, delegate)
    }

    private static var delegateKey: UInt8 = 0

    private func gam(_ view: SellwildAdView) throws -> AdManagerBannerView {
        try XCTUnwrap(view.subviews.compactMap { $0 as? AdManagerBannerView }.first)
    }

    private func prebid(_ view: SellwildAdView) throws -> PrebidBannerView {
        try XCTUnwrap(view.subviews.compactMap { $0 as? PrebidBannerView }.first)
    }

    private func house(_ view: SellwildAdView) -> SellwildHouseAdView? {
        view.subviews.compactMap { $0 as? SellwildHouseAdView }.first
    }

    private func blocked() -> [[String: Any]] {
        recorder.events().filter { $0["event"] as? String == "adBlocked" }
    }

    func testABlockedGAMCreativeIsHiddenForTheHouseAdReportedAndReauctioned() throws {
        network.ready = true
        let (view, delegate) = try adView(["AD_STACK": "both"], refreshMax: 2)
        view.load()
        let banner = try gam(view)
        view.bannerViewDidReceiveAd(banner)
        XCTAssertTrue(sessions.last?.captured === banner)
        XCTAssertEqual(sessions.last?.tag?.adUnitId, "/1/app/mrec")

        sessions.last?.block()

        XCTAssertTrue(banner.isHidden)
        XCTAssertEqual(house(view)?.isHidden, false)
        XCTAssertEqual(delegate.calls.filter { $0.hasPrefix("blocked") }, ["blocked 43"])
        XCTAssertEqual(blocked().map { $0["action"] as? String }, ["gam"])
        XCTAssertEqual(blocked().map { $0["label"] as? String }, ["43"])
        XCTAssertEqual(network.auctions.count, 2, "the block re-auctions at once")

        view.bannerViewDidReceiveAd(banner)
        XCTAssertFalse(banner.isHidden, "the next fill shows the banner again")
        capture.none()
    }

    func testAGAMBlockWithNoRefreshBudgetDoesNotReauction() throws {
        network.ready = true
        let (view, _) = try adView(["AD_STACK": "both", "AD_REFRESH_MAX": 0], refreshMax: 0)
        view.load()
        view.bannerViewDidReceiveAd(try gam(view))

        sessions.last?.block()

        XCTAssertEqual(blocked().count, 1)
        XCTAssertEqual(network.auctions.count, 1)
        XCTAssertEqual(scheduler.pending, [], "and the refresh timer is gone")
    }

    func testAGAMBlockOnceTheCapIsSpentDoesNotReauction() throws {
        network.ready = true
        let (view, _) = try adView(["AD_STACK": "both"], refreshMax: 1)
        view.load()
        let banner = try gam(view)
        view.bannerViewDidReceiveAd(banner)
        sessions.last?.block()
        XCTAssertEqual(network.auctions.count, 2)
        view.bannerViewDidReceiveAd(banner)

        sessions.last?.block()

        XCTAssertEqual(blocked().count, 2)
        XCTAssertEqual(network.auctions.count, 2)
    }

    func testABlockedPrebidCreativeCarriesItsBidderAndReauctionsThroughPrebid() throws {
        network.ready = true
        let (view, _) = try adView(["AD_STACK": "prebidOnly"], refreshMax: 2)
        view.load()
        let banner = try prebid(view)
        let loadsBefore = network.prebidLoads.count
        view.bannerView(banner, didReceiveAdWithAdSize: CGSize(width: 300, height: 250))
        XCTAssertTrue(sessions.last?.captured === banner)
        XCTAssertEqual(sessions.last?.tag?.adUnitId, zone)

        sessions.last?.block()

        XCTAssertTrue(banner.isHidden)
        XCTAssertEqual(house(view)?.isHidden, false)
        XCTAssertEqual(blocked().map { $0["action"] as? String }, ["prebid"], "no bid, so no bidder")
        XCTAssertEqual(network.prebidLoads.count, loadsBefore + 1)
        XCTAssertTrue(network.prebidLoads.last === banner)
    }

    func testAPrebidBlockWithNoRefreshBudgetDoesNotReauction() throws {
        network.ready = true
        let (view, _) = try adView(["AD_STACK": "prebidOnly", "AD_REFRESH_MAX": 0], refreshMax: 0)
        view.load()
        let banner = try prebid(view)
        view.bannerView(banner, didReceiveAdWithAdSize: CGSize(width: 300, height: 250))
        let loadsBefore = network.prebidLoads.count

        sessions.last?.block()

        XCTAssertEqual(blocked().count, 1)
        XCTAssertEqual(network.prebidLoads.count, loadsBefore)
    }

    func testABlockWhileDetachedDoesNotReauction() throws {
        network.ready = true
        let (view, _) = try adView(["AD_STACK": "both"], refreshMax: 3)
        let host = Host()
        host.add(view)
        view.load()
        let banner = try gam(view)
        view.bannerViewDidReceiveAd(banner)
        view.removeFromSuperview()

        sessions.last?.block()

        XCTAssertTrue(banner.isHidden)
        XCTAssertEqual(blocked().count, 1)
        XCTAssertEqual(network.auctions.count, 1)
    }

    func testALateBlockForABannerTheViewDroppedIsIgnored() throws {
        let (view, delegate) = try adView(["AD_STACK": "prebidOnly"], refreshMax: 2)
        view.load()
        let other = PrebidBannerView(frame: .zero, configID: "43", adSize: CGSize(width: 300, height: 250))
        view.bannerView(other, didReceiveAdWithAdSize: CGSize(width: 300, height: 250))

        sessions.last?.block()

        XCTAssertEqual(blocked().count, 0)
        XCTAssertEqual(delegate.calls.filter { $0.hasPrefix("blocked") }, [])
    }

    // MARK: ad.firstLoad

    func testTheFirstRenderOfAZoneIsTimedOncePerProcessAndViewsAreCounted() throws {
        var pushed: [SellwildTimingCore.Event] = []
        var clock: TimeInterval = 50
        SellwildTiming.setDependencies(SellwildTiming.Dependencies(push: { pushed.append($0) }, now: { 1 },
                                                                   uid: { "u" },
                                                                   monotonic: { clock }))
        SellwildTiming.remote = ["TIMING_SAMPLE_RATE": 1]
        network.ready = true
        let (view, _) = try adView(["AD_STACK": "both"], refreshMax: 2)
        let host = Host()
        host.add(view)
        XCTAssertEqual(SellwildViews.adViews, 1)
        view.load()
        clock += 1.5
        let banner = try gam(view)
        view.bannerViewDidReceiveAd(banner)
        view.bannerViewDidReceiveAd(banner)
        let (second, _) = try adView(["AD_STACK": "both"], refreshMax: 2)
        second.load()
        second.bannerViewDidReceiveAd(try gam(second))

        XCTAssertEqual(pushed.map(\.action), ["ad.firstLoad"])
        XCTAssertEqual(pushed.first?.attributes["ms"], "1500")
        XCTAssertEqual(pushed.first?.attributes["zoneId"], "43")
        view.removeFromSuperview()
        XCTAssertEqual(SellwildViews.adViews, 0)
    }

    // MARK: Debug lines

    func testDebugNamesTheRenderTheMonitorAndTheBlock() throws {
        network.ready = true
        let (view, _) = try adView(["AD_STACK": "prebidOnly"], refreshMax: 2)
        view.load()
        let banner = try prebid(view)
        let lines = debugLines {
            view.bannerView(banner, didReceiveAdWithAdSize: .zero)
            sessions.last?.block()
            SellwildBoltiveController().renderDidSucceed(bannerView: UIView(), network: .gam, remoteValues: on,
                                                         zoneId: nil, tag: .init(), roll: 0) { _ in }
        }

        XCTAssertTrue(lines.contains { $0.contains("bid has no size") && $0.contains("bidder ?") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("[prebidOnly] rendered") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("[SellwildBoltive] creative blocked — zone 43") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("[SellwildBoltive] zone ?, gam") }, "\(lines)")
        _ = recorder.events()
    }
}
