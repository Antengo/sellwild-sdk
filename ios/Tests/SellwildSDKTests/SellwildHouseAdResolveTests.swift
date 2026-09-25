import XCTest
@testable import SellwildSDK

/// `SellwildHouseAd.resolve` image resolution: `MOBILE_HOUSE_AD_IMAGE` (and the
/// `image` field of a by-zone / by-size object) is either a single URL string
/// or an array of URL strings, with a random non-empty pick per call (per
/// no-fill). The pick's random source is injected, so every draw is exact.
/// Remote values come from the app-config factory.
final class SellwildHouseAdResolveTests: XCTestCase {

    private let mrec = CGSize(width: 300, height: 250)

    private func remote(_ overrides: [String: Any]) throws -> [String: Any] {
        try AppConfigFactory.remote(overrides)
    }

    private func resolve(_ overrides: [String: Any], zone: String? = nil, seed: UInt64 = 1) throws -> SellwildHouseAdCreative? {
        var rng = SeededGenerator(seed: seed)
        return SellwildHouseAd.resolve(remoteValues: try remote(overrides), zoneId: zone, size: mrec, using: &rng)
    }

    func testSingleImageStringUnchanged() throws {
        let c = try resolve(["MOBILE_HOUSE_AD_IMAGE": "https://x/a.png", "MOBILE_HOUSE_AD_URL": "https://x/click"])
        XCTAssertEqual(c, SellwildHouseAdCreative(imageURL: "https://x/a.png", clickURL: "https://x/click"))
    }

    func testImageArrayPickIsTheSeededDrawFromTheCandidates() throws {
        let urls = ["https://x/a.png", "https://x/b.png", "https://x/c.png"]
        let candidates = SellwildHouseAd.candidates(remoteValues: try remote(["MOBILE_HOUSE_AD_IMAGE": urls]), zoneId: nil, size: mrec)
        XCTAssertEqual(candidates.map(\.imageURL), urls)

        var picks = Set<String>()
        for seed in UInt64(0)..<32 {
            var expectedRNG = SeededGenerator(seed: seed)
            let expected = candidates.randomElement(using: &expectedRNG)
            let picked = try resolve(["MOBILE_HOUSE_AD_IMAGE": urls], seed: seed)
            XCTAssertEqual(picked, expected, "seed \(seed)")
            picks.insert(picked?.imageURL ?? "")
        }
        XCTAssertEqual(picks, Set(urls), "every image is reachable, so backfill rotates")

        // The public entry point draws from the same candidates.
        XCTAssertTrue(urls.contains(SellwildHouseAd.resolve(remoteValues: try remote(["MOBILE_HOUSE_AD_IMAGE": urls]),
                                                            zoneId: nil, size: mrec)?.imageURL ?? ""))
    }

    func testImageArraySkipsBlankEntries() throws {
        XCTAssertEqual(try resolve(["MOBILE_HOUSE_AD_IMAGE": ["", "   ", "https://x/only.png"]])?.imageURL, "https://x/only.png")
    }

    func testEmptyOrMissingImageResolvesNil() throws {
        XCTAssertNil(try resolve(["MOBILE_HOUSE_AD_IMAGE": [String]()]))
        XCTAssertNil(try resolve([:]))
        XCTAssertNil(SellwildHouseAd.resolve(remoteValues: nil, zoneId: "43", size: mrec))
    }

