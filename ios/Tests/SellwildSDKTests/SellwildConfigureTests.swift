import XCTest
@testable import SellwildSDK

/// `SellwildSDK.configure`: context wiring at configure time and the
/// remote-config failure sites. The fetch goes to `StubURLProtocol`, the
/// events client is a fresh one, and bootstrap is recorded instead of
/// starting GMA and Prebid.
final class SellwildConfigureTests: XCTestCase {

    private var capture: FailureCapture!
    private var events: SellwildAPIClient!
    private var session: URLSession!
    private var bootstrapped: [SellwildConfig] = []
    private var bootstrappedOnMain: [Bool] = []

    override func setUp() {
        super.setUp()
        SellwildFailures.resetForTests()
        capture = FailureCapture()
        capture.install()
        events = SellwildAPIClient(session: StubURLProtocol.makeSession(),
                                   eventTransport: CapturingEventTransport().transport,
                                   eventClock: ManualEventClock().clock)
        session = StubURLProtocol.makeSession()
        bootstrapped = []
        bootstrappedOnMain = []
    }

    override func tearDown() {
        session.finishTasksAndInvalidate()
        SellwildFailures.resetForTests()
        SellwildLog.isEnabled = false
        SellwildLog.setOutput(nil)
        capture = nil
        events = nil
        super.tearDown()
    }

    private func configure(
        partnerCode: String = "weatherbug",
        slug: String = "weatherbug-weatherbug",
        session: URLSession? = nil,
        makeURL: @escaping (String) -> URL? = { URL(string: $0) },
        overrides: ((inout SellwildConfig) -> Void)? = nil
    ) async -> SellwildConfig {
        let environment = SellwildSDK.ConfigureEnvironment(
            session: session ?? self.session,
            makeURL: makeURL,
            events: events,
            bootstrap: { [self] config in
                bootstrappedOnMain.append(Thread.isMainThread)
                bootstrapped.append(config)
            }
        )
        return await SellwildSDK.configure(partnerCode: partnerCode, slug: slug, timeout: 3,
                                           overrides: overrides, environment: environment)
    }

    private func respond(_ object: Any, status: Int = 200) {
        StubURLProtocol.handler = { _ in try .json(object, status: status) }
    }

    private var onlyFailure: SellwildFailuresCore.Event? {
        XCTAssertEqual(capture.events.count, 1, "a failure is logged once")
        return capture.events.first
    }

    // MARK: Wiring

