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

    // MARK: URL pairing

    func testImageAndURLArraysPairByIndex() {
        let images = ["https://x/a.png", "https://x/b.png", "https://x/c.png"]
        let urls = ["https://x/ua", "https://x/ub", "https://x/uc"]
        let paired = ["https://x/a.png": "https://x/ua",
                      "https://x/b.png": "https://x/ub",
                      "https://x/c.png": "https://x/uc"]
        for _ in 0..<80 {
            let c = SellwildHouseAd.resolve(
                remoteValues: ["MOBILE_HOUSE_AD_IMAGE": images, "MOBILE_HOUSE_AD_URL": urls],
                zoneId: nil, size: mrec)
            XCTAssertNotNil(c)
            XCTAssertEqual(c?.clickURL, paired[c!.imageURL], "click URL must pair with its image")
        }
    }

    func testImageArrayWithSingleSharedURL() {
        for _ in 0..<20 {
            let c = SellwildHouseAd.resolve(
                remoteValues: ["MOBILE_HOUSE_AD_IMAGE": ["https://x/a.png", "https://x/b.png"],
                               "MOBILE_HOUSE_AD_URL": "https://x/shared"],
                zoneId: nil, size: mrec)
            XCTAssertEqual(c?.clickURL, "https://x/shared")
        }
    }

    func testShorterURLArrayLeavesUnpairedClickNil() {
        // 3 images, 1 URL → only index 0 gets a click; the rest resolve nil.
        let images = ["https://x/a.png", "https://x/b.png", "https://x/c.png"]
        for _ in 0..<80 {
            let c = SellwildHouseAd.resolve(
                remoteValues: ["MOBILE_HOUSE_AD_IMAGE": images, "MOBILE_HOUSE_AD_URL": ["https://x/only0"]],
                zoneId: nil, size: mrec)
            if c?.imageURL == "https://x/a.png" {
                XCTAssertEqual(c?.clickURL, "https://x/only0")
            } else {
                XCTAssertNil(c?.clickURL)
            }
        }
    }

    func testBlankImagesKeepURLPairingByOriginalIndex() {
        // image[0] blank → never picked; b/c pair with their ORIGINAL-index URLs.
        for _ in 0..<80 {
            let c = SellwildHouseAd.resolve(
                remoteValues: ["MOBILE_HOUSE_AD_IMAGE": ["", "https://x/b.png", "https://x/c.png"],
                               "MOBILE_HOUSE_AD_URL": ["https://x/u0", "https://x/u1", "https://x/u2"]],
                zoneId: nil, size: mrec)
            XCTAssertNotNil(c)
            if c?.imageURL == "https://x/b.png" {
                XCTAssertEqual(c?.clickURL, "https://x/u1")
            } else {
                XCTAssertEqual(c?.imageURL, "https://x/c.png")
                XCTAssertEqual(c?.clickURL, "https://x/u2")
            }
        }
    }
}
