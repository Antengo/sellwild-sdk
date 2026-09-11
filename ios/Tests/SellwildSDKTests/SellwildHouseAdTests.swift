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

    // MARK: pickListing excludeIds (dedup vs. already-shown feed rows)

    func testPickListingExcludesAlreadyShownIds() {
        let ls = listings("""
        [
          {"id":"1","status":"active","title":"a","photos":[{"url":"https://x/a.jpg"}]},
          {"id":"2","status":"active","title":"b","photos":[{"url":"https://x/b.jpg"}]},
          {"id":"3","status":"active","title":"c","photos":[{"url":"https://x/c.jpg"}]}
        ]
        """)
        // Without exclusion, row 0 resolves to "1" (see rotation tests above).
        // With "1" already shown as a normal feed row, it must never be picked.
        for row in 0..<6 {
            XCTAssertNotEqual(SellwildHouseAd.pickListing(from: ls, row: row, excludeIds: ["1"])?.id, "1")
        }
    }

    func testPickListingFallsBackToDuplicateWhenAllExcluded() {
        let ls = listings("""
        [
          {"id":"1","status":"active","title":"a","photos":[{"url":"https://x/a.jpg"}]},
          {"id":"2","status":"active","title":"b","photos":[{"url":"https://x/b.jpg"}]}
        ]
        """)
        // Every candidate is already shown elsewhere — degrade to a duplicate
        // (matches the web widget's documented last-resort behavior) rather
        // than returning nil and leaving the ad slot with no house content.
        let picked = SellwildHouseAd.pickListing(from: ls, row: 0, excludeIds: ["1", "2"])
        XCTAssertNotNil(picked)
    }

    func testPickListingDefaultExcludeIdsIsUnchanged() {
        // No excludeIds argument at all — existing call sites/behavior untouched.
        let ls = listings("""
        [
          {"id":"a","status":"active","title":"a","photos":[{"url":"https://x/a.jpg"}]},
          {"id":"b","status":"active","title":"b","photos":[{"url":"https://x/b.jpg"}]}
        ]
        """)
        XCTAssertEqual(SellwildHouseAd.pickListing(from: ls, row: 0)?.id, "a")
    }
}
