import XCTest
@testable import SellwildSDK

/// Unit tests for the house-ad listing-fallback SELECTION logic. The fallback
/// renders a grey placeholder when handed a photoless listing, so the picker
/// must prefer listings that actually have a photo. Rendering / hide-on-fill
/// behavior is exercised by the build/sim gate; this pins the pure selection.
final class SellwildHouseAdTests: XCTestCase {

    /// Decode `SellwildListing` values from JSON (the model has a custom decoder,
    /// no memberwise init) — mirrors the shape the listings cache serves.
    private func listings(_ json: String) -> [SellwildListing] {
        let data = Data(json.utf8)
        return (try? JSONDecoder().decode([SellwildListing].self, from: data)) ?? []
    }

    // MARK: hasUsablePhoto

    func testHasUsablePhoto() {
        let ls = listings("""
        [
          {"id":"1","status":"active","title":"with","photos":[{"url":"https://x/a.jpg"}]},
          {"id":"2","status":"active","title":"none"},
          {"id":"3","status":"active","title":"empty","photos":[{"url":"  "}]}
        ]
        """)
        XCTAssertEqual(ls.count, 3)
        XCTAssertTrue(SellwildHouseAd.hasUsablePhoto(ls[0]))
        XCTAssertFalse(SellwildHouseAd.hasUsablePhoto(ls[1]))  // no photos
        XCTAssertFalse(SellwildHouseAd.hasUsablePhoto(ls[2]))  // blank url
    }

    // MARK: pickListing

    func testPickListingPrefersListingsWithPhotos() {
        // Only id "2" has a photo — every row must resolve to it, never the
        // photoless neighbors.
        let ls = listings("""
        [
          {"id":"1","status":"active","title":"no"},
          {"id":"2","status":"active","title":"yes","photos":[{"url":"https://x/b.jpg"}]},
          {"id":"3","status":"active","title":"no2"}
        ]
        """)
        for row in 0..<6 {
            XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: row)?.id, "2")
        }
    }

    func testPickListingRotatesWithinPhotoSubset() {
        let ls = listings("""
        [
          {"id":"a","status":"active","title":"a","photos":[{"url":"https://x/a.jpg"}]},
          {"id":"b","status":"active","title":"b","photos":[{"url":"https://x/b.jpg"}]},
          {"id":"c","status":"active","title":"c"}
        ]
        """)
        // Rotates over the two photo-bearing listings (a, b), skipping c.
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 0)?.id, "a")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 1)?.id, "b")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 2)?.id, "a")
    }

    func testPickListingFallsBackToAllWhenNoneHavePhotos() {
        let ls = listings("""
        [
          {"id":"x","status":"active","title":"x"},
          {"id":"y","status":"active","title":"y"}
        ]
        """)
        // No photos anywhere → plain rotation over all rather than returning nil.
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 0)?.id, "x")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 1)?.id, "y")
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 2)?.id, "x")
    }

    func testPickListingEmptyIsNil() {
        XCTAssertNil(SellwildHouseAd.pickListing(from: [], row: 0))
    }
}
