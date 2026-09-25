import XCTest
import GoogleMobileAds
@_spi(SWPBMInternal) import SellwildPrebidSDK
@testable import SellwildSDK

/// The pure decisions behind SellwildAdView (`SellwildAdPolicy`): refresh,
/// cold start, flags, resume and detach, the GAM unit, the house backdrop,
/// placement validation, no-fill and the native labels.
final class SellwildAdPolicyTests: XCTestCase {

    // MARK: Refresh

    func testRefreshMaxPrefersTheMobileCap() {
        XCTAssertEqual(SellwildAdPolicy.refreshMax(mobile: 3, shared: 5), 3)
        XCTAssertEqual(SellwildAdPolicy.refreshMax(mobile: 0, shared: 5), 5, "only the shared key set still refreshes")
        XCTAssertEqual(SellwildAdPolicy.refreshMax(mobile: 0, shared: 0), 0)
    }

    func testRefreshIntervalIsFlooredAtTenSeconds() {
        XCTAssertEqual(SellwildAdPolicy.refreshInterval(0.03), 10, "a seconds value read as ms cannot storm")
        XCTAssertEqual(SellwildAdPolicy.refreshInterval(30), 30)
        XCTAssertEqual(SellwildAdPolicy.minRefreshInterval, 10)
    }

    func testMayRefreshNeedsRefreshOnAndBudgetLeft() {
        XCTAssertFalse(SellwildAdPolicy.mayRefresh(count: 0, max: 0), "refresh off")
        XCTAssertTrue(SellwildAdPolicy.mayRefresh(count: 1, max: 2))
        XCTAssertFalse(SellwildAdPolicy.mayRefresh(count: 2, max: 2), "budget spent")
    }

    func testPrebidRefreshIsSpentAfterMaxPlusTheFirstRender() {
        XCTAssertFalse(SellwildAdPolicy.prebidRefreshSpent(count: 9, max: 0), "refresh off never stops")
        XCTAssertFalse(SellwildAdPolicy.prebidRefreshSpent(count: 2, max: 2))
        XCTAssertTrue(SellwildAdPolicy.prebidRefreshSpent(count: 3, max: 2))
    }

    // MARK: Cold start

    func testColdStartWaitsEightTimesThenTimesOut() {
        XCTAssertEqual(SellwildAdPolicy.coldStart(ready: true, attempts: 99), .ready)
        XCTAssertEqual(SellwildAdPolicy.coldStart(ready: false, attempts: 0), .wait)
        XCTAssertEqual(SellwildAdPolicy.coldStart(ready: false, attempts: 7), .wait)
        XCTAssertEqual(SellwildAdPolicy.coldStart(ready: false, attempts: 8), .timedOut)
        XCTAssertEqual(SellwildAdPolicy.coldStart(ready: false, attempts: 1, maxAttempts: 1), .timedOut)
        XCTAssertEqual(SellwildAdPolicy.maxPrebidWaitAttempts, 8)
        XCTAssertEqual(SellwildAdPolicy.prebidWaitInterval, 0.15)
    }

    // MARK: Flags

    func testFlagReadsBoolsNumbersAndText() {
        XCTAssertTrue(SellwildAdPolicy.flag(true, default: false))
        XCTAssertFalse(SellwildAdPolicy.flag(false, default: true))
        XCTAssertTrue(SellwildAdPolicy.flag(NSNumber(value: 2), default: false), "any non-zero number is on")
        XCTAssertFalse(SellwildAdPolicy.flag(NSNumber(value: 0.0), default: true))
        for on in ["1", "TRUE", "yes", "On"] { XCTAssertTrue(SellwildAdPolicy.flag(on, default: false), on) }
        for off in ["0", "false", "maybe", ""] { XCTAssertFalse(SellwildAdPolicy.flag(off, default: true), off) }
        XCTAssertTrue(SellwildAdPolicy.flag(nil, default: true), "missing is the default")
        XCTAssertFalse(SellwildAdPolicy.flag(nil, default: false))
        XCTAssertTrue(SellwildAdPolicy.flag(["x"], default: true), "another type is the default")
    }

    // MARK: Resume and detach

    func testResumeReloadsWhenTheFirstAuctionNeverFinished() {
        XCTAssertEqual(SellwildAdPolicy.resumeAction(needsReload: true, stack: .prebidOnly, hasRefreshBudget: false,
                                                     hasRenderedCreative: true, keepCreative: true), .reload)
    }

    func testResumeRestartsTheGAMRefreshTimer() {
        for stack in [SellwildAdStack.both, .gamOnly] {
            XCTAssertEqual(SellwildAdPolicy.resumeAction(needsReload: false, stack: stack, hasRefreshBudget: false,
                                                         hasRenderedCreative: false, keepCreative: false), .scheduleRefresh)
        }
    }

