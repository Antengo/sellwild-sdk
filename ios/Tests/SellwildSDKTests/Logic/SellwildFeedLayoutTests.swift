import XCTest
import UIKit
@testable import SellwildSDK

/// The feed's pure half (`SellwildFeedLayout`) and the shared formatting
/// (`SellwildFormat`). Listings come from the listing factory.
final class SellwildFeedLayoutTests: XCTestCase {

    private func listing(_ id: String, _ overrides: [String: Any] = [:]) throws -> SellwildListing {
        var fields = overrides
        fields["id"] = id
        return try ListingFactory.decoded(ListingFactory.make(fields))
    }

    /// A row as text, so a whole layout reads in one assertion.
    private func text(_ row: SellwildFeedLayout.Row) -> String {
        switch row {
        case .header: return "H"
        case .listing(let listing): return "L:\(listing.id)"
        case .gamAd(let zone): return "G:\(zone)"
        case .directAd(let zone): return "D:\(zone)"
        case .banner(let zone): return "B:\(zone)"
        }
    }

    // MARK: Schedule

    func testScheduleIsTrimmedUpperCasedOrTheDefault() {
        XCTAssertEqual(SellwildFeedLayout.normalizeSchedule(nil), "LLGLLGLLG")
        XCTAssertEqual(SellwildFeedLayout.normalizeSchedule(" \n "), SellwildFeedLayout.defaultSchedule)
        XCTAssertEqual(SellwildFeedLayout.normalizeSchedule(" lgb\n"), "LGB")
    }

    func testZonesCycleAndEmptyZonesAreDropped() {
        XCTAssertNil(SellwildFeedLayout.pickZone([], index: 0))
        XCTAssertEqual(SellwildFeedLayout.pickZone(["a", "b"], index: 3), "b")
        XCTAssertEqual(SellwildFeedLayout.adZones(["a", "", "b"]), ["a", "b"])
    }

    func testBannerZoneIsTheFirstSetOneEvenWhenEmpty() {
        XCTAssertEqual(SellwildFeedLayout.bannerZone(mobile: "m", banner: "b", bottom: "t"), "m")
        XCTAssertEqual(SellwildFeedLayout.bannerZone(mobile: "", banner: "b", bottom: "t"), "b",
                       "a blank mobile zone does not shadow BANNER_ZID (origin b194344)")
        XCTAssertEqual(SellwildFeedLayout.bannerZone(mobile: nil, banner: "b", bottom: "t"), "b")
        XCTAssertEqual(SellwildFeedLayout.bannerZone(mobile: nil, banner: nil, bottom: "t"), "t")
        XCTAssertEqual(SellwildFeedLayout.bannerZone(mobile: nil, banner: nil, bottom: nil), "")
    }

    // MARK: Rows

    func testEveryTokenBecomesARowWhileListingsAndZonesLast() throws {
        let layout = SellwildFeedLayout.build(schedule: "LLgDBL", listings: [try listing("1"), try listing("2")],
                                              adZones: ["a", "b"], bannerZone: "z")
        XCTAssertEqual(layout.rows.map(text), ["H", "L:1", "L:2", "G:a", "D:b", "B:z"],
                       "a third L has no listing left and is simply not a row")
        XCTAssertEqual(layout.skipped, [])
        XCTAssertEqual(layout.rows.map(\.adZoneId), [nil, nil, nil, "a", "b", "z"])
    }

    func testTokensThatCannotBecomeRowsAreSkipped() throws {
        let layout = SellwildFeedLayout.build(schedule: "GDBX", listings: [], adZones: [], bannerZone: "")
        XCTAssertEqual(layout.rows.map(text), ["H"])
        XCTAssertEqual(layout.skipped, [.noAdZone, .noAdZone, .noBannerZone, .unknownToken("X")])
    }

    func testGpidsAreUniquePerSlotAndMissingBasesAreLeftOut() {
        let rows: [SellwildFeedLayout.Row] = [.header, .gamAd(zoneId: "a"), .directAd(zoneId: "b"),
                                              .banner(zoneId: "none"), .gamAd(zoneId: "c")]
        var asked: [String] = []
        let gpids = SellwildFeedLayout.gpids(rows: rows) { zone in
            asked.append(zone)
            return zone == "none" ? nil : "/1/app"
        }
        XCTAssertEqual(asked, ["a", "b", "none", "c"], "only ad rows, in row order")
        XCTAssertEqual(gpids, [1: "/1/app#1", 2: "/1/app#2", 4: "/1/app#3"])
    }

