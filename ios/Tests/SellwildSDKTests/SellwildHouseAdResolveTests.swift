import XCTest
@testable import SellwildSDK

/// Unit tests for `SellwildHouseAd.resolve` image resolution — specifically the
/// new support for `MOBILE_HOUSE_AD_IMAGE` (and the `image` field of a
/// by-zone / by-size object) being either a single URL string OR an array of
/// URL strings, with a random non-empty pick per call (per no-fill).
final class SellwildHouseAdResolveTests: XCTestCase {

    private let mrec = CGSize(width: 300, height: 250)

    func testSingleImageStringUnchanged() {
        let c = SellwildHouseAd.resolve(
            remoteValues: ["MOBILE_HOUSE_AD_IMAGE": "https://x/a.png",
                           "MOBILE_HOUSE_AD_URL": "https://x/click"],
            zoneId: nil, size: mrec)
        XCTAssertEqual(c?.imageURL, "https://x/a.png")
        XCTAssertEqual(c?.clickURL, "https://x/click")
    }

    func testImageArrayAlwaysPicksFromTheSet() {
        let urls = ["https://x/a.png", "https://x/b.png", "https://x/c.png"]
        let set = Set(urls)
        // Random pick — assert membership across many draws (and that it's not
        // always the same index, i.e. rotation actually happens).
        var seen = Set<String>()
        for _ in 0..<80 {
            let c = SellwildHouseAd.resolve(
                remoteValues: ["MOBILE_HOUSE_AD_IMAGE": urls], zoneId: nil, size: mrec)
            XCTAssertNotNil(c)
            XCTAssertTrue(set.contains(c!.imageURL))
            seen.insert(c!.imageURL)
        }
        XCTAssertGreaterThan(seen.count, 1, "expected rotation across draws")
    }

    func testImageArraySkipsBlankEntries() {
        let c = SellwildHouseAd.resolve(
            remoteValues: ["MOBILE_HOUSE_AD_IMAGE": ["", "   ", "https://x/only.png"]],
            zoneId: nil, size: mrec)
        XCTAssertEqual(c?.imageURL, "https://x/only.png")
    }

    func testEmptyImageArrayResolvesNil() {
        let c = SellwildHouseAd.resolve(
            remoteValues: ["MOBILE_HOUSE_AD_IMAGE": [String]()], zoneId: nil, size: mrec)
        XCTAssertNil(c)
    }

    func testBySizeObjectImageArray() {
        let c = SellwildHouseAd.resolve(
            remoteValues: ["MOBILE_HOUSE_AD_BY_SIZE": [
                "300x250": ["image": ["https://x/m1.png", "https://x/m2.png"], "url": "https://x/c"]
            ]],
            zoneId: nil, size: mrec)
        XCTAssertNotNil(c)
        XCTAssertTrue(["https://x/m1.png", "https://x/m2.png"].contains(c!.imageURL))
        XCTAssertEqual(c?.clickURL, "https://x/c")
    }

    func testDisabledStillWins() {
        let c = SellwildHouseAd.resolve(
            remoteValues: ["MOBILE_HOUSE_AD_ENABLED": false,
                           "MOBILE_HOUSE_AD_IMAGE": ["https://x/a.png"]],
            zoneId: nil, size: mrec)
        XCTAssertNil(c)
    }
}