    func testResumeOnPrebidKeepsTheCreativeOnlyWhenOneRenderedAndTheFlagIsOn() {
        XCTAssertEqual(SellwildAdPolicy.resumeAction(needsReload: false, stack: .prebidOnly, hasRefreshBudget: false,
                                                     hasRenderedCreative: true, keepCreative: true), .none,
                       "no refresh budget")
        XCTAssertEqual(SellwildAdPolicy.resumeAction(needsReload: false, stack: .prebidOnly, hasRefreshBudget: true,
                                                     hasRenderedCreative: true, keepCreative: true), .keepPrebidCreative)
        XCTAssertEqual(SellwildAdPolicy.resumeAction(needsReload: false, stack: .prebidOnly, hasRefreshBudget: true,
                                                     hasRenderedCreative: true, keepCreative: false), .reloadPrebid)
        var reads = 0
        func keep() -> Bool { reads += 1; return true }
        XCTAssertEqual(SellwildAdPolicy.resumeAction(needsReload: false, stack: .prebidOnly, hasRefreshBudget: true,
                                                     hasRenderedCreative: false, keepCreative: keep()), .reloadPrebid)
        XCTAssertEqual(reads, 0, "the flag is not read without a creative to keep")
    }

    func testDetachPausesOnceAndResumesOnReattach() {
        XCTAssertEqual(SellwildAdPolicy.detachAction(enabled: false, attached: false, pausedForDetach: false), .none)
        XCTAssertEqual(SellwildAdPolicy.detachAction(enabled: true, attached: false, pausedForDetach: false), .pause)
        XCTAssertEqual(SellwildAdPolicy.detachAction(enabled: true, attached: false, pausedForDetach: true), .none)
        XCTAssertEqual(SellwildAdPolicy.detachAction(enabled: true, attached: true, pausedForDetach: true), .resume)
        XCTAssertEqual(SellwildAdPolicy.detachAction(enabled: true, attached: true, pausedForDetach: false), .none)
    }

    // MARK: GAM ad unit

    func testGAMAdUnitPrefersTheTagThenGAMThenASizedTestUnit() {
        let mrec = CGSize(width: 300, height: 250)
        XCTAssertEqual(SellwildAdPolicy.gamAdUnit(gamTag: "/1/tag", remoteGAM: "/1/gam", size: mrec),
                       .init(id: "/1/tag", isTestFallback: false))
        XCTAssertEqual(SellwildAdPolicy.gamAdUnit(gamTag: "", remoteGAM: "/1/gam", size: mrec),
                       .init(id: "/1/gam", isTestFallback: false))
        XCTAssertEqual(SellwildAdPolicy.gamAdUnit(gamTag: nil, remoteGAM: "", size: mrec),
                       .init(id: SellwildAdPolicy.gamTestAdUnitAdaptive, isTestFallback: true))
        XCTAssertEqual(SellwildAdPolicy.gamAdUnit(gamTag: nil, remoteGAM: 42, size: CGSize(width: 320, height: 50)),
                       .init(id: "/6499/example/banner", isTestFallback: true), "320x50 gets the banner test unit")
        XCTAssertEqual(SellwildAdPolicy.gamAdUnit(gamTag: nil, remoteGAM: nil, size: CGSize(width: 320, height: 100)).id,
                       "/21775744923/example/adaptive-banner")
    }

    // MARK: House backdrop

    func testHouseContentPrefersTheImageThenAnMRECListing() {
        let mrec = CGSize(width: 300, height: 250)
        let banner = CGSize(width: 320, height: 50)
        func show(_ c: SellwildAdPolicy.HouseContent<String, Int>) -> String {
            switch c {
            case .image(let image): return "image \(image)"
            case .listing(let listing): return "listing \(listing)"
            case .none: return "none"
            }
        }
        XCTAssertEqual(show(SellwildAdPolicy.houseContent(enabled: false, image: "a.png", listing: 1, size: mrec)), "none")
        XCTAssertEqual(show(SellwildAdPolicy.houseContent(enabled: true, image: "a.png", listing: 1, size: mrec)), "image a.png")
        XCTAssertEqual(show(SellwildAdPolicy.houseContent(enabled: true, image: nil as String?, listing: 1, size: mrec)), "listing 1")
        XCTAssertEqual(show(SellwildAdPolicy.houseContent(enabled: true, image: nil as String?, listing: 1, size: banner)), "none",
                       "a 320x50 banner is too small for a card")
        XCTAssertEqual(show(SellwildAdPolicy.houseContent(enabled: true, image: nil as String?, listing: nil as Int?, size: mrec)), "none")
        XCTAssertTrue(SellwildAdPolicy.isMREC(CGSize(width: 300, height: 600)))
        XCTAssertFalse(SellwildAdPolicy.isMREC(CGSize(width: 728, height: 90)))
    }

    // MARK: Placement

