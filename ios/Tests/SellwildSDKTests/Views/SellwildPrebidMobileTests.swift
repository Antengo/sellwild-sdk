import XCTest
import UIKit
import GoogleMobileAds
import SellwildPrebidSDK
@testable import SellwildSDK

/// The Prebid/GMA bridge with its third-party calls (SDK start, the auction
/// request, the GAM and Prebid requests) swapped for recorders. Everything
/// else runs for real against the local Prebid and Targeting singletons.
final class SellwildPrebidMobileTests: FailureCapturingTestCase {

    private var started: [String] = []
    private var fetches: [(unit: BannerAdUnit, request: AdManagerRequest)] = []
    private var gamLoads: [(banner: AdManagerBannerView, request: AdManagerRequest)] = []
    private var prebidLoads: [PrebidBannerView] = []
    /// What the recorded auction answers, at once.
    private var answer: ResultCode = .prebidDemandFetchSuccess

    override func setUp() {
        super.setUp()
        SellwildPrebidMobile.resetForTesting()
        SellwildGeoStore.current = nil
        Targeting.shared.setGlobalORTBConfig(nil)
        started = []
        fetches = []
        gamLoads = []
        prebidLoads = []
        SellwildPrebidMobile.calls = SellwildPrebidMobile.Calls(
            startSDKs: { [weak self] url in self?.started.append(url) },
            fetchBannerDemand: { [weak self] unit, request, done in
                guard let self else { return }
                self.fetches.append((unit, request))
                done(self.answer)
            },
            loadGAM: { [weak self] banner, request in self?.gamLoads.append((banner, request)) },
            loadPrebid: { [weak self] banner in self?.prebidLoads.append(banner) }
        )
    }

    override func tearDown() {
        SellwildPrebidMobile.resetForTesting()
        SellwildGeoStore.current = nil
        Targeting.shared.itunesID = nil
        Targeting.shared.storeURL = nil
        Targeting.shared.setGlobalORTBConfig(nil)
        SellwildPrebid.shared.prebidServerAccountId = ""
        SellwildPrebid.shared.pbsDebug = false
        super.tearDown()
    }

