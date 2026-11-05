import XCTest
import UIKit
@testable import SellwildSDK

/// The feed's timings (FAILURES.md 18.1): the listings fetch and decode, and
/// the first listing on screen once per process; and its window count.
final class SellwildFeedTimingTests: ViewTestCase {

    private var pushed: [SellwildTimingCore.Event] = []

    override func setUp() {
        super.setUp()
        pushed = []
        SellwildTiming.setDependencies(SellwildTiming.Dependencies(
            push: { [unowned self] in self.pushed.append($0) }, now: { 1 }, uid: { "u" },
            // Frozen: a slow runner must not turn these fetches into listings.fetch.slow.
            monotonic: { 0 }
        ))
        SellwildTiming.remote = ["TIMING_SAMPLE_RATE": 1]
        SellwildListingCardView.cache.removeAllObjects()
        SellwildFeedView.environment = SellwildFeedView.Environment(
            makeAPIClient: { SellwildAPIClient(session: StubURLProtocol.makeSession()) },
            makeAdView: { config, size, zone in SellwildAdView(config: config, adSize: size, zoneId: zone) },
            present: { _, _ in },
            imageSession: StubURLProtocol.makeSession()
        )
    }

    override func tearDown() {
        SellwildFeedView.environment = .live
        SellwildListingCardView.cache.removeAllObjects()
        super.tearDown()
    }

    func testTheFirstListingAndTheListingsFetchAreTimedOncePerProcess() throws {
        let items = try (1...2).map { try ListingFactory.make(["id": "\($0)"]) }
        let body = try ListingsResponseFactory.data(listings: items)
        StubURLProtocol.handler = { request in
            if ["png", "jpg", "jpeg", "webp"].contains(request.url?.pathExtension ?? "") {
                return .init(status: 200, body: testPNG())
            }
            return .init(status: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        var config = try AppConfigFactory.config([:], partnerCode: "minimal")
        config.col1 = "LL"
        let feed = SellwildFeedView(config: config)
        let host = Host()
        host.add(feed)
        feed.frame = host.controller.view.bounds
        XCTAssertEqual(SellwildViews.feedViews, 1)

        let rows = { feed.tableView(feed.tableView, numberOfRowsInSection: 0) }
        let showRows = {
            for row in 0..<rows() { _ = feed.tableView(feed.tableView, cellForRowAt: IndexPath(row: row, section: 0)) }
        }
        feed.load()
        spin { rows() == 3 }
        XCTAssertEqual(rows(), 3, "header and two listings")
        showRows()
        feed.load()
        spin { pushed.filter { $0.action == "listings.fetch" }.count == 2 }
        spin { rows() == 3 }
        showRows()

        XCTAssertEqual(pushed.filter { $0.action == "feed.firstListing" }.count, 1)
        XCTAssertEqual(Set(pushed.map(\.action)), ["listings.fetch", "listings.decode", "feed.firstListing"])
        feed.removeFromSuperview()
        XCTAssertEqual(SellwildViews.feedViews, 0)
        capture.none()
    }
}
