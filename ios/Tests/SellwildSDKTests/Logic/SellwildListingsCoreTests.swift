import XCTest
@testable import SellwildSDK

/// The pure listings request builder and parser. Bodies come from the
/// listings factories and the real samples.
final class SellwildListingsCoreTests: XCTestCase {

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testStaticCacheIsAGet() throws {
        let request = try SellwildListingsCore.request(url: try url("https://cache.sellwild.com/listings-sm"),
                                                       partnerCode: "p", encode: { _ in throw PlannedError() })
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.httpBody, "the encoder is not called for a GET")
    }

    func testOtherHostsAreTheJSONRPCPost() throws {
        var seen: [String: Any]?
        let request = try SellwildListingsCore.request(url: try url("https://api.sellwild.invalid/rpc"), partnerCode: "weatherbug") {
            seen = $0
            return Data("{}".utf8)
        }
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
        XCTAssertEqual(seen?["method"] as? String, "getFeaturedListingsForPartnerWidget")
        XCTAssertEqual(seen?["params"] as? [String], ["weatherbug", "regular"])
        XCTAssertEqual(seen?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(seen?["id"] as? Int, 1)

        XCTAssertThrowsError(try SellwildListingsCore.request(url: try url("https://api.sellwild.invalid/rpc"),
                                                              partnerCode: "p", encode: { _ in throw PlannedError() }))
        XCTAssertFalse(SellwildListingsCore.isStaticCache(try url("stub:listings")), "no host")
    }

    func testCacheKeyIsURLAndPartner() throws {
        let u = try url("https://cache.sellwild.com/a")
        XCTAssertEqual(SellwildListingsCore.cacheKey(url: u, partnerCode: "p"), "https://cache.sellwild.com/a|p")
        XCTAssertNotEqual(SellwildListingsCore.cacheKey(url: u, partnerCode: "p"), SellwildListingsCore.cacheKey(url: u, partnerCode: "q"))
    }

    func testParseTheRealCacheAndTheRPCEnvelope() throws {
        let cache = try SellwildListingsCore.parse(ListingsResponseFactory.data(result: ["config": ["browse": 0]])).get()
        XCTAssertEqual(cache.response.listings.count, 10)
        XCTAssertEqual(cache.response.config["browse"] as? Int, 0)
        XCTAssertNil(cache.rsProblem)
        XCTAssertEqual(cache.dropped, 0)
        XCTAssertNil(cache.firstDropError)

        let rpc = try SellwildListingsCore.parse(Factory.data(ListingsResponseFactory.variant("rpc-envelope"))).get()
        XCTAssertEqual(rpc.response.listings.map(\.id), ["5550001"])
        XCTAssertEqual(rpc.response.widgetCacheVersionId, "12")

        let bare = try SellwildListingsCore.parse(Factory.data(["rs": [try ListingFactory.make()]])).get()
        XCTAssertEqual(bare.response.listings.count, 1, "a bare { rs } root is accepted")
        XCTAssertTrue(bare.response.config.isEmpty)
    }

    func testParseFailuresAndProblems() throws {
        guard case .failure(.notJSON(let error)) = SellwildListingsCore.parse(Data("<xml/>".utf8)) else {
            return XCTFail("not JSON")
        }
        XCTAssertEqual((error as NSError).code, 3840)
        guard case .failure(.notAnObject) = SellwildListingsCore.parse(try Factory.data([try ListingFactory.make()])) else {
            return XCTFail("not an object")
        }

        let missing = try SellwildListingsCore.parse(
            Factory.offSchema(because: "result.rs is required") { try ListingsResponseFactory.data(result: ["rs": Factory.remove]) }).get()
        XCTAssertEqual(missing.rsProblem, "result.rs is missing")
        XCTAssertTrue(missing.response.listings.isEmpty)
        let wrong = try SellwildListingsCore.parse(
            Factory.offSchema(because: "result.rs must hold objects") { try ListingsResponseFactory.data(result: ["rs": [1, 2]]) }).get()
        XCTAssertEqual(wrong.rsProblem, "result.rs is not a list of objects")

        let body = try Factory.offSchema(because: "a title and a user.id must be text: the two items the SDK drops") {
            let first = try ListingFactory.make(["id": "a", "title": 1])
            let second = try ListingFactory.make(["id": "b", "user": ["id": 7]])
            return try ListingsResponseFactory.data(listings: [first, try ListingFactory.make(), second])
        }
        let mixed = try SellwildListingsCore.parse(body).get()
        XCTAssertEqual(mixed.response.listings.map(\.id), ["105140231"])
        XCTAssertEqual(mixed.dropped, 2)
        guard case .typeMismatch(_, let context)? = mixed.firstDropError as? DecodingError else {
            return XCTFail("the first drop's error is kept")
        }
        XCTAssertEqual(context.codingPath.map(\.stringValue), ["title"])
    }

    func testEmptyResponse() {
        XCTAssertTrue(SellwildListingsCore.empty.listings.isEmpty)
        XCTAssertTrue(SellwildListingsCore.empty.config.isEmpty)
        XCTAssertNil(SellwildListingsCore.empty.widgetCacheVersionId)
    }
}
