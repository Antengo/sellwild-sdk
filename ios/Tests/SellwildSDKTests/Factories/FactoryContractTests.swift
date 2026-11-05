import XCTest
@testable import SellwildSDK

/// Every factory's default, every variant and every real sample it wraps is
/// written to `contracts/out/ios/<schema>.<variant>.json`;
/// `scripts/coverage/ios.sh` then runs `node contracts/scripts/validate.mjs
/// --out ios` over them. The assertions here check what each factory does
/// with its base and overrides.
final class FactoryContractTests: XCTestCase {

    @discardableResult
    private func emit(_ object: Any, _ schema: String, _ variant: String) throws -> URL {
        try ContractEmitter.emit(object, schema: schema, variant: variant)
    }

    private func emitAll(_ schema: String, fixtures: [String], samples: [String] = [],
                         fixture: (String) throws -> Any, sample: (String) throws -> Any = { _ in [:] }) throws {
        XCTAssertFalse(fixtures.isEmpty, schema)
        for name in fixtures { try emit(try fixture(name), schema, "fixture-\(Factory.variantName(name))") }
        for name in samples { try emit(try sample(name), schema, "sample-\(Factory.variantName(name))") }
    }

    // MARK: Shared plumbing

    func testMarkersAreStrippedAndOverridesApply() throws {
        let raw = try Fixtures.dict("fixtures/app-config/valid/minimal.json")
        XCTAssertEqual(raw["_synthetic"] as? Bool, true)
        let config = try Factory.offSchema(because: "removes the required SLUG to show Factory.remove works") {
            try AppConfigFactory.variant("minimal", ["NAME": "renamed", "SLUG": Factory.remove, "EXTRA": NSNull()])
        }
        XCTAssertNil(config["_synthetic"])
        XCTAssertEqual(config["NAME"] as? String, "renamed")
        XCTAssertNil(config["SLUG"])
        XCTAssertTrue(config["EXTRA"] is NSNull, "NSNull stays a JSON null")
        XCTAssertEqual(Factory.variantName("a.local-build"), "a-local-build")
    }

    func testFactoriesRejectFilesOfTheWrongShape() {
        XCTAssertThrowsError(try Factory.object("fixtures/eid-blob/valid/full.json")) { error in
            XCTAssertEqual(error as? Factory.Failure, .notAnObject("fixtures/eid-blob/valid/full.json"))
        }
        XCTAssertThrowsError(try Factory.array("fixtures/listing/valid/rpc-item.json")) { error in
            XCTAssertEqual(error as? Factory.Failure, .notAnArray("fixtures/listing/valid/rpc-item.json"))
        }
        XCTAssertTrue("\(Factory.Failure.emptyArray("x"))".contains("empty"))
        XCTAssertTrue("\(Factory.Failure.dropped("sampled_out"))".contains("sampled_out"))
        XCTAssertTrue("\(Factory.Failure.notAnObject("x"))".contains("object"))
        XCTAssertTrue("\(Factory.Failure.notAnArray("x"))".contains("array"))
    }

    // MARK: Each factory

    func testAppConfigFactory() throws {
        let config = try AppConfigFactory.make(["FAILURES_ENABLED": false, "FAILURES_SAMPLE_RATE": "0.25"])
        XCTAssertEqual(config["CODE"] as? String, "weatherbug", "the default is the real weatherbug config")
        XCTAssertEqual(config["FAILURES_ENABLED"] as? Bool, false)
        try emit(AppConfigFactory.make(), AppConfigFactory.schema, "default")
        try emit(config, AppConfigFactory.schema, "override-failure-flags")
        try emitAll(AppConfigFactory.schema, fixtures: AppConfigFactory.variantNames(), samples: AppConfigFactory.sampleNames(),
                    fixture: { try AppConfigFactory.variant($0) }, sample: { try AppConfigFactory.sample($0) })

        let missing = String(decoding: try AppConfigFactory.missingBody(), as: UTF8.self)
        XCTAssertTrue(missing.contains("AccessDenied"), "a missing config is a 403 XML body")
    }

    func testListingFactory() throws {
        let listing = try ListingFactory.make(["title": "Road bike", "price": 250])
        let decoded = try ListingFactory.decoded(listing)
        XCTAssertEqual(decoded.id, "105140231")
        XCTAssertEqual(decoded.title, "Road bike")
        XCTAssertEqual(decoded.price, "250", "numeric prices decode as text")
        XCTAssertEqual(try ListingFactory.decoded(ListingFactory.variant("rpc-item")).user?.username, "sam")
        try emit(ListingFactory.make(), ListingFactory.schema, "default")
        try emit(listing, ListingFactory.schema, "override-title-price")
        try emitAll(ListingFactory.schema, fixtures: ListingFactory.variantNames(), fixture: { try ListingFactory.variant($0) })
    }

