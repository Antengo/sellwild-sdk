import XCTest
@testable import SellwildSDK

/// The feed's pure row builder. A listings failure renders the feed from the
/// schedule with zero listings — the ad rows must still be there.
final class SellwildFeedRowsTests: XCTestCase {

    private func describe(_ rows: [SellwildFeedView.Row]) -> [String] {
        rows.map { row in
            switch row {
            case .header: return "header"
            case .listing: return "listing"
            case .gamAd(let z): return "G:\(z)"
            case .directAd(let z): return "D:\(z)"
            case .banner(let z): return "B:\(z)"
            }
        }
    }

    func testZeroListingsStillYieldsAdRows() {
        var config = SellwildConfig(partnerCode: "acme")
        config.mobileZids = ["101", "102"]
        config.mobileBannerZid = "201"

        let rows = SellwildFeedView.buildRows(schedule: "LLGLLDLLGB", listings: [], config: config)

        // L tokens are skipped; G/D rotate through the zones; B uses the banner zone.
        XCTAssertEqual(describe(rows), ["header", "G:101", "D:102", "G:101", "B:201"])
    }

    func testZeroListingsAndNoZonesIsHeaderOnly() {
        // No cached/fetched config ⇒ no zones ⇒ nothing to show, and no crash.
        let config = SellwildConfig(partnerCode: "acme")
        let rows = SellwildFeedView.buildRows(schedule: "LLGLLGB", listings: [], config: config)
        XCTAssertEqual(describe(rows), ["header"])
    }

    func testBlankBannerZoneFallsThroughToNextConfiguredZone() {
        var config = SellwildConfig(partnerCode: "acme")
        config.mobileBannerZid = ""
        config.bannerZid = "301"
        let rows = SellwildFeedView.buildRows(schedule: "B", listings: [], config: config)
        XCTAssertEqual(describe(rows), ["header", "B:301"])
    }
}
