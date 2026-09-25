import XCTest
@testable import SellwildSDK

/// contracts/README.md "Conformance" for iOS: every app-config and listings
/// input (real samples and valid fixtures) goes through the real iOS path
/// (`SellwildSDK.configure` with a stub session, `SellwildAPIClient.fetchListings`)
/// and must give the expected typed result for each field this test holds
/// iOS to. A field named in the case's entry in
/// contracts/expectations/drift/ios.json must differ instead (FAILURES.md
/// 14.2): the entry is removed in the change that fixes the drift.
final class SellwildConformanceTests: FailureCapturingTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        session = StubURLProtocol.makeSession()
    }

    override func tearDown() {
        session.finishTasksAndInvalidate()
        super.tearDown()
    }

    // MARK: Expectation files

    private struct Case {
        let file: String
        let expected: [String: Any]
    }

    private struct ExpectationFile {
        let zones: [String]
        let iosFields: [String]
        let cases: [Case]
    }

    private func expectations(_ name: String) throws -> ExpectationFile {
        let doc = try Fixtures.dict("expectations/\(name).expected.json")
        let fields = try XCTUnwrap(doc["fields"] as? [String: [String: Any]])
        let cases = try XCTUnwrap(doc["cases"] as? [[String: Any]]).map { entry in
            Case(file: try XCTUnwrap(entry["file"] as? String), expected: try XCTUnwrap(entry["expected"] as? [String: Any]))
        }
        return ExpectationFile(
            zones: doc["zones"] as? [String] ?? [],
            iosFields: fields.filter { ($0.value["platforms"] as? [String] ?? []).contains("ios") }.map(\.key).sorted(),
            cases: cases
        )
    }

    /// iOS drift text per case of one expectations file.
    private func drift(_ name: String) throws -> [String: String] {
        let doc = try Fixtures.dict("expectations/drift/ios.json")
        XCTAssertEqual(doc["platform"] as? String, "ios")
        let expectations = try XCTUnwrap(doc["expectations"] as? [String: [String: String]])
        return try XCTUnwrap(expectations[name])
    }

    /// Fields a drift text names: "field:" anywhere, or the text starts with
    /// it (the rule of contracts/test/expectations.test.mjs and core).
    static func namedFields(_ text: String?, among fields: [String]) -> [String] {
        guard let text else { return [] }
        return fields.filter { text.contains("\($0):") || text.hasPrefix($0) }
    }

    /// `value`, or JSON null.
    static func orNull(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    /// One JSON text for any JSON-able value, keys sorted, so numbers, nulls
    /// and nesting compare the way JSON does.
    static func canonical(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["v": value], options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func check(_ file: String, field: String, actual: Any, expected: Any, drifting: Bool,
                       line: UInt = #line) {
        let a = Self.canonical(actual)
        let e = Self.canonical(expected)
        XCTAssertFalse(a == "", "\(file) \(field): actual is not JSON", line: line)
        if drifting {
            XCTAssertNotEqual(a, e, "\(file) \(field) is listed as known drift in drift/ios.json, so it must differ; remove the entry", line: line)
        } else {
            XCTAssertEqual(a, e, "\(file) \(field)", line: line)
        }
    }

    // MARK: Drift rule

    func testDriftRuleNamesFieldsLikeTheContractsTest() {
        let fields = ["iabCats", "publisherId", "houseAd"]
        XCTAssertEqual(Self.namedFields("iabCats: returns []. publisherId: keeps ''", among: fields), ["iabCats", "publisherId"])
        XCTAssertEqual(Self.namedFields("houseAd differs", among: fields), ["houseAd"])
        XCTAssertEqual(Self.namedFields(nil, among: fields), [])
        XCTAssertEqual(Self.canonical(["b": 1, "a": NSNull()]), Self.canonical(["a": NSNull(), "b": 1.0]))
        XCTAssertNotEqual(Self.canonical(["a": true]), Self.canonical(["a": "true"]))
    }

    // MARK: app-config

    /// Fields held elsewhere: `publisherId` is resolved inside
    /// SellwildPrebidMobile and `auctionBidderParams` inside SellwildAdView,
    /// neither of which exposes a pure function to this test yet.
    static let appConfigFieldsHeldElsewhere = ["auctionBidderParams", "publisherId"]

    private func configure(_ body: Data, events: SellwildAPIClient) async -> SellwildConfig {
        StubURLProtocol.handler = { _ in .init(status: 200, body: body) }
        let environment = SellwildSDK.ConfigureEnvironment(
            session: session, makeURL: { URL(string: $0) }, events: events, bootstrap: { _ in true }
        )
        return await SellwildSDK.configure(partnerCode: "conformance", slug: "conformance", timeout: 3,
                                           overrides: nil, environment: environment)
    }

    /// The expectation fields from what iOS resolved.
    private func appConfigResult(_ config: SellwildConfig, raw: [String: Any], events: SellwildAPIClient,
                                 zones: [String]) throws -> [String: Any] {
        let remote = try XCTUnwrap(config.remoteValues)
        var probe = SellwildConfig(partnerCode: "probe")
        probe.adRefreshInterval = -1
        let refresh = SellwildSDK.apply(raw, to: probe).adRefreshInterval

        let byZone = (remote["AD_STACK_BY_ZONE"] as? [String: Any] ?? [:])
            .compactMapValues { SellwildAdStack.parse($0)?.rawValue }
        var resolvedStack: [String: Any] = [:]
        var bannerSizes: [String: Any] = [:]
        for zone in zones {
            resolvedStack[zone] = SellwildAdStack.resolve(remoteValues: remote, zoneId: zone).rawValue
            bannerSizes[zone] = SellwildAdSizes.resolve(remoteValues: remote, zoneId: zone, primary: CGSize(width: 1, height: 1))
                .dropFirst().map { [Int($0.width), Int($0.height)] }
        }

        let houseZone = "43"
        let houseSize = CGSize(width: 300, height: 250)
        let candidates = SellwildHouseAd.candidates(remoteValues: remote, zoneId: houseZone, size: houseSize)

        var localized: Any = NSNull()
        if let integration = SellwildLocalizedListings.resolve(config: config) {
            let state = integration.forceState ?? "AL"
            localized = [
                "source": Self.orNull(integration.source),
                "baseUrl": integration.baseUrl,
                "urlTemplate": integration.urlTemplate,
                "frequency": integration.frequency,
                "forceState": Self.orNull(integration.forceState),
                "cacheUrlForState": [
                    "state": state,
                    "url": Self.orNull(SellwildLocalizedListings.buildCacheURL(integration, state: state)?.absoluteString),
                ],
                "everyNth": SellwildLocalizedListings.everyN(frequencyPercent: integration.frequency),
            ] as [String: Any]
        }

        let context = SellwildFailures.context
        return [
            "partnerCode": config.partnerCode,
            "slug": config.slug,
            "mobileZids": config.mobileZids,
            "mobileBannerZid": Self.orNull(config.mobileBannerZid),
            "adRefreshIntervalMs": Self.orNull(refresh < 0 ? nil : Int((refresh * 1000).rounded())),
            "iabCats": config.iabCats,
            "adStack": [
                "global": Self.orNull(SellwildAdStack.parse(remote["AD_STACK"])?.rawValue),
                "byZone": byZone,
                "resolved": resolvedStack,
            ] as [String: Any],
            "eventsEnabled": events.eventsEnabled,
            "failuresEnabled": SellwildFailuresCore.coerceFlag(context.failuresEnabled),
            "failuresSampleRate": context.sampleRate,
            "appBundleId": Self.orNull(config.appBundleId),
            "appStoreUrl": Self.orNull(config.appStoreUrl),
            "bannerSizesByZone": bannerSizes,
            "houseAd": [
                "enabled": SellwildHouseAd.isEnabled(remoteValues: remote),
                "zone": houseZone,
                "size": "300x250",
                "candidates": candidates.map { ["image": $0.imageURL, "click": Self.orNull($0.clickURL)] as [String: Any] },
            ] as [String: Any],
            "localizedListings": localized,
        ]
    }

    /// The part of an expected value iOS is held to: the `ios` entry of the
    /// per-OS fields.
    private static func iosView(_ field: String, _ expected: Any?) -> Any {
        let perOS = ["mobileZids", "mobileBannerZid", "appBundleId", "appStoreUrl"]
        if perOS.contains(field), let byOS = expected as? [String: Any] { return Self.orNull(byOS["ios"]) }
        return Self.orNull(expected)
    }

    func testAppConfigConformance() async throws {
        let doc = try expectations("app-config")
        let drift = try drift("app-config")
        XCTAssertGreaterThanOrEqual(doc.cases.count, 37)
        XCTAssertEqual(doc.zones, ["43", "280", "999"])

        for entry in doc.cases {
            SellwildFailures.resetForTests()
            capture = FailureCapture()
            capture.install()
            let body = try Fixtures.data(entry.file)
            let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any], entry.file)
            let events = SellwildAPIClient(session: session, eventTransport: CapturingEventTransport().transport,
                                           eventClock: ManualEventClock().clock)
            let config = await configure(body, events: events)
            let actual = try appConfigResult(config, raw: raw, events: events, zones: doc.zones)

            let held = Set(actual.keys)
            XCTAssertEqual(held.union(Self.appConfigFieldsHeldElsewhere).sorted(), doc.iosFields,
                           "every field iOS is held to is checked here or listed as held elsewhere")
            let drifting = Self.namedFields(drift[entry.file], among: doc.iosFields)
            for field in held.sorted() {
                check(entry.file, field: field, actual: actual[field] as Any,
                      expected: Self.iosView(field, entry.expected[field]), drifting: drifting.contains(field))
            }
            XCTAssertEqual(capture.events.map(\.action), [], "\(entry.file): a valid config reports no failure")
            XCTAssertEqual(capture.calls, 0, "\(entry.file): a valid config makes no log call")
        }
    }

    // MARK: listings-response

    func testListingsConformance() throws {
        let doc = try expectations("listings-response")
        let drift = try drift("listings-response")
        XCTAssertEqual(doc.iosFields, ["ids", "items", "nullRemoteUrlIds", "widgetCacheVersionId"])

        for entry in doc.cases {
            SellwildFailures.resetForTests()
            capture = FailureCapture()
            capture.install()
            let body = try Fixtures.data(entry.file)
            StubURLProtocol.handler = { _ in .init(status: 200, body: body) }
            let client = SellwildAPIClient(session: session)
            let done = expectation(description: entry.file)
            var result: Result<SellwildListingsResponse, Error>?
            client.fetchListings(config: SellwildConfig(partnerCode: "conformance", listingsUrl: "https://cache.sellwild.com/conformance")) {
                result = $0
                done.fulfill()
            }
            wait(for: [done], timeout: 10)
            let response = try XCTUnwrap(result, entry.file).get()

            // Ids whose remote_url is JSON null in the input, and that iOS
            // reads as absent (never the text "null").
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let items = ((root["result"] as? [String: Any]) ?? root)["rs"] as? [[String: Any]] ?? []
            let nullIds = Set(items.filter { $0["remote_url"] is NSNull }.map { "\($0["id"] ?? "")" })

            let actual: [String: Any] = [
                "items": response.listings.count,
                "ids": response.listings.map(\.id),
                "nullRemoteUrlIds": response.listings.filter { nullIds.contains($0.id) && $0.remoteUrl == nil }.map(\.id),
                "widgetCacheVersionId": Self.orNull(response.widgetCacheVersionId),
            ]
            let drifting = Self.namedFields(drift[entry.file], among: doc.iosFields)
            for field in doc.iosFields {
                check(entry.file, field: field, actual: actual[field] as Any, expected: Self.orNull(entry.expected[field]),
                      drifting: drifting.contains(field))
            }
            XCTAssertEqual(capture.events.map(\.action), [], "\(entry.file): a valid feed reports no failure")
            XCTAssertEqual(capture.calls, 0, "\(entry.file): a valid feed makes no log call")
        }
    }
}