    func testListingsResponseFactory() throws {
        let item = try ListingFactory.make(["id": "1"])
        let response = try ListingsResponseFactory.make(listings: [item], result: ["widgetCacheVersionId": "v9"])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual((result["rs"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(result["widgetCacheVersionId"] as? String, "v9")
        let real = try XCTUnwrap(try ListingsResponseFactory.make()["result"] as? [String: Any])
        XCTAssertFalse((real["rs"] as? [Any] ?? []).isEmpty, "the default is the real cache payload")
        let empty = try JSONSerialization.jsonObject(with: ListingsResponseFactory.data(listings: [])) as? [String: Any]
        XCTAssertEqual(((empty?["result"] as? [String: Any])?["rs"] as? [Any])?.count, 0)
        try emit(ListingsResponseFactory.make(), ListingsResponseFactory.schema, "default")
        try emit(response, ListingsResponseFactory.schema, "override-one-listing")
        try emit(ListingsResponseFactory.variant("rpc-envelope", listings: [item]), ListingsResponseFactory.schema, "override-rpc-one-listing")
        try emitAll(ListingsResponseFactory.schema, fixtures: ListingsResponseFactory.variantNames(),
                    samples: ListingsResponseFactory.sampleNames(),
                    fixture: { try ListingsResponseFactory.variant($0) }, sample: { try ListingsResponseFactory.sample($0) })
    }

    func testLocalizedListingsFactory() throws {
        let config = try LocalizedListingsFactory.config(["forceState": "TX"])
        XCTAssertEqual(config["forceState"] as? String, "TX")
        XCTAssertEqual(config["urlTemplate"] as? String, "sports-img-data-sm-webp-{state}.json")
        let response = try LocalizedListingsFactory.response(state: "TX", listings: [ListingFactory.make()])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["state"] as? String, "TX")
        XCTAssertEqual((result["rs"] as? [Any])?.count, 1)

        try emit(LocalizedListingsFactory.config(), LocalizedListingsFactory.configSchema, "default")
        try emit(config, LocalizedListingsFactory.configSchema, "override-force-state")
        try emitAll(LocalizedListingsFactory.configSchema, fixtures: LocalizedListingsFactory.configVariantNames(),
                    fixture: { try LocalizedListingsFactory.configVariant($0) })
        try emit(LocalizedListingsFactory.response(), LocalizedListingsFactory.responseSchema, "default")
        try emit(response, LocalizedListingsFactory.responseSchema, "override-state-listing")
        try emit(LocalizedListingsFactory.responseVariant("minimal", state: "AL"), LocalizedListingsFactory.responseSchema, "override-minimal-al")
        try emitAll(LocalizedListingsFactory.responseSchema, fixtures: LocalizedListingsFactory.responseVariantNames(),
                    samples: LocalizedListingsFactory.responseSampleNames(),
                    fixture: { try LocalizedListingsFactory.responseVariant($0) },
                    sample: { try LocalizedListingsFactory.responseSample($0) })
    }

    func testGrowthCodeAndEidFactories() throws {
        let eids = try EidBlobFactory.single(source: "uidapi.com", id: "uid2-x", atype: 3)
        XCTAssertEqual(eids.count, 1)
        XCTAssertEqual((eids[0]["uids"] as? [[String: Any]])?.first?["atype"] as? Int, 3)
        XCTAssertNil(try EidBlobFactory.single(source: "id5-sync.com", id: "x")[0]["uids"].flatMap { ($0 as? [[String: Any]])?.first?["atype"] })

        let sync = try GrowthCodeFactory.syncResponse(eids: eids, ["gc_id": "gc-1"])
        XCTAssertEqual(sync["gc_id"] as? String, "gc-1")
        let eb = try XCTUnwrap((sync["eb"] as? String)?.data(using: .utf8))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: eb) as? [[String: Any]])?.first?["source"] as? String, "uidapi.com",
                       "eb is the EID array as JSON text")

