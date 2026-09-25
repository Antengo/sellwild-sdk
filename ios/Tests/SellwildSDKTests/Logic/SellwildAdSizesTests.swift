import XCTest
import GoogleMobileAds
import SellwildPrebidSDK
@testable import SellwildSDK

/// Multi-size banners: remote size parsing (every accepted shape), the
/// report for dropped entries, and the per-stack apply helpers on locally
/// built GAM and Prebid views (nothing is loaded).
final class SellwildAdSizesTests: FailureCapturingTestCase {

    private let mrec = CGSize(width: 300, height: 250)
    private let banner = CGSize(width: 320, height: 50)

    private func sizes(_ overrides: [String: Any], zone: String? = "43") throws -> [CGSize] {
        SellwildAdSizes.resolve(remoteValues: try AppConfigFactory.remote(overrides), zoneId: zone, primary: mrec)
    }

    // MARK: resolve

    func testPrimaryOnlyWhenNothingIsConfigured() throws {
        XCTAssertEqual(SellwildAdSizes.resolve(remoteValues: nil, zoneId: nil, primary: mrec), [mrec])
        XCTAssertEqual(try sizes([:]), [mrec])
        XCTAssertEqual(try sizes(["BANNER_SIZES": ""]), [mrec], "'' is the CMS's unset")
        XCTAssertEqual(try Factory.offSchema(because: "BANNER_SIZES null is outside the schema; the SDK reads it as unset") {
            try sizes(["BANNER_SIZES": NSNull()])
        }, [mrec])
        capture.none()
    }

    func testEveryAcceptedShape() throws {
        XCTAssertEqual(try sizes(["BANNER_SIZES": ["300x250", "320X50", " 728 x 90 "]]),
                       [mrec, banner, CGSize(width: 728, height: 90)], "primary first, duplicates removed")
        XCTAssertEqual(try sizes(["BANNER_SIZES": [[320, 50], ["728", "90"]]]), [mrec, banner, CGSize(width: 728, height: 90)])
        XCTAssertEqual(try sizes(["BANNER_SIZES": "[\"320x50\"]"]), [mrec, banner], "JSON text of a list")
        XCTAssertEqual(try sizes(["BANNER_SIZES": "320x50"]), [mrec, banner], "one size as text")
        capture.none()
    }

    func testPerZoneWinsOverGlobal() throws {
        let overrides: [String: Any] = [
            "BANNER_SIZES": ["728x90"],
            "BANNER_SIZES_BY_ZONE": ["43": ["320x50"]],
        ]
        XCTAssertEqual(try sizes(overrides, zone: "43"), [mrec, banner])
        XCTAssertEqual(try sizes(overrides, zone: "280"), [mrec, CGSize(width: 728, height: 90)])
        XCTAssertEqual(try sizes(overrides, zone: nil), [mrec, CGSize(width: 728, height: 90)])
    }

