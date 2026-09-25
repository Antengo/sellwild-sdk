import XCTest
import UIKit
import AVFoundation
import GoogleMobileAds
@_spi(SWPBMInternal) import SellwildPrebidSDK
@testable import SellwildSDK

/// The SellwildAdView shell with fake GMA and Prebid, manual timers and a
/// captured events queue. Remote config comes from the app-config factory;
/// typed config fields are set in code, as an app would.
final class SellwildAdViewTests: ViewTestCase {

    private func adConfig(_ overrides: [String: Any] = [:], gamTag: String? = "/1/app/mrec") throws -> SellwildConfig {
        var config = try AppConfigFactory.config(overrides, partnerCode: "minimal")
        config.gamTag = gamTag
        return config
    }

    private func makeView(_ config: SellwildConfig, size: SellwildAdSize = .mrec300x250,
                          zone: String? = "43") -> (SellwildAdView, AdViewDelegateRecorder) {
        let view = SellwildAdView(config: config, adSize: size, zoneId: zone)
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

    private func native(_ view: SellwildAdView) -> SellwildNativeAdView? {
        view.subviews.compactMap { $0 as? SellwildNativeAdView }.first
    }

    private func house(_ view: SellwildAdView) -> SellwildHouseAdView? {
        view.subviews.compactMap { $0 as? SellwildHouseAdView }.first
    }

    // MARK: Init

    func testInitStampsThePartnerAndTheKillSwitchAndReservesEverySize() throws {
        let off = try adConfig(["EVENTS_ENABLED": false, "BANNER_SIZES": ["728x90"]])
        let (view, _) = makeView(off)
        XCTAssertFalse(recorder.client.eventsEnabled)
        XCTAssertEqual(recorder.client.partnerCode, "minimal")
        XCTAssertEqual(SellwildFailures.context.partnerCode, "minimal", "failure reports carry the partner too")
        XCTAssertEqual(view.frame.size, CGSize(width: 728, height: 250), "the widest and tallest requested size")
        _ = SellwildAdView(config: try adConfig(), adSize: .banner320x50)
        XCTAssertTrue(recorder.client.eventsEnabled)
    }

    func testAStoryboardInitIsReportedBeforeItTraps() {
        SellwildAdView.reportUnsupportedInit()
        XCTAssertEqual(capture.only(.adViewInitUnsupported, label: .banner)?.attributes["severity"], "fatal")
    }

    func testTheLiveEnvironmentResolvesGrowthCodeAndWatchesTheQueue() throws {
        let live = SellwildAdView.Environment.live
        XCTAssertTrue(live.events === SellwildAPIClient.shared)
        XCTAssertTrue(live.network is SellwildLiveAdNetwork)
        live.resolveGrowthCode(try adConfig(), "43")
        capture.none()
    }

    func testErrorsDescribeThemselves() {
        XCTAssertEqual(SellwildAdError.missingZoneIdForPrebidOnly.errorDescription,
                       "SellwildAdView resolved to .prebidOnly but has no zoneId; Prebid rendering requires a configId.")
        XCTAssertEqual(SellwildAdError.nativeNoFill.localizedDescription, "Native demand request returned no fill.")
    }

    // MARK: .both

    func testBothRunsTheAuctionIntoAGAMBanner() throws {
        network.ready = true
        let (view, _) = makeView(try adConfig(["GPID_BASE": "/1/app"]))
        let lines = debugLines {
            view.load()
            network.auctions.first?.completion(.prebidDemandFetchSuccess)
        }
        XCTAssertEqual(network.bootstraps, ["minimal"])
        XCTAssertEqual(growthCodeZones, ["43"])
        let auction = try XCTUnwrap(network.auctions.first)
        XCTAssertEqual(auction.configId, "43")
        XCTAssertEqual(auction.adSizes, [CGSize(width: 300, height: 250)])
        XCTAssertEqual(auction.gpid, "/1/app")
        XCTAssertFalse(auction.video)
        XCTAssertTrue(auction.banner === gam(view))
        XCTAssertEqual(gam(view)?.adUnitID, "/1/app/mrec")
        XCTAssertTrue(network.gamLoads.isEmpty, "the auction sends the GAM request")
        XCTAssertTrue(lines.contains { $0.contains("Prebid auction result: Prebid demand fetch successful") }, "\(lines)")
        capture.none()
    }

    func testTheGPIDOverrideWinsAndVideoIsAsked() throws {
        network.ready = true
        let (view, _) = makeView(try adConfig(["GPID_BASE": "/1/app", "VIDEO_ENABLED": true]))
        view.gpidOverride = "/1/app#2"
        view.load()
        XCTAssertEqual(network.auctions.first?.gpid, "/1/app#2")
        XCTAssertEqual(network.auctions.first?.video, true)
    }

    func testAMissingGAMUnitFallsBackToTheTestUnitAndIsReportedOnceALaunch() throws {
        network.ready = true
        let (mrec, _) = makeView(try adConfig(gamTag: nil))
        mrec.load()
        mrec.load()
        XCTAssertEqual(gam(mrec)?.adUnitID, SellwildAdPolicy.gamTestAdUnitAdaptive)
        let (banner, _) = makeView(try adConfig(gamTag: nil), size: .banner320x50)
        banner.load()
        XCTAssertEqual(gam(banner)?.adUnitID, SellwildAdPolicy.gamTestAdUnitBanner)
        let event = capture.only(.adGamUnitMissing, label: .banner)
        XCTAssertEqual(event?.attributes["severity"], "fatal")
        XCTAssertEqual(event?.attributes["zoneId"], "43")
    }

    func testBothWithoutAZoneSendsAPlainGAMRequestAndReportsItOnce() throws {
        let (view, _) = makeView(try adConfig(), zone: nil)
        view.load()
        view.load()
        XCTAssertEqual(network.gamLoads.count, 2)
        XCTAssertTrue(network.auctions.isEmpty)
        XCTAssertEqual(capture.only(.adZoneMissing, label: .banner)?.attributes["severity"], "warn")
    }

    func testGAMOnlySendsAPlainRequestAndNothingIsReported() throws {
        let (view, _) = makeView(try adConfig(["AD_STACK": "gamOnly"]))
        view.load()
        XCTAssertEqual(network.gamLoads.count, 1)
        XCTAssertTrue(network.auctions.isEmpty)
        capture.none()
    }

    func testColdStartWaitsForPrebidThenTimesOutOnceALaunch() throws {
        let (view, _) = makeView(try adConfig())
        view.load()
        XCTAssertEqual(scheduler.pending, [0.15])
        for _ in 0..<8 { scheduler.fire() }
        XCTAssertEqual(network.auctions.count, 1, "after 8 waits the auction runs anyway")
        XCTAssertEqual(scheduler.pending, [])
        XCTAssertEqual(capture.only(.adPrebidInitTimeout, label: .banner)?.attributes["zoneId"], "43")

        view.load()
        for _ in 0..<8 { scheduler.fire() }
        XCTAssertEqual(network.auctions.count, 2)
        XCTAssertEqual(capture.calls, 1, "reported once a launch")
    }

    func testReadyMidWaitRunsTheAuctionWithoutAReport() throws {
        let (view, _) = makeView(try adConfig())
        view.load()
        network.ready = true
        scheduler.fire()
        XCTAssertEqual(network.auctions.count, 1)
        capture.none()
    }

    func testAViewThatIsGoneCancelsItsTimers() throws {
        let plain = try adConfig()
        weak var gone: SellwildAdView?
        autoreleasepool {
            let view = SellwildAdView(config: plain, adSize: .mrec300x250, zoneId: "43")
            view.load()
            gone = view
        }
        XCTAssertNil(gone)
        XCTAssertEqual(scheduler.items.count, 1)
        XCTAssertTrue(scheduler.items.allSatisfy(\.cancelled), "deinit cancelled the cold-start wait")
        scheduler.fire()
        XCTAssertTrue(network.auctions.isEmpty)
    }

    func testPausedMidWaitLoadsAgainOnResume() throws {
        let (view, _) = makeView(try adConfig())
        view.load()
        view.pause()
        XCTAssertEqual(scheduler.pending, [], "the wait is cancelled")
        view.resume()
        XCTAssertEqual(network.bootstraps.count, 2, "resume re-issues load()")
        XCTAssertEqual(scheduler.pending, [0.15])
    }

    // MARK: GAM callbacks

    func testAGAMFillHidesTheHouseAdReportsAndRefreshes() throws {
        network.ready = true
        var config = try adConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"])
        config.adRefreshMaxMobile = 2
        config.adRefreshInterval = 30
        let (view, delegate) = makeView(config)
        view.load()
        XCTAssertEqual(house(view)?.isHidden, false, "the house backdrop sits behind the slot")
        let banner = try XCTUnwrap(gam(view))
        let lines = debugLines { view.bannerViewDidReceiveAd(banner) }
        XCTAssertEqual(house(view)?.isHidden, true)
        XCTAssertEqual(delegate.calls, ["load", "size", "impression 43"])
        XCTAssertEqual(delegate.sizes, [banner.adSize.size])
        XCTAssertEqual(recorder.names(), ["adRenderSucceeded", "firstAdViewed"])
        XCTAssertTrue(lines.contains { $0.contains("firstAdViewed fired once") })
        XCTAssertEqual(scheduler.pending, [30])

        scheduler.fire()
        XCTAssertEqual(network.auctions.count, 2, "the refresh loads again")
        view.bannerViewDidReceiveAd(banner)
        XCTAssertEqual(recorder.names(), ["adRenderSucceeded", "firstAdViewed", "adRenderSucceeded"], "firstAdViewed once a surface")
        scheduler.fire()
        view.bannerViewDidReceiveAd(banner)
        XCTAssertEqual(scheduler.pending, [], "the refresh budget (2) is spent")
        capture.none()
    }

    func testAGAMNoFillShowsTheHouseAdAndIsNotAFailure() throws {
        network.ready = true
        var config = try adConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"])
        config.adRefreshMax = 1
        let (view, delegate) = makeView(config)
        view.load()
        let banner = try XCTUnwrap(gam(view))
        view.bannerViewDidReceiveAd(banner)
        let noFill = NSError(domain: RequestError.errorDomain, code: RequestError.Code.noFill.rawValue)
        view.bannerView(banner, didFailToReceiveAdWithError: noFill)
        XCTAssertEqual(house(view)?.isHidden, false)
        XCTAssertEqual(Array(delegate.calls.suffix(2)), ["fail", "house 43"])
        XCTAssertEqual(recorder.events().last?["event"] as? String, "adError")
        XCTAssertEqual(recorder.events().last?["label"] as? String, "43")
        capture.none()
    }

    func testAGAMLoadErrorIsReportedAndStillSendsAdError() throws {
        network.ready = true
        let (view, delegate) = makeView(try adConfig())
        view.load()
        let banner = try XCTUnwrap(gam(view))
        let error = NSError(domain: RequestError.errorDomain, code: RequestError.Code.networkError.rawValue)
        view.bannerView(banner, didFailToReceiveAdWithError: error)
        XCTAssertEqual(delegate.calls, ["fail"], "no house ad configured, so no house impression")
        XCTAssertEqual(recorder.names(), ["adError"])
        let event = capture.only(.adGamLoadException, label: .banner)
        XCTAssertEqual(event?.attributes["zoneId"], "43")
        XCTAssertEqual(event?.attributes["errName"], "com.google.admob(2)")
    }

    func testAGAMClickIsForwarded() throws {
        let (view, delegate) = makeView(try adConfig(["AD_STACK": "gamOnly"]), zone: nil)
        view.load()
        view.bannerViewDidRecordClick(try XCTUnwrap(gam(view)))
        XCTAssertEqual(delegate.calls, ["click"])
        XCTAssertEqual(recorder.events().first?["event"] as? String, "click")
        XCTAssertEqual(recorder.events().first?["label"] as? String, "")
    }

    // MARK: .prebidOnly

    func testPrebidOnlyWithoutAZoneReportsAndLoadsNothing() throws {
        let (view, delegate) = makeView(try adConfig(["AD_STACK": "prebidOnly"]), zone: "")
        view.load()
        view.load()
        XCTAssertTrue(network.prebidLoads.isEmpty)
        XCTAssertEqual(delegate.calls, ["fail", "fail"])
        XCTAssertTrue(delegate.errors.first is SellwildAdError)
        XCTAssertEqual(capture.only(.adZoneMissing, label: .banner)?.attributes["severity"], "error")
    }

    func testPrebidOnlyLoadsTheRenderingBannerWithTheGPID() throws {
        network.ready = true
        var config = try adConfig(["AD_STACK": "prebidOnly", "GPID_BASE": "/1/app"])
        config.adRefreshMaxMobile = 2
        let (view, _) = makeView(config)
        view.load()
        let banner = try XCTUnwrap(prebid(view))
        XCTAssertTrue(network.prebidLoads.first === banner)
        XCTAssertEqual(banner.configID, "43")
        XCTAssertNil(gam(view))
        capture.none()
    }

    func testPrebidOnlyWaitsForPrebidToo() throws {
        let (view, _) = makeView(try adConfig(["AD_STACK": "prebidOnly", "VIDEO_ENABLED": true]))
        view.load()
        XCTAssertTrue(network.prebidLoads.isEmpty)
        network.ready = true
        scheduler.fire()
        XCTAssertEqual(network.prebidLoads.count, 1)
    }

    func testAPrebidRenderCapsRefreshAndMutesAVideoInABannerZone() throws {
        network.ready = true
        var config = try adConfig(["AD_STACK": "prebidOnly"])
        config.adRefreshMaxMobile = 1
        let (view, delegate) = makeView(config)
        view.load()
        let banner = try XCTUnwrap(prebid(view))
        let player = PlayerLayerView()
        player.playerLayer?.player = AVPlayer()
        let inner = UIView()
        inner.addSubview(player)
        banner.addSubview(inner)
        network.bid = SellwildAdPolicy.BidSummary(isVideoFormat: true)

        view.bannerView(banner, didReceiveAdWithAdSize: CGSize(width: 300, height: 250))
        XCTAssertEqual(player.playerLayer?.player?.isMuted, true)
        XCTAssertEqual(delegate.calls, ["load", "size", "impression 43"])
        XCTAssertEqual(recorder.names(), ["placementMismatch", "adRenderSucceeded", "firstAdViewed"])
        XCTAssertEqual(capture.only(.adPlacementInvalid, label: .banner)?.attributes["zoneId"], "43")

        view.bannerView(banner, didReceiveAdWithAdSize: CGSize(width: 320, height: 50))
        XCTAssertEqual(delegate.sizes.last, CGSize(width: 320, height: 50))
    }

    func testAVideoZoneKeepsItsSoundAndABannerBidChangesNothing() throws {
        network.ready = true
        let (view, _) = makeView(try adConfig(["AD_STACK": "prebidOnly", "VIDEO_ENABLED": true, "VIDEO_SOUND_ENABLED": true]))
        view.load()
        let banner = try XCTUnwrap(prebid(view))
        let player = PlayerLayerView()
        player.playerLayer?.player = AVPlayer()
        player.playerLayer?.player?.isMuted = true
        banner.addSubview(player)
        network.bid = SellwildAdPolicy.BidSummary(adm: "<VAST version=\"4.0\"></VAST>")
        view.bannerView(banner, didReceiveAdWithAdSize: CGSize(width: 300, height: 250))
        XCTAssertEqual(player.playerLayer?.player?.isMuted, false)

        network.bid = nil
        player.playerLayer?.player?.isMuted = true
        view.bannerView(banner, didReceiveAdWithAdSize: CGSize(width: 300, height: 250))
        XCTAssertEqual(player.playerLayer?.player?.isMuted, true, "a banner bid leaves players alone")
        XCTAssertFalse(recorder.names().contains("placementMismatch"))
        capture.none()
    }

    func testAPrebidNoBidIsNotAFailureButOtherErrorsAre() throws {
        network.ready = true
        let (view, delegate) = makeView(try adConfig(["AD_STACK": "prebidOnly"]))
        view.load()
        let banner = try XCTUnwrap(prebid(view))
        view.bannerView(banner, didFailToReceiveAdWith: SWPBMError.noWinningBid())
        capture.none()
        view.bannerView(banner, didFailToReceiveAdWith: SWPBMError.prebidInvalidConfigId())
        XCTAssertEqual(capture.only(.adPrebidRenderException, label: .banner)?.attributes["zoneId"], "43")
        XCTAssertEqual(delegate.calls, ["fail", "fail"])
        XCTAssertEqual(recorder.names(), ["adError", "adError"])
    }

    func testThePresenterIsTheHostOrReported() throws {
        let (view, _) = makeView(try adConfig())
        XCTAssertNil(view.bannerViewPresentationController())
        XCTAssertEqual(capture.only(.adPresenterMissing, label: .banner)?.attributes["zoneId"], "43")
        let host = Host()
        host.add(view)
        XCTAssertTrue(view.bannerViewPresentationController() === host.controller)
    }

    // MARK: Resume and detach

    func testResumeKeepsARenderedPrebidCreativeWhenTheFlagIsOn() throws {
        network.ready = true
        var config = try adConfig(["AD_STACK": "prebidOnly", "MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH": "yes"])
        config.adRefreshMaxMobile = 3
        config.adRefreshInterval = 12
        let (view, _) = makeView(config)
        let host = Host()
        host.add(view)
        view.load()
        let banner = try XCTUnwrap(prebid(view))
        view.bannerView(banner, didReceiveAdWithAdSize: CGSize(width: 300, height: 250))
        view.pause()
        view.resume()
        XCTAssertEqual(network.prebidLoads.count, 1, "the creative stays")
        XCTAssertEqual(scheduler.pending, [12])
        scheduler.fire()
        XCTAssertEqual(network.prebidLoads.count, 2, "re-auctions after one interval while attached")

        view.resume()
        view.removeFromSuperview()
        view.resume()
        scheduler.fire()
        XCTAssertEqual(network.prebidLoads.count, 2, "no re-auction off the window")
    }

    func testResumeReauctionsAPrebidBannerByDefault() throws {
        network.ready = true
        var config = try adConfig(["AD_STACK": "prebidOnly"])
        config.adRefreshMax = 2
        let (view, _) = makeView(config)
        view.resume()
        XCTAssertTrue(network.prebidLoads.isEmpty, "no banner yet")
        view.load()
        view.resume()
        XCTAssertEqual(network.prebidLoads.count, 2)
        let banner = try XCTUnwrap(prebid(view))
        view.bannerView(banner, didReceiveAdWithAdSize: CGSize(width: 300, height: 250))
        view.resume()
        XCTAssertEqual(network.prebidLoads.count, 3, "the flag is off, so the creative is replaced")
    }

    func testResumeDoesNothingForPrebidWithRefreshOffOrItsBudgetSpent() throws {
        network.ready = true
        let (off, _) = makeView(try adConfig(["AD_STACK": "prebidOnly"]))
        off.load()
        off.resume()
        XCTAssertEqual(network.prebidLoads.count, 1)

        var spent = try adConfig(["AD_STACK": "prebidOnly", "MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH": true])
        spent.adRefreshMaxMobile = 1
        let (view, _) = makeView(spent)
        view.load()
        let banner = try XCTUnwrap(prebid(view))
        view.bannerView(banner, didReceiveAdWithAdSize: .zero)
        view.bannerView(banner, didReceiveAdWithAdSize: .zero)
        view.resume()
        XCTAssertEqual(scheduler.pending, [], "no refresh left to schedule")
    }

    func testDetachPausesAndReattachResumesTheGAMRefresh() throws {
        network.ready = true
        var config = try adConfig()
        config.adRefreshMaxMobile = 5
        let (view, _) = makeView(config)
        let host = Host()
        host.add(view)
        view.load()
        view.bannerViewDidReceiveAd(try XCTUnwrap(gam(view)))
        XCTAssertEqual(scheduler.pending, [30])
        view.removeFromSuperview()
        XCTAssertEqual(scheduler.pending, [], "paused while detached")
        host.add(view)
        XCTAssertEqual(scheduler.pending, [30], "resumed on reattach")
        host.add(view)
        XCTAssertEqual(scheduler.pending, [30], "a second attach changes nothing")
    }

    func testDetachPauseCanBeTurnedOff() throws {
        network.ready = true
        var config = try adConfig(["MOBILE_PAUSE_REFRESH_DETACHED": false])
        config.adRefreshMaxMobile = 5
        let (view, _) = makeView(config)
        let host = Host()
        host.add(view)
        view.load()
        view.bannerViewDidReceiveAd(try XCTUnwrap(gam(view)))
        view.removeFromSuperview()
        XCTAssertEqual(scheduler.pending, [30], "refresh keeps running")
    }

    // MARK: Native

    func testNativeLoadsTheTemplateAndForwardsItsCallbacks() throws {
        network.ready = true
        let (view, delegate) = makeView(try adConfig(["AD_STACK": "prebidOnly", "NATIVE_ENABLED": true,
                                                    "NATIVE_MAX_HEIGHT": 200,
                                                    "MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"]))
        view.load()
        let template = try XCTUnwrap(native(view))
        XCTAssertEqual(nativeFetches.count, 1, "the template asked for native demand")
        XCTAssertNil(prebid(view))

        template.onLoaded?()
        XCTAssertEqual(house(view)?.isHidden, true)
        XCTAssertEqual(delegate.calls, ["load", "size", "impression 43"])
        XCTAssertEqual(delegate.sizes, [CGSize(width: 300, height: 200)])
        template.onClick?()
        XCTAssertEqual(delegate.calls.last, "click")
        template.onFailed?(SellwildAdError.nativeNoFill)
        XCTAssertEqual(delegate.calls.last, "fail", "the house ad is hidden after the fill, so no house impression")
        XCTAssertEqual(recorder.names(), ["adRenderSucceeded", "firstAdViewed", "click", "adError"])
        capture.none()
    }

    func testANativeNoFillShowsTheHouseImpression() throws {
        network.ready = true
        let (view, delegate) = makeView(try adConfig(["AD_STACK": "prebidOnly", "NATIVE_ENABLED": true,
                                                    "MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"]))
        view.load()
        native(view)?.onFailed?(SellwildAdError.nativeNoFill)
        XCTAssertEqual(delegate.calls, ["fail", "house 43"])
        capture.none()
    }

    func testNativeWithoutAZoneReportsUnderNative() throws {
        let (view, delegate) = makeView(try adConfig(["AD_STACK": "prebidOnly", "NATIVE_ENABLED": true]), zone: nil)
        view.load()
        XCTAssertEqual(delegate.calls, ["fail"])
        XCTAssertNil(native(view))
        XCTAssertEqual(capture.only(.adZoneMissing, label: .native)?.attributes["severity"], "error")
    }

    func testNativeWaitsForPrebid() throws {
        let (view, _) = makeView(try adConfig(["AD_STACK": "prebidOnly", "NATIVE_ENABLED": true]))
        view.load()
        XCTAssertNil(native(view))
        network.ready = true
        scheduler.fire()
        XCTAssertNotNil(native(view))
    }

    func testSwitchingStacksTearsDownTheOtherRenderPaths() throws {
        network.ready = true
        let plain = try adConfig()
        let withNative = try adConfig(["NATIVE_ENABLED": true])
        let (view, _) = makeView(plain)
        func load(_ stack: SellwildAdStack, _ config: SellwildConfig) {
            view.adStackOverride = stack
            view.config = config
            view.load()
        }
        load(.both, plain)
        let firstGAM = try XCTUnwrap(gam(view))
        load(.prebidOnly, plain)
        XCTAssertNil(gam(view), "Prebid replaces GAM")
        let banner = try XCTUnwrap(prebid(view))
        load(.prebidOnly, plain)
        XCTAssertTrue(prebid(view) === banner, "the Prebid banner is reused")
        load(.prebidOnly, withNative)
        XCTAssertNil(prebid(view), "native replaces the Prebid banner")
        let template = try XCTUnwrap(native(view))
        load(.prebidOnly, withNative)
        XCTAssertTrue(native(view) === template, "the template is reused")
        load(.prebidOnly, plain)
        XCTAssertNil(native(view), "the Prebid banner replaces the template")
        XCTAssertNotNil(prebid(view))
        load(.both, plain)
        XCTAssertNil(prebid(view), "GAM replaces the Prebid banner")
        XCTAssertFalse(gam(view) === firstGAM, "a new GAM banner after the teardown")
        load(.prebidOnly, withNative)
        XCTAssertNil(gam(view), "native replaces GAM")
        XCTAssertNotNil(native(view))
        load(.gamOnly, plain)
        XCTAssertNil(native(view), "GAM replaces the template")
        XCTAssertNotNil(gam(view))
    }

    // MARK: House ad

    func testTheHouseImageOpensItsClickURL() throws {
        let (view, _) = makeView(try adConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png",
                                             "MOBILE_HOUSE_AD_URL": "https://sellwild.com/deal"]))
        view.load()
        house(view)?.onTap?()
        XCTAssertEqual(opened.map(\.absoluteString), ["https://sellwild.com/deal"])
        capture.none()
    }

    func testAHouseClickURLThatIsNotHTTPIsReportedAndNotOpened() throws {
        let (view, _) = makeView(try adConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png",
                                             "MOBILE_HOUSE_AD_URL": "tel:5551234"]))
        view.load()
        house(view)?.onTap?()
        XCTAssertEqual(opened, [])
        XCTAssertEqual(capture.only(.houseOpenUrlInvalid, label: .house)?.attributes["zoneId"], "43")
    }

    func testAHouseImageWithoutAClickURLDoesNothingOnTap() throws {
        let (view, _) = makeView(try adConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"]))
        view.load()
        house(view)?.onTap?()
        XCTAssertEqual(opened, [])
        capture.none()
    }

    func testAFeedListingBackfillsAnMRECAndOpensTheListing() throws {
        let listing = try ListingFactory.decoded(ListingFactory.make(["url": "https://sellwild.com/listing/9"]))
        let (view, _) = makeView(try adConfig())
        view.houseFallbackListing = listing
        view.load()
        let backdrop = try XCTUnwrap(house(view))
        XCTAssertFalse(backdrop.isHidden)
        XCTAssertEqual(backdrop.titleLabel.text, listing.title)
        backdrop.onTap?()
        XCTAssertEqual(opened.map(\.absoluteString), ["https://sellwild.com/listing/9"])

        let (banner, _) = makeView(try adConfig(), size: .banner320x50)
        banner.houseFallbackListing = listing
        banner.load()
        XCTAssertNil(house(banner), "a 320x50 banner is too small for a card")
    }

    func testTurningHouseAdsOffHidesTheBackdropOnTheNextLoad() throws {
        let (view, _) = makeView(try adConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"]))
        view.load()
        let backdrop = try XCTUnwrap(house(view))
        view.config = try adConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png",
                                  "MOBILE_HOUSE_AD_ENABLED": false])
        view.load()
        XCTAssertTrue(backdrop.isHidden)
        view.config = try adConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"])
        view.load()
        XCTAssertTrue(house(view) === backdrop, "the backdrop is reused")
        XCTAssertFalse(backdrop.isHidden)
    }

    // MARK: First ad viewed

    func testTheFirstAdViewedGuardRunsItsBlockOnce() {
        let guardian = SellwildFirstAdViewedGuard()
        var runs = 0
        guardian.fireOnce { runs += 1 }
        guardian.fireOnce { runs += 1 }
        XCTAssertEqual(runs, 1)
    }
}