        try emit(EidBlobFactory.make(), EidBlobFactory.schema, "default")
        try emit(EidBlobFactory.make(["matcher": "sellwild.com"]), EidBlobFactory.schema, "override-matcher")
        try emit(eids, EidBlobFactory.schema, "single-uid2")
        try emitAll(EidBlobFactory.schema, fixtures: EidBlobFactory.variantNames(), fixture: { try EidBlobFactory.variant($0) })
        try emit(GrowthCodeFactory.syncResponse(), GrowthCodeFactory.schema, "default")
        try emit(sync, GrowthCodeFactory.schema, "override-eids")
        try emitAll(GrowthCodeFactory.schema, fixtures: GrowthCodeFactory.variantNames(), fixture: { try GrowthCodeFactory.variant($0) })
    }

    func testEventFactory() throws {
        let event = try EventFactory.event(["label": "280"])
        XCTAssertEqual(event["event"] as? String, "adError")
        XCTAssertEqual(event["label"] as? String, "280")
        XCTAssertEqual(try EventFactory.batch().count, 1)
        try emit(EventFactory.batch(), EventFactory.schema, "default")
        try emit(EventFactory.batch([event, EventFactory.event(["event": "click"])]), EventFactory.schema, "override-two-events")
        try emitAll(EventFactory.schema, fixtures: EventFactory.variantNames(), fixture: { try EventFactory.batchVariant($0) })
    }

    func testClientFailureEventFactory() throws {
        let event = try ClientFailureEventFactory.make(attributes: ["zoneId": "280"])
        XCTAssertEqual((event["attributes"] as? [String: Any])?["zoneId"] as? String, "280")
        try emit(ClientFailureEventFactory.make(), ClientFailureEventFactory.schema, "default")
        try emit(event, ClientFailureEventFactory.schema, "override-zone")
        try emitAll(ClientFailureEventFactory.schema, fixtures: ClientFailureEventFactory.variantNames(),
                    fixture: { try ClientFailureEventFactory.variant($0) })

        // Built by the iOS pure core itself.
        let fromCore = try ClientFailureEventFactory.fromCore(.init(
            code: SellwildFailureCode.configFetchHttp.rawValue, component: "remoteConfig", severity: "warn",
            errName: "NSURLErrorDomain(-1011)", errMessage: "bad status", message: "HTTP 403",
            httpStatus: 403, url: "https://widget.sellwild.com/app/weatherbug/weatherbug-main.json", zoneId: nil
        ), wrapper: "react-native")
        let attributes = try XCTUnwrap(fromCore["attributes"] as? [String: String])
        XCTAssertEqual(attributes["client"], "ios")
        XCTAssertEqual(attributes["wrapper"], "react-native")
        XCTAssertEqual(attributes["host"], "widget.sellwild.com")
        XCTAssertEqual(attributes["msg"], "HTTP 403: bad status")
        try emit(fromCore, ClientFailureEventFactory.schema, "ios-core-config-http")
        let invalid = try ClientFailureEventFactory.fromCore(.init(code: "Not A Code", component: "nope", message: String(repeating: "x", count: 300)))
        XCTAssertEqual(invalid["action"] as? String, "client.code.invalid")
        try emit(invalid, ClientFailureEventFactory.schema, "ios-core-invalid-code-long-msg")

    }

    /// The real wire form: a clientFailure pushed through SellwildAPIClient
    /// (queue stamping included) next to an ordinary event.
    func testClientFailureWireBatchFromTheQueue() throws {
        let transport = CapturingEventTransport()
        let client = SellwildAPIClient(session: StubURLProtocol.makeSession(), eventTransport: transport.transport,
                                       eventClock: ManualEventClock().clock)
        client.partnerCode = "weatherbug"
        let decision = SellwildFailuresCore.decide(
            state: .init(),
            input: .init(code: "listings.fetch.http", component: "listings", message: "HTTP 503", httpStatus: 503,
                         url: "https://cache.sellwild.com/listings-img-data-sm", zoneId: "43"),
            context: .init(partnerCode: "weatherbug", client: "ios", clientVersion: SellwildSDK.sdkVersion),
            uid: FailureCapture.uid, now: FailureCapture.now
        )
        client.sendEvent(SellwildEvent(failure: try XCTUnwrap(decision.event)))
        client.sendEvent(SellwildEvent(event: "adError", action: "No ad to show.", label: "43"))
        client.flushEvents()
        client.waitForEventQueue()

        let body = try XCTUnwrap(transport.requests.last?.httpBody)
        let failure = try XCTUnwrap(transport.batches.first?.first)
        XCTAssertEqual(failure["event"] as? String, "clientFailure")
        XCTAssertEqual(failure["uid"] as? String, FailureCapture.uid)
        XCTAssertEqual((failure["createdTime"] as? NSNumber)?.int64Value, FailureCapture.now)
        let attributes = try XCTUnwrap(failure["attributes"] as? [String: String])
        XCTAssertEqual(attributes["type"], "ios")
        XCTAssertEqual(attributes["client"], "ios")
        XCTAssertEqual(attributes["code"], "weatherbug")
        try ContractEmitter.emit(jsonData: try XCTUnwrap(transport.requests.first?.httpBody),
                                 schema: "events-batch", variant: "ios-queue-client-failure")
        try ContractEmitter.emit(jsonData: body, schema: "events-batch", variant: "ios-queue-ad-error")
    }
}