    func testDroppedEntriesAreReportedWithTheirZone() throws {
        let raw = try Factory.offSchema(because: "five entries that are not sizes: the drops being reported") {
            try AppConfigFactory.variant("minimal", ["BANNER_SIZES": ["big", "0x50", [300], ["a", "b"], 7, "320x50"]])
        }
        XCTAssertEqual(SellwildAdSizes.resolve(remoteValues: raw, zoneId: "43", primary: mrec), [mrec, banner])
        let event = capture.only(.configBannerSizesInvalid, label: .remoteConfig)
        XCTAssertEqual(event?.attributes["msg"], "5 banner size entries were dropped")
        XCTAssertEqual(event?.attributes["zoneId"], "43")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    /// A size read on every load (the ad view resolves its sizes several times
    /// per load) is reported once per launch, per zone (FAILURES.md 9.1).
    func testTheSameDropIsReportedOncePerLaunchPerZone() throws {
        let raw = try AppConfigFactory.remote(["BANNER_SIZES": ["0x50", "320x50"]])
        for _ in 0..<3 { XCTAssertEqual(SellwildAdSizes.resolve(remoteValues: raw, zoneId: "43", primary: mrec), [mrec, banner]) }
        XCTAssertEqual(capture.only(.configBannerSizesInvalid, label: .remoteConfig)?.attributes["zoneId"], "43")

        resetCapture()
        _ = SellwildAdSizes.resolve(remoteValues: raw, zoneId: "43", primary: mrec)
        capture.none()
        _ = SellwildAdSizes.resolve(remoteValues: raw, zoneId: "280", primary: mrec)
        _ = SellwildAdSizes.resolve(remoteValues: raw, zoneId: "280", primary: mrec)
        XCTAssertEqual(capture.events.map(\.attributes["zoneId"]), ["280"], "another zone is its own report")
        XCTAssertEqual(capture.calls, 1)
    }

    /// A dimension too large for an Int (the schema allows any run of digits)
    /// crashed resolve: `Int(_:)` traps in the dedupe key. Such an entry, and
    /// one whose part reads as infinity, is now dropped and reported like any
    /// entry that does not parse.
    func testSizeTooLargeForAnIntIsDroppedNotACrash() throws {
        XCTAssertEqual(try sizes(["BANNER_SIZES": ["99999999999999999999x50", [1e20, 50], ["inf", 50], "320x50"]]), [mrec, banner])
        XCTAssertEqual(capture.only(.configBannerSizesInvalid, label: .remoteConfig)?.attributes["msg"],
                       "3 banner size entries were dropped")
        XCTAssertEqual(SellwildAdSizes.parseSizes([[9_000_000_000_000_000_000.0, 50]]).dropped, 0, "just under 2^63 still fits")
    }

    /// 2^63 (9223372036854775808) is the first dimension `Int(_:)` traps on,
    /// and the schema allows it. It is dropped; the largest Double below it
    /// (9223372036854774784) still fits and is kept.
    func testTwoToThe63IsTheFirstDimensionDropped() throws {
        XCTAssertEqual(SellwildAdSizes.parseSizes(["9223372036854775808x50"]).dropped, 1)
        XCTAssertEqual(SellwildAdSizes.parseSizes(["50x9223372036854775808"]).dropped, 1)
        XCTAssertEqual(SellwildAdSizes.parseSizes(["9223372036854774784x50"]).sizes, [CGSize(width: 9_223_372_036_854_774_784.0, height: 50)])
        XCTAssertEqual(try sizes(["BANNER_SIZES": ["9223372036854775808x50", "320x50"]]), [mrec, banner])
        XCTAssertEqual(capture.only(.configBannerSizesInvalid, label: .remoteConfig)?.attributes["msg"],
                       "1 banner size entry was dropped")
    }

    /// A pair part that is text is read with `Double(_:)`, which does not
    /// trim, so [" 320 ", "50"] is dropped and reported. The schema allows
    /// any text there, and Android trims it and keeps the size (drift/ios.json
    /// `other`, bannerSizes.pairTextPadding).
    func testPairTextWithSpacesIsDroppedAsBefore() throws {
        XCTAssertEqual(try sizes(["BANNER_SIZES": [[" 320 ", "50"], ["320", "50"]]]), [mrec, banner])
        XCTAssertEqual(capture.only(.configBannerSizesInvalid, label: .remoteConfig)?.attributes["msg"],
                       "1 banner size entry was dropped")
    }

    /// JSON numbers reach the pair parser as NSNumber. Most read as a Double;
    /// an integer a Double cannot hold exactly reads as an Int, and one too
    /// large for an Int reads through NSNumber. All three give the same size.
    func testPairNumbersOfEveryWidth() throws {
        let raw = try AppConfigFactory.remote(["BANNER_SIZES": [[320, 50], [9_007_199_254_740_993, 50], [UInt64.max, 50]]])
        XCTAssertEqual(SellwildAdSizes.parseSizes(raw["BANNER_SIZES"]).sizes,
                       [banner, CGSize(width: 9_007_199_254_740_992, height: 50)])
        XCTAssertEqual(SellwildAdSizes.parseSizes(raw["BANNER_SIZES"]).dropped, 1, "UInt64.max does not fit an Int")
    }

    func testTheInvalidFixtureIsReported() throws {
        let raw = Factory.stripMarkers(try Fixtures.dict("fixtures/app-config/invalid/banner-sizes-bad-entry.json"))
        XCTAssertEqual(SellwildAdSizes.resolve(remoteValues: raw, zoneId: nil, primary: mrec), [mrec])
        XCTAssertEqual(capture.only(.configBannerSizesInvalid, label: .remoteConfig)?.attributes["msg"],
                       "1 banner size entry was dropped")
    }

    func testParseSizesCountsWhatItDrops() {
        XCTAssertEqual(SellwildAdSizes.parseSizes(nil).dropped, 0)
        XCTAssertEqual(SellwildAdSizes.parseSizes("  ").dropped, 0)
        XCTAssertEqual(SellwildAdSizes.parseSizes(42).dropped, 1, "a number is not a size list")
        XCTAssertEqual(SellwildAdSizes.parseSizes(["x": 1]).dropped, 1)
        XCTAssertEqual(SellwildAdSizes.parseSizes("[\"300x250\"").dropped, 1, "broken JSON text")
        XCTAssertEqual(SellwildAdSizes.parseSizes("{}").dropped, 1, "JSON that is not a list")
        XCTAssertEqual(SellwildAdSizes.parseSizes(["300x250x1", "-1x5"]).dropped, 2)
        XCTAssertEqual(SellwildAdSizes.parseSizes([[true, 5]]).sizes, [CGSize(width: 1, height: 5)], "a JSON number pair, as before")
    }

    /// One "WxH" text is parsed as sent, as before phase 3: each part is
    /// trimmed of spaces only, so a trailing line break drops the size, and
    /// the drop is reported. The schema allows it and Android keeps it
    /// (drift/ios.json `other`, BANNER_SIZES).
    func testSizeTextWithALineBreakIsDroppedAsBefore() throws {
        XCTAssertEqual(try sizes(["BANNER_SIZES": "320x50\n"]), [mrec])
        XCTAssertEqual(capture.only(.configBannerSizesInvalid, label: .remoteConfig)?.attributes["msg"],
                       "1 banner size entry was dropped")
        XCTAssertEqual(SellwildAdSizes.parseSizes(["320x50\n"]).dropped, 1, "the same for a list entry")

        resetCapture()
        XCTAssertEqual(try sizes(["BANNER_SIZES": " 320 x 50 "]), [mrec, banner], "spaces around each part are trimmed")
        XCTAssertEqual(try sizes(["BANNER_SIZES": "\n"]), [mrec], "blank text is unset, not a drop")
        capture.none()
    }

    func testPrimaryThatIsNotPositiveIsLeftOut() throws {
        XCTAssertEqual(SellwildAdSizes.resolve(remoteValues: try AppConfigFactory.remote(["BANNER_SIZES": ["320x50"]]),
                                               zoneId: nil, primary: .zero), [banner])
        XCTAssertEqual(SellwildAdSizes.parseSizes([[["300"], 250]]).dropped, 1, "a pair member that is not a number")
        capture.none()
    }

    func testBoundingSize() {
        XCTAssertEqual(SellwildAdSizes.boundingSize([mrec, banner]), CGSize(width: 320, height: 250))
        XCTAssertEqual(SellwildAdSizes.boundingSize([]), .zero)
    }

    // MARK: apply

    func testApplyGAMSetsPrimaryAndValidSizes() {
        let view = AdManagerBannerView(adSize: AdSizeBanner)
        SellwildAdSizes.applyGAM([], to: view)
        XCTAssertEqual(view.adSize.size, AdSizeBanner.size, "nothing to apply")

        SellwildAdSizes.applyGAM([mrec], to: view)
        XCTAssertEqual(view.adSize.size, mrec)
        XCTAssertNil(view.validAdSizes)

        SellwildAdSizes.applyGAM([mrec, banner], to: view)
        XCTAssertEqual(view.validAdSizes?.count, 2)
    }

    func testApplyRenderingAddsTheExtras() {
        let view = PrebidBannerView(frame: CGRect(origin: .zero, size: mrec), configID: "43", adSize: mrec)
        SellwildAdSizes.applyRendering([mrec], to: view)
        XCTAssertNil(view.additionalSizes)
        SellwildAdSizes.applyRendering([mrec, banner], to: view)
        XCTAssertEqual(view.additionalSizes, [banner])
    }

    func testApplyPrebidAcceptsOneOrMoreSizes() {
        // BannerAdUnit keeps its sizes internal; this pins that both paths run.
        let unit = BannerAdUnit(configId: "43", size: mrec)
        SellwildAdSizes.applyPrebid([mrec], to: unit)
        SellwildAdSizes.applyPrebid([mrec, banner], to: unit)
        XCTAssertNil(unit.getImpORTBConfig(), "only the sizes are touched")
    }
}
