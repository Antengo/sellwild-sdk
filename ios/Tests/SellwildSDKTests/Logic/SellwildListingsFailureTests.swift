import XCTest
@testable import SellwildSDK

/// Every failure site of `SellwildAPIClient.fetchListings` and
/// `fetchCacheListings` reports its registry code exactly once, and still
/// hands the caller the same result as before. Payloads come from the
/// factories; requests go to `StubURLProtocol`.
final class SellwildListingsFailureTests: FailureCapturingTestCase {

    private var session: URLSession!
    private var client: SellwildAPIClient!
    private let cacheURL = "https://cache.sellwild.com/listings-img-data-sm"
    private let localURL = URL(string: "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/sports-img-data-sm-webp-ga.json")!

    override func setUp() {
        super.setUp()
        session = StubURLProtocol.makeSession()
        client = SellwildAPIClient(session: session)
    }

    override func tearDown() {
        session.finishTasksAndInvalidate()
        client = nil
        SellwildGeoStore.current = nil
        super.tearDown()
    }

    private func config(_ url: String? = nil) -> SellwildConfig {
        SellwildConfig(partnerCode: "weatherbug", listingsUrl: url ?? cacheURL)
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
        return result ?? .failure(PlannedError())
    }

    private func fetchCache(on client: SellwildAPIClient? = nil) -> Result<[SellwildListing], Error> {
        let done = expectation(description: "fetchCacheListings")
        var result: Result<[SellwildListing], Error>?
        (client ?? self.client).fetchCacheListings(url: localURL) {
            XCTAssertTrue(Thread.isMainThread)
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result ?? .failure(PlannedError())
    }

    private func respond(_ object: Any, status: Int = 200) {
        StubURLProtocol.handler = { _ in try .json(object, status: status) }
    }

    /// Answers with no body and no error, which URLSession never does.
    private func answerWithoutBody(status: Int = 200) {
        client.load = { request, completion in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)
            completion(nil, response, nil)
        }
    }

    // MARK: fetchListings