    func testANonVideoBidNeedsNothing() {
        XCTAssertNil(SellwildAdPolicy.placement(bid: nil, expectedVideo: false, soundEnabled: true))
        XCTAssertNil(SellwildAdPolicy.placement(bid: .init(adm: "<div>banner</div>"), expectedVideo: false, soundEnabled: true))
        XCTAssertNil(SellwildAdPolicy.placement(bid: .init(), expectedVideo: false, soundEnabled: true))
    }

    func testAVideoBidInABannerZoneIsAMismatchAndMuted() {
        var soundReads = 0
        func sound() -> Bool { soundReads += 1; return true }
        for bid in [SellwildAdPolicy.BidSummary(isVideoFormat: true),
                    .init(hasVideoConfig: true),
                    .init(adm: "<?xml?><VAST version=\"4.0\">")] {
            XCTAssertEqual(SellwildAdPolicy.placement(bid: bid, expectedVideo: false, soundEnabled: sound()),
                           .init(mismatch: true, muted: true))
        }
        XCTAssertEqual(soundReads, 0, "sound is read only for a video zone")
    }

    func testAVideoZoneKeepsSoundOnlyWhenSoundIsEnabled() {
        let video = SellwildAdPolicy.BidSummary(isVideoFormat: true)
        XCTAssertEqual(SellwildAdPolicy.placement(bid: video, expectedVideo: true, soundEnabled: true), .init(mismatch: false, muted: false))
        XCTAssertEqual(SellwildAdPolicy.placement(bid: video, expectedVideo: true, soundEnabled: false), .init(mismatch: false, muted: true))
    }

    // MARK: No-fill

    func testGAMNoFillMatchesTheSDKErrorCodes() {
        XCTAssertEqual(SellwildAdPolicy.gamErrorDomain, RequestError.errorDomain)
        XCTAssertEqual(RequestError.Code.noFill.rawValue, 1)
        XCTAssertTrue(SellwildAdPolicy.isGAMNoFill(NSError(domain: RequestError.errorDomain, code: RequestError.Code.noFill.rawValue)))
        XCTAssertTrue(SellwildAdPolicy.isGAMNoFill(NSError(domain: RequestError.errorDomain, code: 9)), "mediation no-fill")
        XCTAssertFalse(SellwildAdPolicy.isGAMNoFill(NSError(domain: RequestError.errorDomain, code: RequestError.Code.networkError.rawValue)))
        XCTAssertFalse(SellwildAdPolicy.isGAMNoFill(NSError(domain: "other", code: 1)))
    }

    func testPrebidNoFillMatchesTheForkErrors() {
        XCTAssertEqual(SellwildAdPolicy.prebidResultCodeKey, PrebidConstants.FETCH_DEMAND_RESULT_KEY)
        XCTAssertTrue(SellwildAdPolicy.isPrebidNoFill(SWPBMError.noWinningBid()))
        XCTAssertTrue(SellwildAdPolicy.isPrebidNoFill(SWPBMError.noCachedBids()))
        XCTAssertTrue(SellwildAdPolicy.isPrebidNoFill(SWPBMError.blankResponse()))
        XCTAssertFalse(SellwildAdPolicy.isPrebidNoFill(SWPBMError.prebidInvalidConfigId()))
        XCTAssertFalse(SellwildAdPolicy.isPrebidNoFill(NSError(domain: SellwildAdPolicy.prebidErrorDomain, code: -1)),
                       "no result code")
        XCTAssertFalse(SellwildAdPolicy.isPrebidNoFill(URLError(.timedOut)))
    }

    func testAuctionFailuresAreEveryResultButSuccessAndNoBids() {
        XCTAssertEqual(ResultCode.prebidDemandFetchSuccess.rawValue, SellwildAdPolicy.prebidSuccessCode)
        XCTAssertFalse(SellwildAdPolicy.isAuctionFailure(ResultCode.prebidDemandFetchSuccess.rawValue))
        XCTAssertFalse(SellwildAdPolicy.isAuctionFailure(ResultCode.prebidDemandNoBids.rawValue))
        XCTAssertFalse(SellwildAdPolicy.isAuctionFailure(ResultCode.prebidDemandNoCachedBids.rawValue))
        XCTAssertTrue(SellwildAdPolicy.isAuctionFailure(ResultCode.prebidInvalidConfigId.rawValue))
        XCTAssertTrue(SellwildAdPolicy.isAuctionFailure(ResultCode.prebidDemandTimedOut.rawValue))
    }

    // MARK: Native labels

    func testNativeLabels() {
        XCTAssertEqual(SellwildAdPolicy.sponsoredText("Acme"), "Sponsored · Acme")
        XCTAssertEqual(SellwildAdPolicy.sponsoredText(nil), "Sponsored")
        XCTAssertEqual(SellwildAdPolicy.callToActionText("Shop now"), "Shop now")
        XCTAssertEqual(SellwildAdPolicy.callToActionText(""), "Learn more")
        XCTAssertEqual(SellwildAdPolicy.callToActionText(nil), "Learn more")
    }
}
