import XCTest
import UIKit
import GoogleMobileAds
@testable import SellwildSDK

/// Records every `SellwildFeedViewDelegate` call.
final class FeedDelegateRecorder: SellwildFeedViewDelegate {
    var calls: [String] = []
    var consumeTaps = false
    var heights: [CGFloat] = []

    func sellwildFeed(_ feed: SellwildFeedView, didTapListing listing: SellwildListing) -> Bool {
        calls.append("tap \(listing.id)")
        return consumeTaps
    }
    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdImpressionForZoneId zoneId: String) { calls.append("impression \(zoneId)") }
    func sellwildFeed(_ feed: SellwildFeedView, didRecordAdClickForZoneId zoneId: String) { calls.append("click \(zoneId)") }
    func sellwildFeedDidLoad(_ feed: SellwildFeedView) { calls.append("load") }
    func sellwildFeed(_ feed: SellwildFeedView, didBecomeReadyWithListingCount count: Int) { calls.append("ready \(count)") }
    func sellwildFeed(_ feed: SellwildFeedView, didFailWithError message: String) { calls.append("fail") }
    func sellwildFeed(_ feed: SellwildFeedView, didChangeContentHeight height: CGFloat) { heights.append(height) }
    func sellwildFeed(_ feed: SellwildFeedView, didRecordHouseAdImpressionForZoneId zoneId: String) { calls.append("house \(zoneId)") }
}

/// A delegate that takes every default.
final class DefaultFeedDelegate: SellwildFeedViewDelegate {}

/// The native feed shell: listings through a stub session, ad rows built
/// from `SellwildAdView` with the fake ad network, taps presented through a
/// recorder, photos through the stub session.
final class SellwildFeedViewTests: ViewTestCase {

    private var adViews: [SellwildAdView] = []
    private var presented: [URL] = []
    private var listingsAnswer: () throws -> StubURLProtocol.Response = { .init(status: 503) }
    private var localizedAnswer: () throws -> StubURLProtocol.Response = { .init(status: 404) }

    override func setUp() {
        super.setUp()
        adViews = []
        presented = []
        SellwildListingCardView.cache.removeAllObjects()
        SellwildFeedView.environment = SellwildFeedView.Environment(
            makeAPIClient: { SellwildAPIClient(session: StubURLProtocol.makeSession()) },
            makeAdView: { [weak self] config, size, zone in
                let view = SellwildAdView(config: config, adSize: size, zoneId: zone)
                self?.adViews.append(view)
                return view
            },
            present: { [weak self] url, _ in self?.presented.append(url) },
            imageSession: StubURLProtocol.makeSession()
        )
        StubURLProtocol.handler = { [weak self] request in
            guard let self else { return .init(status: 500) }
            if request.url?.host?.contains("sellwild-sports-cache") == true { return try self.localizedAnswer() }
            if ["png", "jpg", "jpeg", "webp"].contains(request.url?.pathExtension ?? "") {
                return .init(status: 200, body: testPNG())
            }
            return try self.listingsAnswer()
        }
    }

    override func tearDown() {
        SellwildFeedView.environment = .live
        SellwildListingCardView.cache.removeAllObjects()
        super.tearDown()
    }

    private func listings(_ count: Int) throws -> [[String: Any]] {
        try (1...count).map { try ListingFactory.make(["id": "\($0)", "url": "https://sellwild.com/listing/\($0)"]) }
    }

    private func answerListings(_ items: [[String: Any]]) throws {
        let data = try ListingsResponseFactory.data(listings: items)
        listingsAnswer = { .init(status: 200, headers: ["Content-Type": "application/json"], body: data) }
    }

    private func feedConfig(_ overrides: [String: Any] = [:], col1: String? = "LGLB") throws -> SellwildConfig {
        var config = try AppConfigFactory.config(overrides, partnerCode: "minimal")
        config.col1 = col1
        config.mobileZids = ["43"]
        config.mobileBannerZid = "b1"
        config.gamTag = "/1/app/feed"
        return config
    }