    func testPartnerCodeIsSetBeforeTheFetch() async throws {
        var seen: (failures: String?, events: String?, request: URLRequest?)
        let raw = try AppConfigFactory.make()
        StubURLProtocol.handler = { [self] request in
            seen = (SellwildFailures.context.partnerCode, events.partnerCode, request)
            return try .json(raw)
        }
        _ = await configure()

        XCTAssertEqual(seen.failures, "weatherbug")
        XCTAssertEqual(seen.events, "weatherbug")
        let request = try XCTUnwrap(seen.request)
        XCTAssertEqual(request.url?.absoluteString, "https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "SellwildSDK/\(SellwildSDK.sdkVersion) (ios)")
        XCTAssertEqual(request.timeoutInterval, 3)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertTrue(capture.events.isEmpty)
    }

    func testFlagsAndDebugAreAppliedAtConfigure() async throws {
        let raw = try AppConfigFactory.make([
            "EVENTS_ENABLED": true, "FAILURES_ENABLED": "off", "FAILURES_SAMPLE_RATE": "0.25", "DEBUG": true,
        ])
        respond(raw)
        let config = await configure()

        XCTAssertEqual(config.partnerCode, "weatherbug")
        XCTAssertEqual(config.listingsUrl, raw["LISTINGS"] as? String)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: try XCTUnwrap(config.remoteJSON)) as? NSDictionary, raw as NSDictionary)
        XCTAssertTrue(events.eventsEnabled)
        XCTAssertEqual(events.partnerCode, "weatherbug")
        let context = SellwildFailures.context
        XCTAssertEqual(context.partnerCode, "weatherbug")
        XCTAssertTrue(context.debug)
        XCTAssertEqual(context.eventsEnabled as? Bool, true)
        XCTAssertEqual(context.failuresEnabled as? String, "off", "kept raw; the core coerces it")
        XCTAssertEqual(context.failuresSampleRate as? String, "0.25")
        XCTAssertFalse(context.isEnabled)
        XCTAssertEqual(context.sampleRate, 0.25)
        XCTAssertTrue(SellwildLog.isEnabled)
        XCTAssertEqual(bootstrapped.map(\.partnerCode), ["weatherbug"])
        XCTAssertEqual(bootstrappedOnMain, [true])
    }

    func testDisplayAndThirdPartyKeysAreApplied() async throws {
        respond(try AppConfigFactory.make([
            "PARTNER_URL": "https://partner.invalid", "BUY_NOW_TEXT": "Buy", "TITLE_COLOR": "#111111",
            "FONT_COLOR": "#222222", "PRICE_COLOR": "#333333", "PRICE_FONT_COLOR": "#444444",
            "BACKGROUND": "#555555", "WATERMARK_TITLE": "Sellwild", "DISABLE_GPT": true,
            "BOLTIVE": true, "LOTAME": true,
        ]))
        let config = await configure()
        XCTAssertEqual(config.partnerUrl, "https://partner.invalid")
        XCTAssertEqual(config.buyNowText, "Buy")
        XCTAssertEqual(config.titleColor, "#111111")
        XCTAssertEqual(config.fontColor, "#222222")
        XCTAssertEqual(config.priceColor, "#333333")
        XCTAssertEqual(config.priceFontColor, "#444444")
        XCTAssertEqual(config.bgColor, "#555555", "BACKGROUND stands in for BG_COLOR")
        XCTAssertEqual(config.watermarkTitle, "Sellwild")
        XCTAssertTrue(config.disableGpt)
        XCTAssertTrue(config.boltive)
        XCTAssertTrue(config.lotame)
    }

    func testEventsKillSwitchReachesTheEventsClientAtConfigure() async throws {
        respond(try AppConfigFactory.make(["EVENTS_ENABLED": "false"]))
        _ = await configure()
        XCTAssertFalse(events.eventsEnabled)
        XCTAssertFalse(SellwildFailures.context.isEnabled)
    }

    func testOverridesRunBeforeTheFlagsAreApplied() async throws {
        respond(try AppConfigFactory.make())
        _ = await configure(overrides: { config in
            config.partnerCode = "override"
            config.debug = true
        })
        XCTAssertEqual(events.partnerCode, "override")
        XCTAssertEqual(SellwildFailures.context.partnerCode, "override")
        XCTAssertTrue(SellwildFailures.context.debug)
        XCTAssertEqual(bootstrapped.map(\.partnerCode), ["override"])
    }

    /// FAILURES.md 5.3/5.4 through the real iOS parsing, for every app-config
    /// case in contracts/expectations/app-config.expected.json.
    func testFlagCoercionMatchesTheExpectations() async throws {
        let expectations = try Fixtures.dict("expectations/app-config.expected.json")
        let cases = try XCTUnwrap(expectations["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for entry in cases {
            let file = try XCTUnwrap(entry["file"] as? String)
            let expected = try XCTUnwrap(entry["expected"] as? [String: Any], file)
            let body = try Fixtures.data(file)
            StubURLProtocol.handler = { _ in .init(status: 200, body: body) }
            SellwildFailures.resetForTests()
            capture.install()
            _ = await configure()

            let context = SellwildFailures.context
            XCTAssertEqual(events.eventsEnabled, expected["eventsEnabled"] as? Bool, file)
            XCTAssertEqual(SellwildFailuresCore.coerceFlag(context.eventsEnabled), expected["eventsEnabled"] as? Bool, file)
            XCTAssertEqual(SellwildFailuresCore.coerceFlag(context.failuresEnabled), expected["failuresEnabled"] as? Bool, file)
            XCTAssertEqual(context.sampleRate, (expected["failuresSampleRate"] as? NSNumber)?.doubleValue, file)
            XCTAssertTrue(capture.events.isEmpty, file)
        }
    }

    // MARK: Failure sites (fallback unchanged: defaults are kept)

    private func assertDefaultsKept(_ config: SellwildConfig, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(config.partnerCode, "weatherbug", file: file, line: line)
        XCTAssertNil(config.remoteJSON, file: file, line: line)
        XCTAssertNil(config.listingsUrl, file: file, line: line)
        XCTAssertEqual(config.effectiveListingsUrl, SellwildConfig.defaultListingsCacheURL, file: file, line: line)
        XCTAssertEqual(bootstrapped.count, 1, "bootstrap still runs", file: file, line: line)
        XCTAssertTrue(events.eventsEnabled, file: file, line: line)
        XCTAssertEqual(events.partnerCode, "weatherbug", file: file, line: line)
    }

    func testMissingConfigReportsHTTPStatus() async throws {
        let body = try AppConfigFactory.missingBody()
        StubURLProtocol.handler = { _ in .init(status: 403, headers: ["Content-Type": "application/xml"], body: body) }
        let config = await configure(slug: "weatherbug-main")

        assertDefaultsKept(config)
        let event = try XCTUnwrap(onlyFailure)
        XCTAssertEqual(event.action, "config.fetch.http")
        XCTAssertEqual(event.label, "remoteConfig")
        XCTAssertEqual(event.attributes["code"], "weatherbug", "the partner is known before the fetch")
        XCTAssertEqual(event.attributes["httpStatus"], "403")
        XCTAssertEqual(event.attributes["host"], "widget.sellwild.com")
        XCTAssertEqual(event.attributes["msg"], "HTTP 403")
        XCTAssertEqual(event.attributes["severity"], "error")
        XCTAssertEqual(capture.flushes, 1)
    }

    func testBodyThatIsNotJSONReportsParse() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("{\"CODE\":".utf8)) }
        let config = await configure()

        assertDefaultsKept(config)
        let event = try XCTUnwrap(onlyFailure)
        XCTAssertEqual(event.action, "config.fetch.parse")
        XCTAssertEqual(event.attributes["errName"], "NSCocoaErrorDomain(3840)")
        XCTAssertNotNil(event.attributes["msg"])
    }

    func testJSONThatIsNotAnObjectReportsInvalid() async throws {
        respond([try AppConfigFactory.make()])
        let config = await configure()

        assertDefaultsKept(config)
        let event = try XCTUnwrap(onlyFailure)
        XCTAssertEqual(event.action, "config.parse.invalid")
        XCTAssertEqual(event.attributes["msg"], "remote config is not a JSON object")
    }

    func testTimeoutIsReportedAsTimeout() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let config = await configure()

        assertDefaultsKept(config)
        let event = try XCTUnwrap(onlyFailure)
        XCTAssertEqual(event.action, "config.fetch.timeout")
        XCTAssertEqual(event.attributes["errName"], "NSURLErrorDomain(-1001)")
        XCTAssertEqual(event.attributes["host"], "widget.sellwild.com")
    }

    func testOtherTransportErrorsAreReportedAsNetwork() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let config = await configure()

        assertDefaultsKept(config)
        let event = try XCTUnwrap(onlyFailure)
        XCTAssertEqual(event.action, "config.fetch.network")
        XCTAssertEqual(event.attributes["errName"], "NSURLErrorDomain(-1009)")
    }

    func testCancelledFetchIsNotAFailure() async throws {
        var lines: [String] = []
        SellwildLog.setOutput { lines.append($0) }
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        _ = await configure(overrides: { $0.debug = true })

        XCTAssertTrue(capture.events.isEmpty, "a caller abort is not a failure")
        XCTAssertEqual(lines, [], "the debug flag is applied after the fetch")

        SellwildLog.isEnabled = true
        _ = await configure()
        XCTAssertEqual(lines, ["[SellwildSDK] remote config fetch cancelled"])
        XCTAssertTrue(capture.events.isEmpty)
    }

    func testResponseThatIsNotHTTPIsReported() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NonHTTPURLProtocol.self]
        let plain = URLSession(configuration: configuration)
        defer { plain.finishTasksAndInvalidate() }
        let config = await configure(session: plain)

        assertDefaultsKept(config)
        let event = try XCTUnwrap(onlyFailure)
        XCTAssertEqual(event.action, "config.fetch.http")
        XCTAssertEqual(event.attributes["msg"], "not an HTTP response")
        XCTAssertNil(event.attributes["httpStatus"])
    }

    func testURLThatCannotBeBuiltKeepsDefaultsInsteadOfCrashing() async throws {
        // Before iOS 17, URL(string:) returns nil for some partner codes and
        // the old force unwrap crashed. Newer systems encode them, so the
        // seam stands in for the old behavior.
        StubURLProtocol.handler = { _ in
            XCTFail("no request without a URL")
            return .init(status: 500)
        }
        var built: [String] = []
        let config = await configure(partnerCode: "weatherbug", makeURL: { built.append($0); return nil })

        assertDefaultsKept(config)
        XCTAssertEqual(built, ["https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json"])
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        let event = try XCTUnwrap(onlyFailure)
        XCTAssertEqual(event.action, "config.url.invalid")
        XCTAssertEqual(event.label, "configure")
        XCTAssertEqual(event.attributes["severity"], "fatal")
        XCTAssertEqual(event.attributes["host"], "widget.sellwild.com")
        XCTAssertEqual(capture.flushes, 1)
    }

    func testFailureContextStaysUnsetUntilAConfigLoads() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        _ = await configure()
        let context = SellwildFailures.context
        XCTAssertNil(context.eventsEnabled)
        XCTAssertNil(context.failuresEnabled)
        XCTAssertNil(context.failuresSampleRate)
        XCTAssertTrue(context.isEnabled, "unset is on, so config failures are still reported")
        XCTAssertEqual(capture.events.count, 1)
    }

    // MARK: Live environment

    func testLiveEnvironmentUsesTheSharedClientAndSession() {
        let live = SellwildSDK.ConfigureEnvironment.live
        XCTAssertTrue(live.session === URLSession.shared)
        XCTAssertTrue(live.events === SellwildAPIClient.shared)
        XCTAssertEqual(live.makeURL("https://widget.sellwild.com/app/a/b.json")?.host, "widget.sellwild.com")
        XCTAssertNil(live.makeURL(""))
    }
}

/// Answers every request with a plain (non-HTTP) URLResponse.
private final class NonHTTPURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let response = URLResponse(url: url, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // Nothing to cancel: startLoading answers before returning.
    }
}