    func testShownListingIds() throws {
        let rows: [SellwildFeedLayout.Row] = [.header, .listing(try listing("7")), .gamAd(zoneId: "a"), .listing(try listing("9"))]
        XCTAssertEqual(SellwildFeedLayout.shownListingIds(rows), ["7", "9"])
    }

    func testNoFillKeepsTheSlotUnlessAListingCanReplaceIt() {
        XCTAssertEqual(SellwildFeedLayout.noFillView(hasHouseImage: true, hasListing: true), .adSlot)
        XCTAssertEqual(SellwildFeedLayout.noFillView(hasHouseImage: false, hasListing: false), .adSlot)
        XCTAssertEqual(SellwildFeedLayout.noFillView(hasHouseImage: false, hasListing: true), .fallbackCard)
    }

    func testOnlyHTTPTargetsOpen() {
        XCTAssertEqual(try? SellwildFeedLayout.openTarget("https://sellwild.com/p/1").get().host, "sellwild.com")
        XCTAssertEqual(SellwildFeedLayout.openTarget(nil).failure, .missing)
        XCTAssertEqual(SellwildFeedLayout.openTarget("").failure, .missing)
        XCTAssertEqual(SellwildFeedLayout.openTarget("tel:5551234").failure, .notHTTP)
    }

    // MARK: Format

    func testPriceGetsTheCurrencySymbol() {
        XCTAssertEqual(SellwildFormat.price(currency: nil, price: "19315"), "$19315")
        XCTAssertEqual(SellwildFormat.price(currency: "eur", price: "12.5"), "€12.50")
        XCTAssertEqual(SellwildFormat.price(currency: "GBP", price: "3"), "£3")
        XCTAssertEqual(SellwildFormat.price(currency: "USD", price: "abc"), "")
        XCTAssertEqual(SellwildFormat.price(currency: "USD", price: nil), "")
    }

    /// Reproduced first: `Int(_:)` trapped on a whole price above Int.max
    /// ("Fatal error: Double value cannot be converted to Int because the
    /// result would be greater than Int.max"), and the listing schema allows
    /// any numeric text.
    func testAWholePriceTooLargeForAnIntIsNotACrash() throws {
        let huge = try listing("1", ["price": "99999999999999999999"])
        XCTAssertEqual(SellwildFormat.price(currency: huge.currency, price: huge.price), "$100000000000000000000.00")
    }

    func testSellerLine() throws {
        let named = try listing("1", ["user": ["id": "9", "firstName": " ann ", "lastName": "b"]])
        XCTAssertEqual(SellwildFormat.seller(named.user), "ANN B.  |  sellwild.com")
        let noLast = try listing("2", ["user": ["id": "9", "firstName": "Ann"]])
        XCTAssertEqual(SellwildFormat.seller(noLast.user), "ANN  |  sellwild.com")
        let noFirst = try listing("3", ["user": ["id": "9", "lastName": ""]])
        XCTAssertEqual(SellwildFormat.seller(noFirst.user), "SELLER  |  sellwild.com")
        XCTAssertEqual(SellwildFormat.seller(nil), "sellwild.com")
    }

    func testHexColors() {
        XCTAssertEqual(SellwildFormat.hexColor("#FF0000"), .init(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(SellwildFormat.hexColor(" 0000ff80 "), .init(red: 0, green: 0, blue: 1, alpha: CGFloat(0x80) / 255))
        XCTAssertNil(SellwildFormat.hexColor("#12345"))
        XCTAssertNil(SellwildFormat.hexColor("zzzzzz"))
        XCTAssertNil(SellwildFormat.hexColor(""))
        XCTAssertNil(SellwildFormat.hexColor(nil))
        XCTAssertNotNil(SellwildFormat.color("#101010"))
        XCTAssertNil(SellwildFormat.color("nope"))
        XCTAssertTrue(SellwildFormat.isDark(.black))
        XCTAssertFalse(SellwildFormat.isDark(.white))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