    /// A feed, loaded until its delegate hears `ready`.
    private func loadedFeed(_ config: SellwildConfig) -> (SellwildFeedView, FeedDelegateRecorder) {
        let feed = SellwildFeedView(config: config)
        let delegate = FeedDelegateRecorder()
        feed.delegate = delegate
        objc_setAssociatedObject(feed, &Self.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        feed.frame = CGRect(x: 0, y: 0, width: 400, height: 3000)
        feed.load()
        spin { delegate.calls.contains { $0.hasPrefix("ready") || $0 == "fail" } }
        return (feed, delegate)
    }

    private static var delegateKey: UInt8 = 0

    private func cell(_ feed: SellwildFeedView, _ row: Int) -> UITableViewCell {
        feed.tableView(feed.tableView, cellForRowAt: IndexPath(row: row, section: 0))
    }

    private func card(in cell: UITableViewCell) -> SellwildListingCardView? {
        cell.contentView.subviews.compactMap { $0 as? SellwildListingCardView }.first
    }

    // MARK: Load

    func testLoadRendersTheScheduleWithUniqueGPIDs() throws {
        try answerListings(listings(2))
        var feedAndDelegate: (SellwildFeedView, FeedDelegateRecorder)?
        let lines = try debugLines { feedAndDelegate = loadedFeed(try feedConfig(["GPID_BASE": "/1/app"], col1: " lgglb ")) }
        let (feed, delegate) = try XCTUnwrap(feedAndDelegate)
        XCTAssertEqual(delegate.calls, ["load", "ready 2"])
        XCTAssertEqual(feed.tableView(feed.tableView, numberOfRowsInSection: 0), 6, "header, L, G, G, L, B")
        XCTAssertTrue(lines.contains { $0.contains("feed load() partner=minimal col1= lgglb ") }, "\(lines)")
        XCTAssertTrue(lines.contains("[Sellwild] feed rows=6 listings=2"), "\(lines)")

        for row in 0..<6 { _ = cell(feed, row) }
        XCTAssertEqual(adViews.map(\.zoneId), ["43", "43", "b1"])
        XCTAssertEqual(adViews.map(\.adSize), [.mrec300x250, .mrec300x250, .banner320x50])
        XCTAssertEqual(adViews.map(\.gpidOverride), ["/1/app#1", "/1/app#2", "/1/app#3"])
        XCTAssertEqual(network.bootstraps.count, 3, "each ad row loads its ad view")
        XCTAssertTrue(adViews.allSatisfy { $0.firstAdViewedGuard === adViews[0].firstAdViewedGuard }, "one guard per feed")
        capture.none()
    }

    func testAFailedFetchIsPassedOnAndReportedOnlyByTheClient() throws {
        listingsAnswer = { .init(status: 503) }
        let (_, delegate) = loadedFeed(try feedConfig())
        XCTAssertEqual(delegate.calls, ["fail"])
        XCTAssertEqual(capture.events.map(\.action), ["listings.fetch.http"], "the feed does not report it again")
    }

    func testRefreshFetchesAgain() throws {
        try answerListings(listings(1))
        let (feed, delegate) = loadedFeed(try feedConfig())
        delegate.calls = []
        feed.refresh()
        spin { delegate.calls.contains("ready 1") }
        XCTAssertEqual(delegate.calls, ["load", "ready 1"])
    }

    // MARK: Localized dispersion

    func testLocalizedListingsAreMergedIn() throws {
        try answerListings(listings(3))
        let secondary = try LocalizedListingsFactory.response(
            state: "AL", listings: [ListingFactory.make(["id": "s1", "title": "Local pick"])])
        let data = try Factory.data(secondary)
        localizedAnswer = { .init(status: 200, headers: ["Content-Type": "application/json"], body: data) }
        let config = try feedConfig(["LOCALIZED_LISTINGS": try LocalizedListingsFactory.config(["frequency": 50])], col1: "LLL")
        let (feed, delegate) = loadedFeed(config)
        XCTAssertEqual(delegate.calls, ["load", "ready 3"], "every 2nd slot is replaced, the count stays")
        XCTAssertEqual(card(in: cell(feed, 2))?.titleLabel.text, "Local pick")
        XCTAssertEqual(card(in: cell(feed, 1))?.titleLabel.text, "2021 Lexus UX UX 200")
        XCTAssertTrue(StubURLProtocol.requests.contains { $0.url?.lastPathComponent == "sports-img-data-sm-webp-al.json" })
        capture.none()
    }

    func testAFailedLocalizedFetchRendersThePrimaryFeed() throws {
        try answerListings(listings(2))
        localizedAnswer = { .init(status: 404) }
        let (_, delegate) = loadedFeed(try feedConfig(["LOCALIZED_LISTINGS": try LocalizedListingsFactory.config()]))
        XCTAssertEqual(delegate.calls, ["load", "ready 2"])
    }

    func testLocalizedListingsWithoutAFrequencyOrAStateAreSkipped() throws {
        try answerListings(listings(2))
        let noFrequency = try feedConfig(["LOCALIZED_LISTINGS": try LocalizedListingsFactory.config(["frequency": 0])])
        XCTAssertEqual(loadedFeed(noFrequency).1.calls, ["load", "ready 2"])
        let noState = try feedConfig(["LOCALIZED_LISTINGS": try LocalizedListingsFactory.config(["forceState": Factory.remove])])
        XCTAssertEqual(loadedFeed(noState).1.calls, ["load", "ready 2"])
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url?.host?.contains("sellwild-sports-cache") == true })
    }

    // MARK: Schedule problems

    func testTokensThatCannotBecomeRowsAreReportedOnceALaunch() throws {
        let feed = SellwildFeedView(config: try feedConfig())
        var config = try feedConfig(col1: "GDBXL")
        config.mobileZids = [""]
        config.mobileBannerZid = nil
        feed.update(config: config)
        feed.update(config: config)
        XCTAssertEqual(feed.tableView(feed.tableView, numberOfRowsInSection: 0), 1, "only the header")
        XCTAssertEqual(capture.events.map(\.action), ["feed.ad_zone.missing", "feed.ad_zone.missing", "feed.layout.invalid"])
        XCTAssertEqual(capture.calls, 3, "once a launch each")
        XCTAssertEqual(capture.events.last?.attributes["msg"], "COL1 holds the unknown token \"X\"; it is ignored")
    }

    func testThemeFollowsTheBackground() throws {
        var config = try feedConfig()
        config.bgColor = "#000000"
        let feed = SellwildFeedView(config: config)
        XCTAssertEqual(feed.backgroundColor, UIColor(red: 0, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(feed.refreshControl.tintColor, .white)
        config.bgColor = nil
        feed.update(config: config)
        XCTAssertEqual(feed.refreshControl.tintColor, UIColor(white: 0.4, alpha: 1))
    }

    // MARK: Sizing

    func testContentHeightIsReportedAndDrivesTheIntrinsicSize() throws {
        try answerListings(listings(2))
        let (feed, delegate) = loadedFeed(try feedConfig(col1: "LL"))
        let host = display(feed)
        spin { !delegate.heights.isEmpty }
        XCTAssertEqual(delegate.heights.last, feed.contentHeight)
        XCTAssertEqual(feed.intrinsicContentSize.height, UIView.noIntrinsicMetric, "scrolling feeds do not self-size")
        feed.scrollEnabled = false
        XCTAssertNil(feed.tableView.refreshControl)
        XCTAssertEqual(feed.intrinsicContentSize.height, feed.contentHeight)
        let reported = delegate.heights.count
        feed.tableView.contentSize = feed.tableView.contentSize
        XCTAssertEqual(delegate.heights.count, reported, "an unchanged height is not reported again")
        feed.tableView.contentSize = CGSize(width: 400, height: feed.contentHeight + 10)
        XCTAssertEqual(delegate.heights.count, reported + 1)
        XCTAssertEqual(feed.intrinsicContentSize.height, feed.contentHeight)
        feed.scrollEnabled = true
        XCTAssertTrue(feed.tableView.refreshControl === feed.refreshControl)
        withExtendedLifetime(host) {}
    }

    // MARK: Taps

    func testATappedListingOpensInSafariFromTheHost() throws {
        try answerListings(listings(1))
        let (feed, delegate) = loadedFeed(try feedConfig(col1: "L"))
        let host = Host()
        host.add(feed)
        feed.tableView(feed.tableView, didSelectRowAt: IndexPath(row: 1, section: 0))
        XCTAssertEqual(delegate.calls.last, "tap 1")
        XCTAssertEqual(presented.map(\.absoluteString), ["https://sellwild.com/listing/1"])
        delegate.consumeTaps = true
        feed.tableView(feed.tableView, didSelectRowAt: IndexPath(row: 1, section: 0))
        XCTAssertEqual(presented.count, 1, "a consumed tap is not opened")
        feed.tableView(feed.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual(delegate.calls.filter { $0.hasPrefix("tap") }.count, 2, "the header is not a listing")
        capture.none()
    }

    func testTapsThatCannotOpenAreReported() throws {
        try answerListings([try ListingFactory.make(["id": "1", "url": "tel:5551234"]),
                            try ListingFactory.make(["id": "", "dataSourceId": "7", "url": Factory.remove])])
        let (feed, _) = loadedFeed(try feedConfig(col1: "LL"))
        feed.tableView(feed.tableView, didSelectRowAt: IndexPath(row: 1, section: 0))
        XCTAssertEqual(capture.only(.feedOpenUrlInvalid, label: .feed)?.attributes["msg"], "the URL is not http(s)")
        resetCapture()
        feed.tableView(feed.tableView, didSelectRowAt: IndexPath(row: 2, section: 0))
        XCTAssertEqual(capture.only(.feedOpenUrlInvalid, label: .feed)?.attributes["msg"], "there is no URL to open")
        XCTAssertEqual(presented, [])
    }

    func testATapOutsideAViewControllerIsReported() throws {
        try answerListings(listings(1))
        let (feed, _) = loadedFeed(try feedConfig(col1: "L"))
        feed.tableView(feed.tableView, didSelectRowAt: IndexPath(row: 1, section: 0))
        XCTAssertEqual(capture.only(.feedOpenUrlInvalid, label: .feed)?.attributes["msg"], "no view controller to present the page from")
        XCTAssertEqual(presented, [])
    }

    func testTheHeaderOpensThePartnerPageAndSellwild() throws {
        var config = try feedConfig(col1: "")
        config.partnerUrl = "https://partner.example"
        config.title = "Deals"
        let feed = SellwildFeedView(config: config)
        let host = Host()
        host.add(feed)
        let header = cell(feed, 0)
        let title = header.contentView.subviews.compactMap { $0 as? UILabel }.first
        XCTAssertEqual(title?.text, "Deals")
        header.perform(NSSelectorFromString("titleTapped"))
        header.perform(NSSelectorFromString("poweredByTapped"))
        XCTAssertEqual(presented.map(\.absoluteString), ["https://partner.example", "https://sellwild.com"])

        config.partnerUrl = nil
        config.title = nil
        feed.update(config: config)
        let bare = cell(feed, 0)
        XCTAssertEqual(bare.contentView.subviews.compactMap { $0 as? UILabel }.first?.text, "Marketplace")
        bare.perform(NSSelectorFromString("titleTapped"))
        XCTAssertEqual(presented.count, 2, "no partner page, nothing to open")
        capture.none()
    }

    // MARK: Ad rows

    /// Puts the feed on screen so the table makes (and later reuses) its
    /// cells itself.
    private func display(_ feed: SellwildFeedView) -> Host {
        let host = Host()
        host.add(feed)
        feed.frame = host.controller.view.bounds
        feed.tableView.layoutIfNeeded()
        return host
    }

    private func shown(_ feed: SellwildFeedView, _ row: Int) throws -> UITableViewCell {
        try XCTUnwrap(feed.tableView.cellForRow(at: IndexPath(row: row, section: 0)))
    }

    func testAnMRECNoFillSwapsToAListingCardAndBack() throws {
        try answerListings(listings(2))
        let (feed, delegate) = loadedFeed(try feedConfig(col1: "GL"))
        let host = display(feed)
        let adCell = try shown(feed, 1)
        let ad = try XCTUnwrap(adViews.first)
        let adDelegate = try XCTUnwrap(ad.delegate)
        adDelegate.sellwildAdView?(ad, didFailWithError: SellwildAdError.nativeNoFill)
        let fallback = try XCTUnwrap(card(in: adCell))
        XCTAssertFalse(fallback.isHidden)
        XCTAssertTrue(ad.isHidden)
        XCTAssertEqual(fallback.titleLabel.text, "2021 Lexus UX UX 200")
        XCTAssertEqual(delegate.calls.last, "house 43")

        fallback.onTap?()
        XCTAssertEqual(delegate.calls.last, "tap 2", "the backfill is a listing not shown elsewhere")
        XCTAssertEqual(presented.map(\.absoluteString), ["https://sellwild.com/listing/2"])

        feed.tableView.reloadData()
        feed.tableView.layoutIfNeeded()
        XCTAssertTrue(try shown(feed, 1) === adCell, "the row reuses its cell")
        XCTAssertEqual(adViews.count, 1, "the same zone keeps its ad view")
        XCTAssertFalse(fallback.isHidden, "the fallback stays, refreshed")

        adDelegate.sellwildAdViewDidLoad?(ad)
        XCTAssertTrue(fallback.isHidden)
        XCTAssertFalse(ad.isHidden)
        adDelegate.sellwildAdViewDidLoad?(ad)

        adDelegate.sellwildAdView?(ad, didReceiveImpressionForZoneId: "43")
        adDelegate.sellwildAdView?(ad, didRecordHouseImpressionForZoneId: "43")
        adDelegate.sellwildAdViewDidRecordClick?(ad)
        XCTAssertEqual(Array(delegate.calls.suffix(3)), ["impression 43", "house 43", "click 43"])
        withExtendedLifetime(host) {}
    }

    func testAnAdRowMovedToAnotherZoneGetsANewAdView() throws {
        try answerListings(listings(1))
        let (feed, _) = loadedFeed(try feedConfig(col1: "G"))
        let host = display(feed)
        XCTAssertEqual(adViews.map(\.zoneId), ["43"])
        var config = try feedConfig(col1: "G")
        config.mobileZids = ["44"]
        feed.update(config: config)
        feed.tableView.layoutIfNeeded()
        XCTAssertEqual(adViews.map(\.zoneId), ["43", "44"])
        XCTAssertNil(adViews.first?.superview, "the old ad view is removed")
        withExtendedLifetime(host) {}
    }

    func testANoFillWithAHouseImageOrNoListingKeepsTheSlot() throws {
        try answerListings(listings(1))
        let (feed, _) = loadedFeed(try feedConfig(["MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png"], col1: "GB"))
        let host = display(feed)
        let mrecCell = try shown(feed, 1)
        let bannerCell = try shown(feed, 2)
        XCTAssertEqual(adViews.count, 2)
        for ad in adViews {
            ad.delegate?.sellwildAdView?(ad, didFailWithError: SellwildAdError.nativeNoFill)
            XCTAssertFalse(ad.isHidden)
        }
        XCTAssertEqual(card(in: mrecCell)?.isHidden, true, "the house image shows in the slot")
        XCTAssertEqual(card(in: bannerCell)?.isHidden, true, "a banner row never swaps to a card")
        try XCTUnwrap(card(in: bannerCell)).onTap?()
        XCTAssertEqual(presented, [], "a card with no listing opens nothing")
        withExtendedLifetime(host) {}
    }

    func testACellOfTheWrongTypeIsReportedAndLeftBlank() throws {
        try answerListings(listings(1))
        let (feed, _) = loadedFeed(try feedConfig(col1: "LGB"))
        for (row, id) in [(0, "SellwildFeedHeaderCell"), (1, "SellwildFeedListingCardCell"),
                          (2, "SellwildFeedAdRowCell"), (3, "SellwildFeedAdRowCell")] {
            newLaunch()
            feed.tableView.register(UITableViewCell.self, forCellReuseIdentifier: id)
            let blank = cell(feed, row)
            XCTAssertTrue(type(of: blank) == UITableViewCell.self, "row \(row)")
            XCTAssertEqual(capture.only(.feedCellInvalid, label: .feed)?.attributes["severity"], "fatal")
        }
    }

    // MARK: Listing card photos

    private func cardView(_ overrides: [String: Any]) throws -> SellwildListingCardView {
        let card = SellwildListingCardView()
        card.configure(config: try feedConfig(), listing: try ListingFactory.decoded(ListingFactory.make(overrides)))
        return card
    }

    func testTheCardShowsTheListing() throws {
        let card = try cardView(["title": "Road bike", "price": "12.5", "currency": "GBP"])
        XCTAssertEqual(card.titleLabel.text, "Road bike")
        XCTAssertEqual(card.priceLabel.text, "£12.50")
        XCTAssertEqual(card.sellerLabel.text, "LOTLINX A.  |  sellwild.com")
        spin { card.photoView.image != nil }
        XCTAssertNotNil(card.photoView.image)
        capture.none()
    }

    func testAPhotoIsDownloadedOnceThenCached() throws {
        let url = "https://cdn.example/photo-a.png"
        _ = try cardView(["photos": [["url": url]]])
        spin { SellwildListingCardView.cache.object(forKey: url as NSString) != nil }
        let second = try cardView(["photos": [["url": url]]])
        XCTAssertNotNil(second.photoView.image, "a memory hit shows at once")
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url?.absoluteString == url }.count, 1)
    }

    func testADataURIPhotoIsDecoded() throws {
        let card = try cardView(["photos": [["url": testPNGDataURI()]]])
        spin { card.photoView.image != nil }
        XCTAssertNotNil(card.photoView.image)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        capture.none()
    }

    func testPhotosThatCannotShowAreReported() throws {
        _ = try cardView(["photos": [["url": "data:image/png;base64,bm90IGFuIGltYWdl"]]])
        spin { !self.capture.events.isEmpty }
        XCTAssertEqual(capture.only(.feedImageInvalid, label: .feed)?.attributes["msg"], "listing photo: image data could not be decoded")

        resetCapture()
        _ = try cardView(["photos": [["url": "file:///etc/photo.png"]]])
        XCTAssertEqual(capture.only(.feedImageInvalid, label: .feed)?.attributes["msg"], "listing photo URL is not http(s)")

        resetCapture()
        StubURLProtocol.handler = { _ in .init(status: 404) }
        _ = try cardView(["photos": [["url": "https://cdn.example/gone.jpg"]]])
        spin { !self.capture.events.isEmpty }
        let failed = capture.only(.feedImageNetwork, label: .feed)
        XCTAssertEqual(failed?.attributes["httpStatus"], "404")
        XCTAssertEqual(failed?.attributes["host"], "cdn.example")

        // Behavior change: an error answer is not shown even when its body is an image.
        resetCapture()
        StubURLProtocol.handler = { _ in .init(status: 500, body: testPNG()) }
        let errorPage = try cardView(["photos": [["url": "https://cdn.example/error.png"]]])
        spin { !self.capture.events.isEmpty }
        XCTAssertEqual(capture.only(.feedImageNetwork, label: .feed)?.attributes["httpStatus"], "500")
        XCTAssertNil(errorPage.photoView.image)

        resetCapture()
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("text".utf8)) }
        _ = try cardView(["photos": [["url": "https://cdn.example/text.jpg"]]])
        spin { !self.capture.events.isEmpty }
        XCTAssertEqual(capture.only(.feedImageInvalid, label: .feed)?.attributes["msg"], "listing photo: image data could not be decoded")
    }

    func testAPhotoForAListingTheCardLeftIsDroppedAndACancelIsNotReported() throws {
        StubURLProtocol.handler = { request in
            Thread.sleep(forTimeInterval: 0.3)
            return .init(status: 200, body: testPNG())
        }
        let card = try cardView(["photos": [["url": "https://cdn.example/slow.png"]]])
        card.reset()
        XCTAssertNil(card.photoView.image)
        spin(timeout: 1) { false }
        XCTAssertNil(card.photoView.image)
        capture.none()

        let stale = try cardView(["photos": [["url": "https://cdn.example/stale.png"]]])
        stale.configure(config: try feedConfig(), listing: try ListingFactory.decoded(ListingFactory.make(["photos": [Any]()])))
        spin(timeout: 1) { false }
        XCTAssertNil(stale.photoView.image, "the old photo does not land on the new listing")
    }

    func testTheFallbackCardTapIsOnlyOnWithAHandler() throws {
        let card = SellwildListingCardView()
        var taps = 0
        card.perform(NSSelectorFromString("tapped"))
        card.onTap = { taps += 1 }
        card.perform(NSSelectorFromString("tapped"))
        XCTAssertEqual(taps, 1)
    }

    // MARK: Defaults and lifetime

    func testTheDelegateDefaultsDoNothing() throws {
        try answerListings(listings(1))
        let feed = SellwildFeedView(config: try feedConfig(col1: "LGB"))
        let delegate = DefaultFeedDelegate()
        feed.delegate = delegate
        feed.load()
        spin { feed.tableView(feed.tableView, numberOfRowsInSection: 0) == 4 }
        let host = display(feed)
        feed.tableView(feed.tableView, didSelectRowAt: IndexPath(row: 1, section: 0))
        XCTAssertEqual(presented.count, 1, "the default does not consume the tap")
        XCTAssertFalse(adViews.isEmpty, "the ad rows on screen made their ad views")
        withExtendedLifetime(host) {}
        for ad in adViews {
            ad.delegate?.sellwildAdView?(ad, didReceiveImpressionForZoneId: "z")
            ad.delegate?.sellwildAdView?(ad, didRecordHouseImpressionForZoneId: "z")
            ad.delegate?.sellwildAdViewDidRecordClick?(ad)
        }
        delegate.sellwildFeed(feed, didFailWithError: "x")
        delegate.sellwildFeed(feed, didChangeContentHeight: 1)
        listingsAnswer = { .init(status: 503) }
        feed.refresh()
        spin(timeout: 1) { false }
    }

    func testTheLiveEnvironmentMakesItsOwnClientPerFeedAndRealAdViews() throws {
        let live = SellwildFeedView.Environment.live
        XCTAssertFalse(live.makeAPIClient() === live.makeAPIClient())
        XCTAssertTrue(live.imageSession === URLSession.shared)
        let ad = live.makeAdView(try feedConfig(), .mrec300x250, "43")
        XCTAssertEqual(ad.zoneId, "43")
        XCTAssertEqual(ad.adSize, .mrec300x250)
    }

    func testUnreadableColorsFallBackToTheDefaults() throws {
        var config = try feedConfig(col1: "L")
        config.titleColor = "nope"
        config.linkColor = "nope"
        config.title = "Deals"
        let feed = SellwildFeedView(config: config)
        let header = cell(feed, 0)
        let labels = header.contentView.subviews.compactMap { $0 as? UILabel }
        XCTAssertEqual(labels.first?.textColor, .white)
        XCTAssertEqual(labels.last?.textColor, UIColor(white: 0.7, alpha: 1))
        let card = SellwildListingCardView()
        card.configure(config: config, listing: try ListingFactory.decoded(ListingFactory.make()))
        XCTAssertEqual(card.priceLabel.textColor, UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1))
    }

    func testTheLoadTraceNamesAMissingLayout() throws {
        try answerListings(listings(1))
        var config = try feedConfig(col1: nil)
        config.mobileZids = ["43"]
        let lines = debugLines { _ = loadedFeed(config) }
        XCTAssertTrue(lines.contains { $0.contains("col1=(nil)") }, "\(lines)")
    }

    func testAFeedThatIsGoneStopsObserving() throws {
        weak var gone: SellwildFeedView?
        try autoreleasepool {
            let feed = SellwildFeedView(config: try feedConfig())
            gone = feed
        }
        XCTAssertNil(gone)
    }
}