    func testByZoneThenBySizeThenDefault() throws {
        let overrides: [String: Any] = [
            "MOBILE_HOUSE_AD_BY_ZONE": ["43": ["image": "https://x/zone.png", "url": "https://x/z"], "44": ["image": ""]],
            "MOBILE_HOUSE_AD_BY_SIZE": ["300x250": ["image": ["https://x/m1.png", "https://x/m2.png"], "url": "https://x/c"]],
            "MOBILE_HOUSE_AD_IMAGE": "https://x/default.png",
        ]
        XCTAssertEqual(try resolve(overrides, zone: "43"), SellwildHouseAdCreative(imageURL: "https://x/zone.png", clickURL: "https://x/z"))
        let bySize = try XCTUnwrap(try resolve(overrides, zone: "44"), "a blank zone image falls through to the size")
        XCTAssertTrue(["https://x/m1.png", "https://x/m2.png"].contains(bySize.imageURL))
        XCTAssertEqual(bySize.clickURL, "https://x/c")
        let other = SellwildHouseAd.candidates(remoteValues: try remote(overrides), zoneId: "43", size: CGSize(width: 320, height: 50))
        XCTAssertEqual(other.map(\.imageURL), ["https://x/zone.png"])
        let noZone = SellwildHouseAd.candidates(remoteValues: try remote(overrides), zoneId: nil, size: CGSize(width: 320, height: 50))
        XCTAssertEqual(noZone.map(\.imageURL), ["https://x/default.png"])
        // The contract's invalid fixture: a by-zone creative that is a URL, not an object.
        let stringCreative = Factory.stripMarkers(try Fixtures.dict("fixtures/app-config/invalid/house-map-string-creative.json"))
        XCTAssertEqual(SellwildHouseAd.candidates(remoteValues: stringCreative, zoneId: "43", size: mrec), [],
                       "an override that is not an object is ignored")
        let stringBySize = try Factory.offSchema(because: "a MOBILE_HOUSE_AD_BY_SIZE creative must be an object, not a URL") {
            try remote(["MOBILE_HOUSE_AD_BY_SIZE": ["300x250": "https://x/a.png"]])
        }
        XCTAssertEqual(SellwildHouseAd.candidates(remoteValues: stringBySize, zoneId: nil, size: mrec), [], "the same by size")
    }

    func testDisabledStillWins() throws {
        XCTAssertNil(try resolve(["MOBILE_HOUSE_AD_ENABLED": false, "MOBILE_HOUSE_AD_IMAGE": ["https://x/a.png"]]))
        XCTAssertEqual(SellwildHouseAd.candidates(remoteValues: try remote(["MOBILE_HOUSE_AD_ENABLED": "off", "MOBILE_HOUSE_AD_IMAGE": "https://x/a.png"]),
                                                  zoneId: nil, size: mrec), [])
        XCTAssertTrue(SellwildHouseAd.isEnabled(remoteValues: nil))
        XCTAssertTrue(SellwildHouseAd.isEnabled(remoteValues: try remote(["MOBILE_HOUSE_AD_ENABLED": "yes"])))
        XCTAssertFalse(SellwildHouseAd.isEnabled(remoteValues: try remote(["MOBILE_HOUSE_AD_ENABLED": 0])))
    }

    // MARK: URL pairing

    func testImageAndURLArraysPairByIndex() throws {
        let candidates = SellwildHouseAd.candidates(remoteValues: try remote([
            "MOBILE_HOUSE_AD_IMAGE": ["https://x/a.png", "https://x/b.png", "https://x/c.png"],
            "MOBILE_HOUSE_AD_URL": ["https://x/ua", "https://x/ub", "https://x/uc"],
        ]), zoneId: nil, size: mrec)
        XCTAssertEqual(candidates.map(\.clickURL), ["https://x/ua", "https://x/ub", "https://x/uc"])
    }

    func testImageArrayWithSingleSharedURL() throws {
        let candidates = SellwildHouseAd.candidates(remoteValues: try remote([
            "MOBILE_HOUSE_AD_IMAGE": ["https://x/a.png", "https://x/b.png"], "MOBILE_HOUSE_AD_URL": "https://x/shared",
        ]), zoneId: nil, size: mrec)
        XCTAssertEqual(candidates.map(\.clickURL), ["https://x/shared", "https://x/shared"])
    }

    func testShorterURLArrayLeavesUnpairedClickNil() throws {
        let candidates = SellwildHouseAd.candidates(remoteValues: try remote([
            "MOBILE_HOUSE_AD_IMAGE": ["https://x/a.png", "https://x/b.png", "https://x/c.png"],
            "MOBILE_HOUSE_AD_URL": ["https://x/only0"],
        ]), zoneId: nil, size: mrec)
        XCTAssertEqual(candidates.map(\.clickURL), ["https://x/only0", nil, nil])
    }

    func testBlankImagesKeepURLPairingByOriginalIndex() throws {
        let candidates = SellwildHouseAd.candidates(remoteValues: try remote([
            "MOBILE_HOUSE_AD_IMAGE": ["", "https://x/b.png", "https://x/c.png"],
            "MOBILE_HOUSE_AD_URL": ["https://x/u0", "https://x/u1", "  "],
        ]), zoneId: nil, size: mrec)
        XCTAssertEqual(candidates, [
            SellwildHouseAdCreative(imageURL: "https://x/b.png", clickURL: "https://x/u1"),
            SellwildHouseAdCreative(imageURL: "https://x/c.png", clickURL: nil),
        ])
    }
}
