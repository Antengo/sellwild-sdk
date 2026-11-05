import XCTest
import UIKit
import SellwildPrebidSDK
@testable import SellwildSDK

/// The native template: the auction answer, binding a real `NativeAd` from
/// the fork's cache, the tracker callbacks and the asset images (through a
/// stub session).
final class SellwildNativeAdViewTests: ViewTestCase {

    private func makeView(_ overrides: [String: Any] = [:]) throws -> SellwildNativeAdView {
        let config = try AppConfigFactory.config(overrides, partnerCode: "minimal")
        return SellwildNativeAdView(config: config, zoneId: "43", maxHeight: 250)
    }

    private func answer(_ bidInfo: BidInfo) throws {
        let fetch = try XCTUnwrap(nativeFetches.last)
        fetch.done(bidInfo)
    }

    func testLoadAsksForNativeDemandOnce() throws {
        let view = try makeView()
        view.load()
        XCTAssertEqual(nativeFetches.count, 1)
        XCTAssertNil(view.nativeAd, "nothing is bound before the auction answers")
    }

    func testNoFillIsNotAFailure() throws {
        let view = try makeView()
        var failures: [Error] = []
        view.onFailed = { failures.append($0) }
        view.load()
        let lines = try debugLines { try answer(BidInfo(resultCode: .prebidDemandNoBids)) }
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first as? SellwildAdError == .nativeNoFill)
        XCTAssertTrue(lines.contains { $0.contains("no native fill — zone 43") }, "\(lines)")
        capture.none()
    }

    func testNoCachedBidsIsNotAFailureEither() throws {
        let view = try makeView()
        var failures = 0
        view.onFailed = { _ in failures += 1 }
        view.load()
        try answer(BidInfo(resultCode: .prebidDemandNoCachedBids))
        XCTAssertEqual(failures, 1)
        capture.none()
    }

    func testAnAuctionErrorIsReportedOnceAndStillEndsAsNoFill() throws {
        let view = try makeView()
        var failures: [Error] = []
        view.onFailed = { failures.append($0) }
        view.load()
        try answer(BidInfo(resultCode: .prebidServerError))
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first as? SellwildAdError == .nativeNoFill)
        let event = capture.only(.adPrebidAuctionInvalid, label: .native)
        XCTAssertEqual(event?.attributes["msg"], "the native auction failed: Prebid server error")
        XCTAssertEqual(event?.attributes["zoneId"], "43")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    func testAWinWithoutACacheIdIsReported() throws {
        let view = try makeView()
        var failures = 0
        view.onFailed = { _ in failures += 1 }
        view.load()
        try answer(BidInfo(resultCode: .prebidDemandFetchSuccess, targetingKeywords: ["hb_pb": "1.00"]))
        XCTAssertEqual(failures, 1)
        let event = capture.only(.adNativeCreateInvalid, label: .native)
        XCTAssertEqual(event?.attributes["msg"], "a native bid won but carried no local cache id")
        XCTAssertEqual(event?.attributes["zoneId"], "43")
    }

    func testAWinTheCacheDoesNotHoldIsReported() throws {
        let view = try makeView()
        var failures = 0
        view.onFailed = { _ in failures += 1 }
        view.load()
        try answer(BidInfo(resultCode: .prebidDemandFetchSuccess, targetingKeywords: [PrebidLocalCacheIdKey: "Prebid_missing"]))
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(capture.only(.adNativeCreateInvalid, label: .native)?.attributes["msg"],
                       "a native bid won but the native ad could not be created from the cache")
    }

    func testAWinBindsTheAdAndForwardsItsTrackers() throws {
        let view = try makeView()
        var loaded = 0, impressions = 0, clicks = 0
        view.onLoaded = { loaded += 1 }
        view.onImpression = { impressions += 1 }
        view.onClick = { clicks += 1 }
        view.load()
        let cacheId = try XCTUnwrap(try NativeBidFactory.cachedBidId())
        try answer(BidInfo(resultCode: .prebidDemandFetchSuccess, targetingKeywords: [PrebidLocalCacheIdKey: cacheId]))
        spin { loaded == 1 }
        let ad = try XCTUnwrap(view.nativeAd)
        XCTAssertTrue(ad.delegate === view)
        XCTAssertEqual(view.sponsoredLabel.text, "Sponsored")
        XCTAssertEqual(view.ctaButton.title(for: .normal), "Learn more")
        XCTAssertNil(view.titleLabel.text)

        view.adDidLogImpression(ad: ad)
        view.adWasClicked(ad: ad)
        let lines = debugLines { view.adDidExpire(ad: ad) }
        XCTAssertEqual([impressions, clicks], [1, 1])
        XCTAssertEqual(lines, ["[SellwildNativeAdView] native ad expired — zone 43"])
        capture.none()
    }

    func testAnAssetImageIsDownloadedIntoItsView() throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: testPNG()) }
        let view = try makeView()
        view.loadImage("https://cdn.example/icon.png", into: view.iconView)
        spin { view.iconView.image != nil }
        XCTAssertNotNil(view.iconView.image)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.absoluteString }, ["https://cdn.example/icon.png"])
        view.loadImage(nil, into: view.mediaView)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "no asset, no request")
        capture.none()
    }

    func testAnAssetImageThatFailsIsReported() throws {
        let view = try makeView()
        view.loadImage("file:///etc/icon.png", into: view.iconView)
        XCTAssertEqual(capture.only(.adNativeImageNetwork, label: .native)?.attributes["msg"],
                       "native ad image URL is not http(s)")

        resetCapture()
        StubURLProtocol.handler = { _ in .init(status: 404) }
        view.loadImage("https://cdn.example/missing.png", into: view.iconView)
        spin { !self.capture.events.isEmpty }
        let failed = capture.only(.adNativeImageNetwork, label: .native)
        XCTAssertEqual(failed?.attributes["errName"], "HTTPStatusError")
        XCTAssertEqual(failed?.attributes["msg"], "native ad image failed to download: HTTP 404")

        // Behavior change: an error answer is not shown even when its body is an image.
        resetCapture()
        StubURLProtocol.handler = { _ in .init(status: 500, body: testPNG()) }
        view.loadImage("https://cdn.example/error.png", into: view.mediaView)
        spin { !self.capture.events.isEmpty }
        XCTAssertEqual(capture.only(.adNativeImageNetwork, label: .native)?.attributes["msg"],
                       "native ad image failed to download: HTTP 500")
        XCTAssertNil(view.mediaView.image)

        resetCapture()
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("not an image".utf8)) }
        view.loadImage("https://cdn.example/text.png", into: view.mediaView)
        spin { !self.capture.events.isEmpty }
        XCTAssertEqual(capture.only(.adNativeImageNetwork, label: .native)?.attributes["msg"],
                       "native ad image: image data could not be decoded")
        XCTAssertNil(view.mediaView.image)
    }

    func testACancelledDownloadIsNotReported() throws {
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        let view = try makeView()
        view.loadImage("https://cdn.example/icon.png", into: view.iconView)
        spin(timeout: 1) { false }
        capture.none()
    }

    func testTheViewCancelsItsDownloadsWhenItGoes() throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: testPNG()) }
        weak var gone: SellwildNativeAdView?
        try autoreleasepool {
            let view = try makeView()
            view.loadImage("https://cdn.example/icon.png", into: view.iconView)
            gone = view
        }
        spin(timeout: 1) { gone == nil }
        XCTAssertNil(gone)
    }
}
