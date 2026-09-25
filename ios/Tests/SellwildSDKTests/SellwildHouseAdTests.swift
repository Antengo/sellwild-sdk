import XCTest
@testable import SellwildSDK

/// Unit tests for the house-ad listing-fallback SELECTION logic. The fallback
/// renders a grey placeholder when handed a photoless listing, so the picker
/// must prefer listings that actually have a photo. Listings come from the
/// listing factory through the SDK's decoder.
final class SellwildHouseAdTests: XCTestCase {

    private func listing(_ id: String, photo: String?) throws -> SellwildListing {
        guard let photo else {
            return try ListingFactory.decoded(Factory.offSchema(because: "photos is required; the picker must still skip a listing without one") {
                try ListingFactory.make(["id": id, "photos": Factory.remove])
            })
        }
        return try ListingFactory.decoded(ListingFactory.make(["id": id, "photos": [["url": photo]]]))
    }

    // MARK: hasUsablePhoto

    func testHasUsablePhoto() throws {
        XCTAssertTrue(SellwildHouseAd.hasUsablePhoto(try listing("1", photo: "https://x/a.jpg")))
        XCTAssertFalse(SellwildHouseAd.hasUsablePhoto(try listing("2", photo: nil)))  // no photos
        XCTAssertFalse(SellwildHouseAd.hasUsablePhoto(try listing("3", photo: "  ")))  // blank url
    }

    // MARK: pickListing

    func testPickListingPrefersListingsWithPhotos() throws {
        // Only id "2" has a photo — every row must resolve to it.
        let ls = [try listing("1", photo: nil), try listing("2", photo: "https://x/b.jpg"), try listing("3", photo: nil)]
        for row in 0..<6 {
            XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: row)?.id, "2")
        }
    }

    func testPickListingRotatesWithinPhotoSubset() throws {
        let ls = [try listing("a", photo: "https://x/a.jpg"), try listing("b", photo: "https://x/b.jpg"), try listing("c", photo: nil)]
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 0)?.id, "a")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 1)?.id, "b")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 2)?.id, "a")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: -1)?.id, "b", "a negative row still rotates")
    }

    func testPickListingFallsBackToAllWhenNoneHavePhotos() throws {
        let ls = [try listing("x", photo: nil), try listing("y", photo: nil)]
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 0)?.id, "x")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 1)?.id, "y")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 2)?.id, "x")
    }

    func testPickListingEmptyIsNil() {
        XCTAssertNil(SellwildHouseAd.pickListing(from: [], row: 0))
    }

    // MARK: pickListing excludeIds (dedup vs. already-shown feed rows)

    func testPickListingExcludesAlreadyShownIds() throws {
        let ls = [try listing("1", photo: "https://x/a.jpg"), try listing("2", photo: "https://x/b.jpg"), try listing("3", photo: "https://x/c.jpg")]
        for row in 0..<6 {
            XCTAssertNotEqual(SellwildHouseAd.pickListing(from: ls, row: row, excludeIds: ["1"])?.id, "1")
        }
    }

    func testPickListingFallsBackToDuplicateWhenAllExcluded() throws {
        // Every candidate is already shown elsewhere: degrade to a duplicate
        // (the web widget's documented last resort) rather than nil.
        let ls = [try listing("1", photo: "https://x/a.jpg"), try listing("2", photo: "https://x/b.jpg")]
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 0, excludeIds: ["1", "2"])?.id, "1")
    }

    func testPickListingDefaultExcludeIdsIsUnchanged() throws {
        let ls = [try listing("a", photo: "https://x/a.jpg"), try listing("b", photo: "https://x/b.jpg")]
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 0)?.id, "a")
    }
}