    func testCleanFetchReportsNothing() throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: try ListingsResponseFactory.data()) }
        XCTAssertFalse(try fetch(config()).get().listings.isEmpty)
        capture.none()
    }

    func testInvalidListingsURL() throws {
        XCTAssertThrowsError(try fetch(config("http://exa mple.invalid/")).get()) { error in
            XCTAssertEqual(error.localizedDescription, "Invalid URL: http://exa mple.invalid/")
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        let event = capture.only(.listingsUrlInvalid, label: .listings)
        XCTAssertEqual(event?.attributes["msg"], "listings URL is not a valid URL")
        XCTAssertEqual(event?.attributes["severity"], "error")
    }

    func testRequestThatCannotBeEncoded() throws {
        client.encodeListingsEnvelope = { _ in throw PlannedError() }
        XCTAssertThrowsError(try fetch(config("https://api.sellwild.invalid/supplyListing/rpc")).get()) { error in
            XCTAssertEqual(error as? PlannedError, PlannedError())
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        let event = capture.only(.listingsRequestException, label: .listings)
        XCTAssertEqual(event?.attributes["errName"], "PlannedError")
        XCTAssertEqual(event?.attributes["host"], "api.sellwild.invalid")
    }

    func testTimeout() throws {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        XCTAssertThrowsError(try fetch(config()).get()) { XCTAssertEqual(($0 as? URLError)?.code, .timedOut) }
        let event = capture.only(.listingsFetchTimeout, label: .listings)
        XCTAssertEqual(event?.attributes["errName"], "NSURLErrorDomain(-1001)")
        XCTAssertEqual(event?.attributes["host"], "cache.sellwild.com")
    }

    func testNetworkError() throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertThrowsError(try fetch(config()).get())
        XCTAssertEqual(capture.only(.listingsFetchNetwork, label: .listings)?.attributes["errName"], "NSURLErrorDomain(-1009)")
    }

    func testCancelledIsNotAFailure() throws {
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        let lines = try debugLines {
            XCTAssertThrowsError(try fetch(config()).get()) { XCTAssertEqual(($0 as? URLError)?.code, .cancelled) }
        }
        capture.none()
        XCTAssertEqual(lines, ["[SellwildAPIClient] listings fetch cancelled"])
    }

    func testResponseWithoutABody() throws {
        answerWithoutBody()
        XCTAssertThrowsError(try fetch(config()).get()) {
            XCTAssertEqual($0.localizedDescription, SellwildError.noData.localizedDescription)
        }
        capture.only(.listingsFetchMissing, label: .listings)
    }

    func testHTTPErrorStatus() throws {
        let body = try AppConfigFactory.missingBody()
        StubURLProtocol.handler = { _ in .init(status: 403, headers: ["Content-Type": "application/xml"], body: body) }
        XCTAssertThrowsError(try fetch(config()).get()) {
            XCTAssertEqual($0.localizedDescription, SellwildError.invalidResponse.localizedDescription)
        }
        let event = capture.only(.listingsFetchHttp, label: .listings)
        XCTAssertEqual(event?.attributes["httpStatus"], "403")
        XCTAssertEqual(event?.attributes["msg"], "HTTP 403")
    }

    func testBodyThatIsNotJSON() throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("<html>oops</html>".utf8)) }
        XCTAssertThrowsError(try fetch(config()).get()) { XCTAssertEqual(($0 as NSError).code, 3840) }
        XCTAssertEqual(capture.only(.listingsFetchParse, label: .listings)?.attributes["errName"], "NSCocoaErrorDomain(3840)")
    }

    func testJSONThatIsNotAnObject() throws {
        respond([try ListingFactory.make()])
        XCTAssertThrowsError(try fetch(config()).get()) {
            XCTAssertEqual($0.localizedDescription, SellwildError.invalidResponse.localizedDescription)
        }
        XCTAssertEqual(capture.only(.listingsParseInvalid, label: .listings)?.attributes["msg"], "listings JSON is not an object")
    }

    func testMissingListingsListIsReportedAndStillAnEmptySuccess() throws {
        respond(try Factory.offSchema(because: "result.rs is required") { try ListingsResponseFactory.make(result: ["rs": Factory.remove]) })
        XCTAssertEqual(try fetch(config()).get().listings.count, 0)
        XCTAssertEqual(capture.only(.listingsParseInvalid, label: .listings)?.attributes["msg"], "result.rs is missing")

        // Cached as before: the same URL is not asked again.
        XCTAssertEqual(try fetch(config()).get().listings.count, 0)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testListingsThatAreNotAList() throws {
        respond(try Factory.offSchema(because: "result.rs must be a list") { try ListingsResponseFactory.make(result: ["rs": "none"]) })
        XCTAssertEqual(try fetch(config()).get().listings.count, 0)
        XCTAssertEqual(capture.only(.listingsParseInvalid, label: .listings)?.attributes["msg"], "result.rs is not a list of objects")
    }

    func testUndecodableItemsAreDroppedAndReportedOncePerBody() throws {
        let good = try ListingFactory.make()
        let body = try Factory.offSchema(because: "user.id must be text and a photo needs a url: the two items the SDK drops") {
            let bad = try ListingFactory.variant("rpc-item", ["user": ["id": 1234]])
            let photoWithoutURL = try ListingFactory.make(["id": "2", "photos": [["thumbUrl": "https://x.invalid/t.jpg"]]])
            return try ListingsResponseFactory.make(listings: [good, bad, photoWithoutURL])
        }
        respond(body)

        XCTAssertEqual(try fetch(config()).get().listings.map(\.id), ["105140231"])
        let event = capture.only(.listingsItemParse, label: .listings)
        XCTAssertEqual(event?.attributes["msg"]?.hasPrefix("2 listing(s) could not be decoded and were dropped: "), true)
        XCTAssertEqual(event?.attributes["errName"], "DecodingError")
        XCTAssertEqual(event?.attributes["severity"], "error")
    }

    func testClientReleasedMidRequestDeliversAnEmptyFeed() throws {
        let gate = DispatchSemaphore(value: 0)
        StubURLProtocol.handler = { _ in
            gate.wait()
            return .init(status: 200, body: try ListingsResponseFactory.data())
        }
        var owner: SellwildAPIClient? = SellwildAPIClient(session: session)
        let done = expectation(description: "completion")
        var result: Result<SellwildListingsResponse, Error>?
        owner?.fetchListings(config: config()) { result = $0; done.fulfill() }
        owner = nil
        gate.signal()
        wait(for: [done], timeout: 10)

        XCTAssertEqual(try XCTUnwrap(result).get().listings.count, 0)
        let event = capture.only(.listingsClientMissing, label: .listings)
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    func testDefaultEnvelopeEncoderWritesTheRPCBody() throws {
        let body = try client.encodeListingsEnvelope(SellwildListingsCore.rpcEnvelope(partnerCode: "p"))
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(envelope["params"] as? [String], ["p", "regular"])
    }

    // MARK: fetchCacheListings (localized)

    func testLocalizedCleanFetchReportsNothing() throws {
        respond(try LocalizedListingsFactory.response())
        XCTAssertFalse(try fetchCache().get().isEmpty)
        capture.none()
    }

    func testLocalizedMissingStateCacheIsASkipNotAFailure() throws {
        let body = try Fixtures.data("samples/localized-listings-response/sports-img-data-sm-webp-zz.403.xml")
        for status in [403, 404] {
            StubURLProtocol.handler = { _ in .init(status: status, headers: ["Content-Type": "application/xml"], body: body) }
            let lines = try debugLines {
                XCTAssertThrowsError(try fetchCache().get()) {
                    XCTAssertEqual($0.localizedDescription, SellwildError.invalidResponse.localizedDescription)
                }
            }
            XCTAssertEqual(lines, ["[SellwildAPIClient] no localized cache for this state (HTTP \(status))"])
        }
        capture.none()
    }

    func testLocalizedHTTPErrorStatus() throws {
        StubURLProtocol.handler = { _ in .init(status: 500) }
        XCTAssertThrowsError(try fetchCache().get())
        let event = capture.only(.localizedFetchHttp, label: .localized)
        XCTAssertEqual(event?.attributes["httpStatus"], "500")
        XCTAssertEqual(event?.attributes["host"], "sellwild-sports-cache.s3.us-east-1.amazonaws.com")
    }

    func testLocalizedTransportErrors() throws {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        XCTAssertThrowsError(try fetchCache().get())
        capture.only(.localizedFetchTimeout, label: .localized)

        resetCapture()
        StubURLProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        XCTAssertThrowsError(try fetchCache().get()) { XCTAssertEqual(($0 as? URLError)?.code, .networkConnectionLost) }
        capture.only(.localizedFetchNetwork, label: .localized)

        resetCapture()
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        XCTAssertThrowsError(try fetchCache().get())
        capture.none()
    }

    func testLocalizedResponseWithoutABody() throws {
        answerWithoutBody()
        XCTAssertThrowsError(try fetchCache().get()) {
            XCTAssertEqual($0.localizedDescription, SellwildError.noData.localizedDescription)
        }
        capture.only(.localizedFetchMissing, label: .localized)
    }

    func testLocalizedBodyThatIsNotJSON() throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("not json".utf8)) }
        XCTAssertThrowsError(try fetchCache().get())
        capture.only(.localizedFetchParse, label: .localized)
    }

    func testLocalizedJSONThatIsNotAnObject() throws {
        respond([try ListingFactory.make()])
        XCTAssertThrowsError(try fetchCache().get()) {
            XCTAssertEqual($0.localizedDescription, SellwildError.invalidResponse.localizedDescription)
        }
        XCTAssertEqual(capture.only(.listingsParseInvalid, label: .localized)?.attributes["msg"], "localized cache JSON is not an object")
    }

    func testLocalizedMissingListAndDroppedItems() throws {
        respond(try Factory.offSchema(because: "a listing title must be text: the item the SDK drops") {
            try LocalizedListingsFactory.responseVariant("minimal", listings: [try ListingFactory.make(), try ListingFactory.make(["id": "9", "title": 5])])
        })
        XCTAssertEqual(try fetchCache().get().count, 1)
        capture.only(.listingsItemParse, label: .localized)

        resetCapture()
        respond(try Factory.offSchema(because: "result.rs is required") { try LocalizedListingsFactory.response(result: ["rs": Factory.remove]) })
        XCTAssertEqual(try fetchCache().get().count, 0)
        XCTAssertEqual(capture.only(.listingsParseInvalid, label: .localized)?.attributes["msg"], "result.rs is missing")
    }

    func testLocalizedClientReleasedMidRequest() throws {
        let gate = DispatchSemaphore(value: 0)
        let body = try Factory.data(LocalizedListingsFactory.response())
        StubURLProtocol.handler = { _ in
            gate.wait()
            return .init(status: 200, body: body)
        }
        var owner: SellwildAPIClient? = SellwildAPIClient(session: session)
        let done = expectation(description: "completion")
        var listings: [SellwildListing]?
        owner?.fetchCacheListings(url: localURL) { listings = try? $0.get(); done.fulfill() }
        owner = nil
        gate.signal()
        wait(for: [done], timeout: 10)

        XCTAssertEqual(listings?.count, 0)
        let event = capture.only(.listingsClientMissing, label: .localized)
        XCTAssertEqual(event?.attributes["severity"], "warn")
        XCTAssertEqual(event?.attributes["msg"], "listings client released while a request was in flight")
        XCTAssertEqual(event?.attributes["host"], "sellwild-sports-cache.s3.us-east-1.amazonaws.com")
    }

    func testMissingStateCacheStatuses() {
        XCTAssertTrue(SellwildAPIClient.isMissingStateCache(status: 403))
        XCTAssertTrue(SellwildAPIClient.isMissingStateCache(status: 404))
        XCTAssertFalse(SellwildAPIClient.isMissingStateCache(status: 410))
        XCTAssertFalse(SellwildAPIClient.isMissingStateCache(status: 500))
    }
}
