import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import SellwildSDK

/// SellwildAPI.swift outside the events queue: the listing model, the
/// listings and localized-cache fetches, the events kill switch parser, the
/// session uid and the errors. Payloads come from the factories and every
/// request goes to `StubURLProtocol`.
final class SellwildAPIClientTests: XCTestCase {

    private var session: URLSession!
    private var client: SellwildAPIClient!
    /// The failure paths below report; `SellwildListingsFailureTests` checks
    /// each report. Here they are only captured, never sent.
    private var capture: FailureCapture!

    override func setUp() {
        super.setUp()
        SellwildFailures.resetForTests()
        capture = FailureCapture()
        capture.install()
        session = StubURLProtocol.makeSession()
        client = SellwildAPIClient(session: session)
    }

    override func tearDown() {
        session.finishTasksAndInvalidate()
        client = nil
        SellwildGeoStore.current = nil
        SellwildFailures.resetForTests()
        capture = nil
        super.tearDown()
    }

    private func config(listingsUrl: String? = nil, partnerCode: String = "weatherbug") -> SellwildConfig {
        SellwildConfig(partnerCode: partnerCode, listingsUrl: listingsUrl)
    }

    private func fetch(_ config: SellwildConfig, on client: SellwildAPIClient? = nil) -> Result<SellwildListingsResponse, Error> {
        let done = expectation(description: "fetchListings")
        var result: Result<SellwildListingsResponse, Error>?
        (client ?? self.client).fetchListings(config: config) {
            XCTAssertTrue(Thread.isMainThread)
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result ?? .failure(SellwildError.noData)
    }

    private func fetchCache(_ url: URL, on client: SellwildAPIClient? = nil) -> Result<[SellwildListing], Error> {
        let done = expectation(description: "fetchCacheListings")
        var result: Result<[SellwildListing], Error>?
        (client ?? self.client).fetchCacheListings(url: url) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result ?? .failure(SellwildError.noData)
    }

    // MARK: Listing model

    func testListingDecodesFlexibleShapes() throws {
        let listing = try ListingFactory.decoded(Factory.offSchema(because: "categoryId must be text or a whole number; the decoder reads 7.5 as text") {
            try ListingFactory.make([
                "id": 105140231, "status": 1, "categoryId": 7.5, "price": 19315, "strikePrice": "20000",
                "shippable": 1, "dataSourceId": 31, "distance": 2.5, "text": "t", "url": "https://x.invalid/a",
                "currency": "USD", "has_photo": true, "createdDate": "2026-09-01",
            ])
        })
        XCTAssertEqual(listing.id, "105140231")
        XCTAssertEqual(listing.status, "1")
        XCTAssertEqual(listing.categoryId, "7.5")
        XCTAssertEqual(listing.price, "19315")
        XCTAssertEqual(listing.shippable, true)
        XCTAssertEqual(listing.dataSourceId, "31")
        XCTAssertEqual(listing.distance, 2.5)
        XCTAssertEqual(listing.remoteUrl, "https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1")
        XCTAssertEqual(listing.user?.firstName, "Lotlinx")
        XCTAssertEqual(listing.primaryPhoto?.url, "https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231.jpg")

        let text = try ListingFactory.decoded(ListingFactory.variant("localized-item-text-shippable"))
        XCTAssertEqual(text.shippable, true, "\"1\" is true")
        XCTAssertEqual(try ListingFactory.decoded(ListingFactory.make(["shippable": "TRUE"])).shippable, true)
        XCTAssertEqual(try ListingFactory.decoded(ListingFactory.make(["shippable": "0"])).shippable, false)
        XCTAssertEqual(try ListingFactory.decoded(ListingFactory.make(["shippable": 0])).shippable, false)
        XCTAssertNil(try ListingFactory.decoded(ListingFactory.make(["shippable": Factory.remove])).shippable)
        XCTAssertNil(try ListingFactory.decoded(Factory.offSchema(because: "shippable must be a flag, not a list") {
            try ListingFactory.make(["shippable": ["x"]])
        }).shippable)

        let bare = try ListingFactory.decoded(Factory.offSchema(because: "id, title and photos are required and price must be a number or text") {
            try ListingFactory.make([
                "id": Factory.remove, "status": Factory.remove, "title": Factory.remove, "photos": Factory.remove,
                "price": ["not": "a price"],
            ])
        })
        XCTAssertEqual(bare.id, "")
        XCTAssertEqual(bare.status, "")
        XCTAssertEqual(bare.title, "")
        XCTAssertNil(bare.price)
        XCTAssertNil(bare.primaryPhoto)
    }

    func testTapURL() throws {
        let direct = try ListingFactory.decoded(ListingFactory.make(["url": "https://shop.invalid/p?tag=old&x=1"]))
        XCTAssertEqual(direct.tapURL(partnerCode: "p", bhTag: "bh-1"), "https://shop.invalid/p?x=1&tag=bh-1")
        XCTAssertEqual(direct.tapURL(partnerCode: "p"), "https://shop.invalid/p?tag=old&x=1")
        XCTAssertEqual(direct.tapURL(partnerCode: "p", bhTag: ""), "https://shop.invalid/p?tag=old&x=1")
        let bare = try ListingFactory.decoded(ListingFactory.make(["url": "https://shop.invalid/p"]))
        XCTAssertEqual(bare.tapURL(partnerCode: "p", bhTag: "bh"), "https://shop.invalid/p?tag=bh")
        let unparsable = try ListingFactory.decoded(ListingFactory.make(["url": "http://exa mple.invalid/[x"]))
        XCTAssertEqual(unparsable.tapURL(partnerCode: "p", bhTag: "bh"), "http://exa mple.invalid/[x")

        let remote = try ListingFactory.decoded(ListingFactory.make())
        XCTAssertEqual(remote.tapURL(partnerCode: "p"), "https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1")

        let canonical = try ListingFactory.decoded(ListingFactory.make(["dataSourceId": "7", "url": ""]))
        XCTAssertEqual(canonical.tapURL(partnerCode: "weather bug"),
                       "https://sellwild.com/product/105140231?p=weather%20bug&utm_source=weather%20bug")
        XCTAssertEqual(canonical.tapURL(partnerCode: nil), "https://sellwild.com/product/105140231?p=sellwild&utm_source=sellwild")
        XCTAssertEqual(canonical.tapURL(partnerCode: ""), "https://sellwild.com/product/105140231?p=sellwild&utm_source=sellwild")
        let noRemote = try ListingFactory.decoded(ListingFactory.make(["remote_url": ""]))
        XCTAssertEqual(noRemote.tapURL(partnerCode: "p"), "https://sellwild.com/product/105140231?p=p&utm_source=p")
        let noId = try ListingFactory.decoded(ListingFactory.make(["id": "", "dataSourceId": "7"]))
        XCTAssertNil(noId.tapURL(partnerCode: "p"))
    }

    func testDisplayPrice() throws {
        XCTAssertEqual(try ListingFactory.decoded(ListingFactory.make(["price": "19315.4"])).displayPrice, "19315")
        XCTAssertNil(try ListingFactory.decoded(ListingFactory.make(["price": "0"])).displayPrice)
        XCTAssertNil(try ListingFactory.decoded(ListingFactory.make(["price": "free"])).displayPrice)
        XCTAssertNil(try ListingFactory.decoded(ListingFactory.make(["price": Factory.remove])).displayPrice)
    }

    // MARK: fetchListings

    func testStaticCacheIsAGetParsedAndCached() throws {
        StubURLProtocol.handler = { _ in
            let body = try ListingsResponseFactory.data(result: ["widgetCacheVersionId": "733489", "config": ["browse": 0]])
            return .init(status: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        let config = config(listingsUrl: "https://cache.sellwild.com/listings-img-data-sm")
        let response = try fetch(config).get()

        XCTAssertFalse(response.listings.isEmpty)
        XCTAssertEqual(response.widgetCacheVersionId, "733489")
        XCTAssertEqual(response.config["browse"] as? Int, 0)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

        // Same URL and partner: served from the cache without a request.
        XCTAssertEqual(try fetch(config).get().listings.count, response.listings.count)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        client.clearCache()
        _ = try fetch(config).get()
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testOtherHostsGetTheJSONRPCPost() throws {
        StubURLProtocol.handler = { _ in try .json(ListingsResponseFactory.variant("rpc-envelope")) }
        let response = try fetch(config(listingsUrl: "https://api.sellwild.invalid/supplyListing/rpc")).get()

        XCTAssertEqual(response.listings.map(\.title), ["Road bike"])
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(envelope["method"] as? String, "getFeaturedListingsForPartnerWidget")
        XCTAssertEqual(envelope["params"] as? [String], ["weatherbug", "regular"])
    }

    func testURLWithoutAHostIsNotTheStaticCache() throws {
        StubURLProtocol.handler = { _ in try .json(ListingsResponseFactory.variant("rpc-envelope")) }
        _ = try fetch(config(listingsUrl: "stub:listings")).get()
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "POST")
    }

    func testResultWithoutListingsIsEmpty() throws {
        let body = try Factory.offSchema(because: "result.rs is required") { try ListingsResponseFactory.variant("empty-rs", result: ["rs": Factory.remove]) }
        StubURLProtocol.handler = { _ in try .json(body) }
        let response = try fetch(config(listingsUrl: "https://cache.sellwild.com/none")).get()
        XCTAssertTrue(response.listings.isEmpty)
    }

    func testCloudFrontHeadersSeedGeoOnlyWhenEmpty() throws {
        #if canImport(UIKit)
        // Seeding re-emits the global ORTB config, which reads
        // UIDevice.current.userInterfaceIdiom. The first read in a process
        // waits on a system XPC call that can take over 10 s on a freshly
        // booted simulator; make it here, outside the fetch's timeout.
        _ = UIDevice.current.userInterfaceIdiom
        #endif
        SellwildGeoStore.current = nil
        StubURLProtocol.handler = { _ in
            .init(status: 200, headers: ["CloudFront-Viewer-Country-Region": " GA ", "CloudFront-Viewer-Country": "US"],
                  body: try ListingsResponseFactory.data())
        }
        _ = try fetch(config(listingsUrl: "https://cache.sellwild.com/a")).get()
        XCTAssertEqual(SellwildGeoStore.current?.state, "GA")
        XCTAssertEqual(SellwildGeoStore.current?.country, "USA")

        // A partner value is never overwritten, and countries outside North
        // America are not sent.
        SellwildGeoStore.current = SellwildGeo(state: "TX")
        StubURLProtocol.handler = { _ in
            .init(status: 200, headers: ["CloudFront-Viewer-Country-Region": "GA", "CloudFront-Viewer-Country": "FR"],
                  body: try ListingsResponseFactory.data())
        }
        _ = try fetch(config(listingsUrl: "https://cache.sellwild.com/b")).get()
        XCTAssertEqual(SellwildGeoStore.current?.state, "TX")
        XCTAssertNil(SellwildGeoStore.current?.country)
    }

    func testFetchListingsFailures() throws {
        XCTAssertThrowsError(try fetch(config(listingsUrl: "http://exa mple.invalid/")).get()) { error in
            XCTAssertEqual(error.localizedDescription, "Invalid URL: http://exa mple.invalid/")
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)

        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        XCTAssertThrowsError(try fetch(config(listingsUrl: "https://cache.sellwild.com/t")).get()) { error in
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }

        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("{".utf8)) }
        XCTAssertThrowsError(try fetch(config(listingsUrl: "https://cache.sellwild.com/p")).get())

        StubURLProtocol.handler = { _ in try .json([ListingFactory.make()]) }
        XCTAssertThrowsError(try fetch(config(listingsUrl: "https://cache.sellwild.com/a")).get()) { error in
            XCTAssertEqual(error.localizedDescription, SellwildError.invalidResponse.localizedDescription)
        }
    }

    func testUndecodableItemsAreDroppedAndBareRootIsAccepted() throws {
        let good = try ListingFactory.make()
        let bad = try Factory.offSchema(because: "user.id must be text: the item the SDK drops") { try ListingFactory.variant("rpc-item", ["user": ["id": 1234]]) }
        StubURLProtocol.handler = { _ in try .json(["rs": [good, bad]]) }
        let response = try fetch(config(listingsUrl: "https://cache.sellwild.com/mixed")).get()
        XCTAssertEqual(response.listings.map(\.id), ["105140231"])
        XCTAssertNil(response.widgetCacheVersionId)
        XCTAssertTrue(response.config.isEmpty)
    }

    func testResponseAfterTheClientIsGoneIsEmpty() throws {
        let gate = DispatchSemaphore(value: 0)
        StubURLProtocol.handler = { _ in
            gate.wait()
            return .init(status: 200, body: try ListingsResponseFactory.data())
        }
        var owner: SellwildAPIClient? = SellwildAPIClient(session: session)
        weak var released: SellwildAPIClient?
        released = owner
        let done = expectation(description: "completion")
        var listings: [SellwildListing]?
        owner?.fetchListings(config: config(listingsUrl: "https://cache.sellwild.com/gone")) { result in
            listings = try? result.get().listings
            done.fulfill()
        }
        owner = nil
        XCTAssertNil(released)
        gate.signal()
        wait(for: [done], timeout: 10)
        XCTAssertEqual(listings?.count, 0)
    }

    @available(iOS 15, macOS 12, *)
    func testAsyncFetchListings() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: try ListingsResponseFactory.data()) }
        let response = try await client.fetchListings(config: config(listingsUrl: "https://cache.sellwild.com/async"))
        XCTAssertFalse(response.listings.isEmpty)

        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.fetchListings(config: config(listingsUrl: "https://cache.sellwild.com/async-fail"))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    // MARK: fetchCacheListings

    func testLocalizedCacheFetch() throws {
        let url = try XCTUnwrap(URL(string: "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/sports-img-data-sm-webp-ga.json"))
        StubURLProtocol.handler = { _ in try .json(LocalizedListingsFactory.response()) }
        let listings = try fetchCache(url).get()
        XCTAssertFalse(listings.isEmpty)
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "GET")
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Accept"), "application/json")

        let denied = try Fixtures.data("samples/localized-listings-response/sports-img-data-sm-webp-zz.403.xml")
        StubURLProtocol.handler = { _ in .init(status: 403, body: denied) }
        XCTAssertThrowsError(try fetchCache(url).get()) { error in
            XCTAssertEqual(error.localizedDescription, SellwildError.invalidResponse.localizedDescription)
        }
        StubURLProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        XCTAssertThrowsError(try fetchCache(url).get()) { error in
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("[]".utf8)) }
        XCTAssertThrowsError(try fetchCache(url).get())
    }

    func testLocalizedCacheAfterTheClientIsGoneIsEmpty() throws {
        let gate = DispatchSemaphore(value: 0)
        StubURLProtocol.handler = { _ in
            gate.wait()
            return try .json(LocalizedListingsFactory.response())
        }
        var owner: SellwildAPIClient? = SellwildAPIClient(session: session)
        let done = expectation(description: "completion")
        var listings: [SellwildListing]?
        owner?.fetchCacheListings(url: try XCTUnwrap(URL(string: "https://cache.invalid/ga.json"))) { result in
            listings = try? result.get()
            done.fulfill()
        }
        owner = nil
        gate.signal()
        wait(for: [done], timeout: 10)
        XCTAssertEqual(listings?.count, 0)
    }

    // MARK: Kill switch, session, errors

    func testEventsKillSwitchParsing() throws {
        func enabled(_ value: Any) throws -> Bool {
            SellwildEvents.isEnabled(remoteValues: try AppConfigFactory.remote(["EVENTS_ENABLED": value]))
        }
        XCTAssertTrue(SellwildEvents.isEnabled(remoteValues: nil))
        XCTAssertTrue(SellwildEvents.isEnabled(remoteValues: try AppConfigFactory.remote()))
        XCTAssertFalse(try enabled(false))
        XCTAssertTrue(try enabled(true))
        XCTAssertFalse(try enabled(0))
        XCTAssertTrue(try enabled(2))
        for off in ["false", " OFF ", "no", "0"] {
            XCTAssertFalse(try enabled(off), off)
        }
        XCTAssertTrue(try enabled("yes"))
        let objectFlag = Factory.stripMarkers(try Fixtures.dict("fixtures/app-config/invalid/events-enabled-object.json"))
        XCTAssertTrue(SellwildEvents.isEnabled(remoteValues: objectFlag), "an object (outside the schema) is the default")
    }

    /// The EVENTS_ENABLED parser against the contract's coerceFlag table
    /// (FAILURES.md 5.3): ASCII trim and ASCII lower case, so " off\n" is off
    /// and U+00A0 is not trimmed.
    func testEventsKillSwitchAgreesWithTheContractTable() throws {
        let units = try XCTUnwrap(try Fixtures.dict("golden/log-failure.vectors.json")["units"] as? [String: Any])
        let table = try XCTUnwrap(units["coerceFlag"] as? [[String: Any]])
        for row in table {
            // JSON null is an absent key; the rest go through the factory.
            let values: [String: Any]? = try row["input"].map { input in
                if input is NSNull { return try AppConfigFactory.remote() }
                // The table also feeds coerceFlag a list and an object, which the
                // app-config schema does not allow for EVENTS_ENABLED.
                guard input is [Any] || input is [String: Any] else { return try AppConfigFactory.remote(["EVENTS_ENABLED": input]) }
                return try Factory.offSchema(because: "EVENTS_ENABLED must be a flag; the coerceFlag table also tries a list and an object") {
                    try AppConfigFactory.remote(["EVENTS_ENABLED": input])
                }
            }
            XCTAssertEqual(SellwildEvents.isEnabled(remoteValues: values), row["expected"] as? Bool, "\(row["input"] ?? "nil")")
        }
        XCTAssertFalse(SellwildEvents.isEnabled(remoteValues: try AppConfigFactory.remote(["EVENTS_ENABLED": " off\n"])))
        XCTAssertTrue(SellwildEvents.isEnabled(remoteValues: try AppConfigFactory.remote(["EVENTS_ENABLED": "\u{00A0}off"])))
    }

    func testSessionUidIsCreatedOnceAndStored() {
        let key = "_sw_uid"
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        let fresh = SellwildSession().uid
        XCTAssertNotNil(UUID(uuidString: fresh))
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), fresh)
        XCTAssertEqual(SellwildSession().uid, fresh, "a stored uid is reused")
    }

    func testErrorDescriptions() {
        XCTAssertEqual(SellwildError.invalidURL("x").errorDescription, "Invalid URL: x")
        XCTAssertEqual(SellwildError.noData.errorDescription, "No data received from server")
        XCTAssertEqual(SellwildError.invalidResponse.errorDescription, "Invalid response format")
    }
}
