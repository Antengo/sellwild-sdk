import XCTest
import UIKit
@testable import SellwildSDK

/// The feed's listing and ad rows carry the e2e ids of contracts/e2e/ids.json.
/// Every sample app's Maestro flows find the feed's rows by them. (Its own
/// file: SellwildFeedViewTests.swift may not grow.)
final class SellwildFeedE2EIDTests: ViewTestCase {

    override func setUp() {
        super.setUp()
        SellwildFeedView.environment = SellwildFeedView.Environment(
            makeAPIClient: { SellwildAPIClient(session: StubURLProtocol.makeSession()) },
            makeAdView: SellwildAdView.init(config:adSize:zoneId:),
            present: { _, _ in },
            imageSession: StubURLProtocol.makeSession()
        )
    }

    override func tearDown() {
        SellwildFeedView.environment = .live
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testListingAndAdRowsCarryTheE2EIdentifiers() throws {
        let listings = try ListingsResponseFactory.data(listings: [
            try ListingFactory.make(["id": "1"]),
            try ListingFactory.make(["id": "2"])
        ])
        StubURLProtocol.handler = { request in
            if ["png", "jpg", "jpeg", "webp"].contains(request.url?.pathExtension ?? "") {
                return .init(status: 200, body: testPNG())
            }
            return .init(status: 200, headers: ["Content-Type": "application/json"], body: listings)
        }
        var config = try AppConfigFactory.config([:], partnerCode: "minimal")
        config.col1 = "LGLB"
        config.mobileZids = ["43"]
        config.mobileBannerZid = "b1"
        config.gamTag = "/1/app/feed"
        let feed = SellwildFeedView(config: config)
        feed.frame = CGRect(x: 0, y: 0, width: 400, height: 3000)
        feed.load()
        spin { feed.tableView(feed.tableView, numberOfRowsInSection: 0) == 5 }

        let ids = (0..<5).map { row in
            feed.tableView(feed.tableView, cellForRowAt: IndexPath(row: row, section: 0)).accessibilityIdentifier
        }
        XCTAssertEqual(ids, [nil, "sw.listing.card", "sw.feed.ad", "sw.listing.card", "sw.feed.ad"],
                       "header, L, G, L, B")
        let listed = try XCTUnwrap(Fixtures.dict("e2e/ids.json")["ids"] as? [String: Any])
        XCTAssertNotNil(listed[SellwildFeedView.listingCardAccessibilityID])
        XCTAssertNotNil(listed[SellwildFeedView.adRowAccessibilityID])
        capture.none()
    }
}