    private func globalORTB() throws -> [String: Any] {
        let text = try XCTUnwrap(Targeting.shared.getGlobalORTBConfig())
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: Bootstrap

    func testBootstrapAppliesTheConfigOnceAndStartsTheSDKs() throws {
        var config = try AppConfigFactory.config(["PUBLISHER_ID": "pub-1"], partnerCode: "demo")
        config.prebidServer = PrebidServerConfig(accountId: "acct", endpoint: "https://pbs.example/auction", bidders: [], timeout: 900)
        config.debug = true
        config.pbsDebug = true
        config.appStoreUrl = "https://apps.apple.com/us/app/x/id281940292"
        config.iabCats = ["IAB15"]
        config.geo = SellwildGeo(state: "GA")

        XCTAssertTrue(SellwildPrebidMobile.bootstrap(with: config))
        XCTAssertTrue(SellwildPrebidMobile.bootstrap(with: config))
        XCTAssertEqual(started, ["https://pbs.example/auction"], "only the first call starts the SDKs")
        XCTAssertEqual(SellwildPrebid.shared.prebidServerAccountId, "acct")
        XCTAssertEqual(SellwildPrebid.shared.timeoutMillis, 900)
        XCTAssertTrue(SellwildPrebid.shared.pbsDebug)
        XCTAssertEqual(Targeting.shared.itunesID, "281940292")
        XCTAssertEqual(Targeting.shared.storeURL, "https://apps.apple.com/us/app/x/id281940292")
        XCTAssertEqual(SellwildGeoStore.current, config.geo)

        let ortb = try globalORTB()
        let app = ortb["app"] as? [String: Any]
        XCTAssertEqual((app?["publisher"] as? [String: Any])?["id"] as? String, "pub-1")
        XCTAssertEqual(app?["cat"] as? [String], ["IAB15"])
        let device = ortb["device"] as? [String: Any]
        XCTAssertEqual((device?["geo"] as? [String: Any])?["region"] as? String, "GA")
        XCTAssertEqual(device?["devicetype"] as? Int, SellwildPrebidMobile.deviceType(for: UIDevice.current.userInterfaceIdiom))
        capture.none()
    }

    func testBootstrapFallsBackToTheHostedServerAndKeepsAnEarlierGeo() throws {
        let earlier = SellwildGeo(state: "TX")
        SellwildGeoStore.current = earlier
        var config = try AppConfigFactory.config(partnerCode: "demo")
        config.geo = SellwildGeo(state: "GA")
        SellwildPrebidMobile.bootstrap(with: config)
        XCTAssertEqual(started, [SellwildPrebidConfig.defaultEndpoint])
        XCTAssertEqual(SellwildPrebid.shared.prebidServerAccountId, "demo")
        XCTAssertEqual(SellwildPrebid.shared.timeoutMillis, 1500)
        XCTAssertEqual(SellwildGeoStore.current, earlier, "a geo set before bootstrap wins")
        XCTAssertNil((try globalORTB())["app"])
        capture.none()
    }

    func testAStoreURLWithoutAnIdIsReportedAndStillSent() throws {
        var config = try AppConfigFactory.config(partnerCode: "demo")
        config.appStoreUrl = "https://apps.apple.com/us/app/weatherbug"
        SellwildPrebidMobile.apply(config)
        XCTAssertNil(Targeting.shared.itunesID)
        XCTAssertEqual(Targeting.shared.storeURL, "https://apps.apple.com/us/app/weatherbug")
        let event = capture.only(.configAppStoreUrlInvalid, label: .configure)
        XCTAssertEqual(event?.attributes["severity"], "warn")

        resetCapture()
        config.appStoreUrl = ""
        SellwildPrebidMobile.apply(config)
        config.appStoreUrl = nil
        SellwildPrebidMobile.apply(config)
        capture.none()
    }

    func testPrebidInitOutcomes() {
        XCTAssertFalse(SellwildPrebidMobile.isReady())
        SellwildPrebidMobile.initCompleted(status: "failed", error: PlannedError())
        XCTAssertFalse(SellwildPrebidMobile.isReady())
        let failed = capture.only(.adPrebidInitException, label: .banner)
        XCTAssertEqual(failed?.attributes["severity"], "fatal")
        XCTAssertEqual(failed?.attributes["msg"], "Prebid Mobile init completed with an error: planned test error")

        resetCapture()
        SellwildPrebidMobile.initThrew(PlannedError())
        XCTAssertEqual(capture.only(.adPrebidInitException, label: .banner)?.attributes["msg"],
                       "Prebid Mobile init threw: planned test error")

        resetCapture()
        let lines = debugLines { SellwildPrebidMobile.initCompleted(status: "succeeded", error: nil) }
        XCTAssertTrue(SellwildPrebidMobile.isReady())
        XCTAssertEqual(lines, ["[SellwildPrebidMobile] SellwildPrebid SDK init status: succeeded"])
        capture.none()
    }

    // MARK: Global ORTB

    func testAGlobalORTBThatIsNotJSONIsReported() {
        SellwildPrebidMobile.setGeo(SellwildGeo(lat: .nan))
        XCTAssertNil(Targeting.shared.getGlobalORTBConfig())
        XCTAssertEqual(capture.only(.adOrtbConfigException, label: .banner)?.attributes["severity"], "warn")

        resetCapture()
        SellwildGeoStore.current = SellwildGeo(state: "GA")
        SellwildPrebidMobile.applyGlobalORTB { _ in throw PlannedError() }
        XCTAssertEqual(capture.only(.adOrtbConfigException, label: .banner)?.attributes["errName"], "PlannedError")
    }

    func testSetGeoReEmitsTheORTBConfig() throws {
        SellwildPrebidMobile.setGeo(SellwildGeo(state: "AL"))
        XCTAssertEqual(SellwildGeoStore.current?.state, "AL")
        XCTAssertEqual(((try globalORTB()["device"] as? [String: Any])?["geo"] as? [String: Any])?["region"] as? String, "AL")
        SellwildPrebidMobile.setGeo(nil)
        XCTAssertNil((try globalORTB()["device"] as? [String: Any])?["geo"])
        capture.none()
    }

    // MARK: Auction

    func testTheAuctionAsksForTheBannerThenLoadsGAM() throws {
        let banner = AdManagerBannerView(adSize: AdSizeMediumRectangle)
        var results: [ResultCode] = []
        SellwildPrebidMobile.runBannerAuction(on: banner, configId: "43", adSizes: [CGSize(width: 300, height: 250)]) {
            results.append($0)
        }
        let fetch = try XCTUnwrap(fetches.first)
        XCTAssertEqual(fetch.unit.adFormats, [.banner])
        XCTAssertEqual(fetch.unit.bannerParameters.api?.map(\.value), [Signals.Api.MRAID_3.value, Signals.Api.OMID_1.value])
        XCTAssertNil(fetch.unit.getImpORTBConfig(), "no gpid and no bidder params, no imp.ext")
        XCTAssertEqual(results, [.prebidDemandFetchSuccess])
        XCTAssertTrue(gamLoads.first?.banner === banner)
        XCTAssertTrue(gamLoads.first?.request === fetch.request, "GAM gets the request Prebid filled")
        capture.none()
    }

    func testAVideoAuctionWithAGPIDAndBidderParams() throws {
        let banner = AdManagerBannerView(adSize: AdSizeBanner)
        SellwildPrebidMobile.runBannerAuction(on: banner, configId: "43", adSizes: [], bidderParams: ["IX": ["siteId": "1"]],
                                              gpid: "/1/app#1", video: true) { _ in }
        let unit = try XCTUnwrap(fetches.first?.unit)
        XCTAssertEqual(unit.adFormats, [.banner, .video])
        let ext = try XCTUnwrap(unit.getImpORTBConfig())
        XCTAssertTrue(ext.contains(#""gpid":"\/1\/app#1""#), ext)
        XCTAssertTrue(ext.contains("siteId"), ext)
    }

    func testAnAuctionErrorIsReportedButNoBidsIsNot() throws {
        let banner = AdManagerBannerView(adSize: AdSizeBanner)
        answer = .prebidDemandNoBids
        SellwildPrebidMobile.runBannerAuction(on: banner, configId: "43", adSizes: [CGSize(width: 320, height: 50)]) { _ in }
        capture.none()
        answer = .prebidInvalidConfigId
        SellwildPrebidMobile.runBannerAuction(on: banner, configId: "43", adSizes: [CGSize(width: 320, height: 50)]) { _ in }
        let event = capture.only(.adPrebidAuctionInvalid, label: .banner)
        XCTAssertEqual(event?.attributes["zoneId"], "43")
        XCTAssertEqual(event?.attributes["msg"], "the Prebid auction failed: Prebid server does not recognize config id")
        XCTAssertEqual(gamLoads.count, 2, "GAM still gets the request")
    }

    func testAFreshRenderingBannerHasNoWinningBid() {
        let banner = PrebidBannerView(frame: .zero, configID: "43", adSize: CGSize(width: 300, height: 250))
        XCTAssertNil(SellwildLiveAdNetwork().winningBid(of: banner))
    }

    // MARK: The live ad network

    func testTheLiveAdNetworkGoesThroughTheBridge() throws {
        let live = SellwildLiveAdNetwork()
        live.bootstrap(try AppConfigFactory.config(partnerCode: "demo"))
        XCTAssertEqual(started.count, 1)
        XCTAssertFalse(live.isPrebidReady())
        SellwildPrebidMobile.initCompleted(status: "ok", error: nil)
        XCTAssertTrue(live.isPrebidReady())

        let gam = AdManagerBannerView(adSize: AdSizeBanner)
        live.loadGAM(gam)
        XCTAssertTrue(gamLoads.first?.banner === gam)
        var result: ResultCode?
        live.runBannerAuction(on: gam, configId: "43", adSizes: [CGSize(width: 320, height: 50)], gpid: nil, video: false) {
            result = $0
        }
        XCTAssertEqual(fetches.count, 1)
        XCTAssertEqual(result, .prebidDemandFetchSuccess)

        let rendering = PrebidBannerView(frame: .zero, configID: "43", adSize: CGSize(width: 320, height: 50))
        live.loadPrebid(rendering)
        XCTAssertTrue(prebidLoads.first === rendering)
        XCTAssertNil(live.winningBid(of: rendering))
    }

    // MARK: The run-loop scheduler

    func testTheRunLoopSchedulerFiresOnceAndCanBeCancelled() {
        let scheduler = SellwildRunLoopScheduler()
        let fired = expectation(description: "fired")
        _ = scheduler.schedule(after: 0.01) { fired.fulfill() }
        let cancelled = expectation(description: "cancelled")
        cancelled.isInverted = true
        let token = scheduler.schedule(after: 0.05) { cancelled.fulfill() }
        token.cancel()
        wait(for: [fired, cancelled], timeout: 0.3)
    }
}
