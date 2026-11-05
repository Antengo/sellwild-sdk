import XCTest
@testable import SellwildSDK

/// GrowthCode Signal Resolve: settings resolution, the once-per-launch sync
/// with its throttle and MAID policy, and a report for each failure. The
/// transport, clock, defaults suite and advertising id are injected; sync
/// answers come from the growthcode-sync-response and eid-blob factories.
final class SellwildGrowthCodeTests: FailureCapturingTestCase {

    private var savedEnvironment: SellwildGrowthCode.Environment!
    private var defaults: UserDefaults!
    private var suite: String!
    private var sent: [URLRequest] = []
    private var answer: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    private var maid: (String, String)?
    private let now: Double = 1_790_000_000_000
    private let pid = "gc-partner"
    private let endpoint = "https://ids.api.gcprivacy.id/v4/sync/api"

    override func setUp() {
        super.setUp()
        savedEnvironment = SellwildGrowthCode.environment
        suite = "sellwild.growthcode.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        sent = []
        maid = nil
        SellwildGrowthCode.resetForTesting()
        SellwildGrowthCode.environment = SellwildGrowthCode.Environment(
            send: { [self] request, completion in
                sent.append(request)
                completion(answer.0, answer.1, answer.2)
            },
            nowMs: { [self] in now },
            defaults: defaults,
            advertisingId: { [self] in maid }
        )
    }

    override func tearDown() {
        SellwildGrowthCode.environment = savedEnvironment
        SellwildGrowthCode.resetForTesting()
        defaults.removePersistentDomain(forName: suite)
        SellwildEidRegistry.setGrowthCode([])
        super.tearDown()
    }

    private func reply(_ object: Any, status: Int = 200) throws {
        let url = try XCTUnwrap(URL(string: endpoint))
        answer = (try Factory.data(object), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil), nil)
    }

    private func enabledConfig(_ overrides: [String: Any] = [:]) throws -> SellwildConfig {
        try AppConfigFactory.config(Factory.merge([
            "GROWTHCODE_ENABLED": true,
            "GROWTHCODE_PARTNER_ID": pid,
            "GROWTHCODE_SYNC_URL": "https://www.weatherbug.com/home",
        ], overrides))
    }

    private func run(_ config: SellwildConfig, zone: String? = "43") {
        SellwildGrowthCode.resolveIfNeeded(config: config, zoneId: zone)
    }

    private var storedGcid: String? { defaults.string(forKey: "_sw_gc_id.\(pid)") }
    private var storedEb: String? { defaults.string(forKey: "_sw_gc_eb.\(pid)") }
    private var storedSyncTime: Double? { defaults.object(forKey: "_sw_gc_synced_at.\(pid)") as? Double }

    // MARK: Settings

    func testSettingsPreferLocalThenRemoteThenDefault() throws {
        let remote = try enabledConfig(["GROWTHCODE_ENDPOINT": "https://gc.invalid/sync", "GROWTHCODE_SEND_MAID": "0",
                                        "GROWTHCODE_TTL_HOURS": "12"])
        let s = SellwildGrowthCode.resolve(config: remote, zoneId: nil)
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.partnerId, pid)
        XCTAssertEqual(s.endpoint, "https://gc.invalid/sync")
        XCTAssertEqual(s.syncUrl, "https://www.weatherbug.com/home")
        XCTAssertFalse(s.sendMaid)
        XCTAssertEqual(s.ttlHours, 12)

        var local = remote
        local.growthCode = SellwildGrowthCodeConfig(enabled: false, partnerId: "local", endpoint: "https://local.invalid",
                                                    syncUrl: "local.example", sendMaid: true, ttlHours: 6)
        let l = SellwildGrowthCode.resolve(config: local, zoneId: nil)
        XCTAssertFalse(l.enabled)
        XCTAssertEqual(l.partnerId, "local")
        XCTAssertEqual(l.endpoint, "https://local.invalid")
        XCTAssertTrue(l.sendMaid)
        XCTAssertEqual(l.ttlHours, 6)

        let d = SellwildGrowthCode.resolve(config: SellwildConfig(partnerCode: "p"), zoneId: nil)
        XCTAssertFalse(d.enabled)
        XCTAssertEqual(d.endpoint, SellwildGrowthCode.defaultEndpoint)
        XCTAssertTrue(d.sendMaid)
        XCTAssertEqual(d.ttlHours, SellwildGrowthCode.defaultTtlHours)
    }

    func testPerZoneEnable() throws {
        let config = try AppConfigFactory.config(["GROWTHCODE_ENABLED": "no", "GROWTHCODE_ENABLED_BY_ZONE": ["43": 1, "280": "off"]])
        XCTAssertTrue(SellwildGrowthCode.resolve(config: config, zoneId: "43").enabled)
        XCTAssertFalse(SellwildGrowthCode.resolve(config: config, zoneId: "280").enabled)
        XCTAssertFalse(SellwildGrowthCode.resolve(config: config, zoneId: nil).enabled)
        let flags = try AppConfigFactory.config(["GROWTHCODE_ENABLED": 2, "GROWTHCODE_TTL_HOURS": 1.5])
        XCTAssertTrue(SellwildGrowthCode.resolve(config: flags, zoneId: nil).enabled)
        XCTAssertEqual(SellwildGrowthCode.resolve(config: flags, zoneId: nil).ttlHours, 1.5)
        let other = try Factory.offSchema(because: "a GROWTHCODE_ENABLED_BY_ZONE value must be a flag, not a list") {
            try AppConfigFactory.config(["GROWTHCODE_ENABLED_BY_ZONE": ["43": ["on"]]])
        }
        XCTAssertFalse(SellwildGrowthCode.resolve(config: other, zoneId: "43").enabled)
    }

    /// JSON numbers reach the TTL parser as NSNumber: most read as a Double,
    /// an integer a Double cannot hold exactly reads as an Int, and one too
    /// large for an Int reads through NSNumber.
    func testTtlNumbersOfEveryWidth() throws {
        let table: [(Any, Double)] = [(12, 12), (1.5, 1.5), (9_007_199_254_740_993, 9_007_199_254_740_992), (UInt64.max, Double(UInt64.max))]
        for (ttl, expected) in table {
            XCTAssertEqual(SellwildGrowthCode.resolve(config: try enabledConfig(["GROWTHCODE_TTL_HOURS": ttl]), zoneId: nil).ttlHours, expected, "\(ttl)")
        }
    }

    /// GROWTHCODE_TTL_HOURS may be text (the schema allows any string).
    /// `Double(_:)` does not trim, so " 12 " reads as unset: the 48-hour
    /// default, with no report, as it always has. Core reads 12
    /// (drift/ios.json `other`, growthcode.ttlTextPadding). Core does not
    /// report a TTL that is not a number either.
    func testTtlTextWithSpacesReadsAsTheDefault() throws {
        XCTAssertEqual(SellwildGrowthCode.resolve(config: try enabledConfig(["GROWTHCODE_TTL_HOURS": "24"]), zoneId: nil).ttlHours, 24)
        XCTAssertEqual(SellwildGrowthCode.resolve(config: try enabledConfig(["GROWTHCODE_TTL_HOURS": " 12 "]), zoneId: nil).ttlHours,
                       SellwildGrowthCode.defaultTtlHours)
        XCTAssertEqual(SellwildGrowthCode.resolve(config: try enabledConfig(["GROWTHCODE_TTL_HOURS": "12\n"]), zoneId: nil).ttlHours,
                       SellwildGrowthCode.defaultTtlHours)
        capture.none()
    }

    // MARK: Sync

    func testDisabledDoesNothing() throws {
        run(try AppConfigFactory.config())
        XCTAssertTrue(sent.isEmpty)
        capture.none()
    }

    func testEnabledWithoutPartnerOrSyncURLIsReported() throws {
        run(try enabledConfig(["GROWTHCODE_PARTNER_ID": ""]))
        XCTAssertTrue(sent.isEmpty)
        let event = capture.only(.growthcodeConfigMissing, label: .growthcode)
        XCTAssertEqual(event?.attributes["msg"], "GrowthCode is enabled but its partner id or sync URL is missing")
        XCTAssertEqual(event?.attributes["severity"], "warn")

        newLaunch()
        SellwildGrowthCode.resetForTesting()
        run(try enabledConfig(["GROWTHCODE_SYNC_URL": Factory.remove]))
        capture.only(.growthcodeConfigMissing, label: .growthcode)
    }

    /// resolveIfNeeded runs on every ad load. The missing settings are
    /// reported once per launch, and they do not use up the once-per-launch
    /// sync: a config that gains them later still syncs.
    func testMissingSettingsAreReportedOncePerLaunch() throws {
        let missing = try enabledConfig(["GROWTHCODE_PARTNER_ID": Factory.remove])
        for zone in ["43", "43", "280"] { run(missing, zone: zone) }
        XCTAssertTrue(sent.isEmpty)
        capture.only(.growthcodeConfigMissing, label: .growthcode)

        try reply(try GrowthCodeFactory.syncResponse())
        run(try enabledConfig())
        XCTAssertEqual(sent.count, 1, "the sync still runs once the settings are there")
    }

    /// An `atype` longer than Int allows (the schema allows any run of
    /// digits) crashed the parse: `Int(_:)` traps. It now reads as Int.max;
    /// text that reads as infinity or NaN, like any text that is not a
    /// number, reads as 0.
    func testAtypeTooLargeForAnIntIsNotACrash() throws {
        let eids = try EidBlobFactory.variant("minimal", ["source": "id5-sync.com", "uids": [
            ["id": "a", "atype": "99999999999999999999"],
            ["id": "b", "atype": 1e300],
        ]])
        let parsed = SellwildGrowthCode.eidBlob(String(decoding: try Factory.data(eids), as: UTF8.self))
        XCTAssertNil(parsed.problem)
        XCTAssertEqual(parsed.eids.first?.uids.map(\.atype), [Int.max, Int.max])

        let offSchema = try Factory.offSchema(because: "atype text must be digits; Double reads \"inf\" and \"nan\"") {
            try EidBlobFactory.variant("minimal", ["source": "id5-sync.com", "uids": [
                ["id": "c", "atype": "inf"], ["id": "d", "atype": "nan"],
            ]])
        }
        let text = SellwildGrowthCode.eidBlob(String(decoding: try Factory.data(offSchema), as: UTF8.self))
        XCTAssertEqual(text.eids.first?.uids.map(\.atype), [0, 0])
        capture.none()
    }

    func testFirstSyncStoresTheAnswerAndPushesTheEids() throws {
        maid = ("6D92078A-8246-4BA4-AE5B-76104861E7DC", "IDFA")
        try reply(try GrowthCodeFactory.syncResponse())
        run(try enabledConfig())

        let request = try XCTUnwrap(sent.first)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query, [URLQueryItem(name: "pid", value: pid), URLQueryItem(name: "u", value: "https://www.weatherbug.com/home")])
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self),
                       "h=www.weatherbug.com&maid=6D92078A-8246-4BA4-AE5B-76104861E7DC&maid_type=IDFA")

        XCTAssertEqual(storedGcid, "gc-fixture-0001")
        XCTAssertNotNil(storedEb)
        XCTAssertEqual(storedSyncTime, now)
        XCTAssertEqual(SellwildEidRegistry.current.map(\.source), ["uidapi.com", "id5-sync.com"])
        capture.none()

        run(try enabledConfig())
        XCTAssertEqual(sent.count, 1, "once per launch")
    }

    func testThrottleAndCachedEidReplay() throws {
        defaults.set("gc-old", forKey: "_sw_gc_id.\(pid)")
        defaults.set(now - 3_600_000, forKey: "_sw_gc_synced_at.\(pid)")
        defaults.set(String(decoding: try Factory.data(EidBlobFactory.single(source: "uidapi.com", id: "cached")), as: UTF8.self),
                     forKey: "_sw_gc_eb.\(pid)")
        run(try enabledConfig())
        XCTAssertTrue(sent.isEmpty, "inside the 48 h window")
        XCTAssertEqual(SellwildEidRegistry.current.map(\.source), ["uidapi.com"], "cached eids replayed")

        SellwildGrowthCode.resetForTesting()
        defaults.set(now - 49 * 3_600_000, forKey: "_sw_gc_synced_at.\(pid)")
        try reply(try GrowthCodeFactory.variant("gc-id-null"))
        run(try enabledConfig())
        XCTAssertEqual(String(decoding: try XCTUnwrap(sent.first?.httpBody), as: UTF8.self), "gcid=gc-old&h=www.weatherbug.com")
        XCTAssertEqual(storedGcid, "gc-old", "a null gc_id keeps the stored one")
        XCTAssertEqual(storedSyncTime, now)
        capture.none()
    }

    func testNoDeviceIdAndSendMaidOffSkipsTheCall() throws {
        run(try enabledConfig(["GROWTHCODE_SEND_MAID": false]))
        XCTAssertTrue(sent.isEmpty)
        capture.none()

        SellwildGrowthCode.resetForTesting()
        try reply(try GrowthCodeFactory.variant("empty"))
        run(try enabledConfig())
        XCTAssertEqual(sent.count, 1, "sendMaid on: the call goes without a maid")
        XCTAssertEqual(storedSyncTime, now)
        capture.none()
    }

    func testEndpointThatIsNotAURL() throws {
        run(try enabledConfig(["GROWTHCODE_ENDPOINT": "http://exa mple.invalid/sync"]))
        XCTAssertTrue(sent.isEmpty)
        let event = capture.only(.growthcodeUrlInvalid, label: .growthcode)
        XCTAssertEqual(event?.attributes["msg"], "GrowthCode endpoint URL could not be built")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    private func assertSyncFailure(_ code: SellwildFailureCode, file: StaticString = #filePath, line: UInt = #line) throws -> SellwildFailuresCore.Event? {
        run(try enabledConfig())
        XCTAssertEqual(sent.count, 1, file: file, line: line)
        XCTAssertNil(storedSyncTime, "the throttle is not saved, so it retries next launch", file: file, line: line)
        let event = capture.only(code, label: .growthcode, file: file, line: line)
        XCTAssertEqual(event?.attributes["severity"], "warn", "GrowthCode is best effort", file: file, line: line)
        return event
    }

    func testTimeout() throws {
        answer = (nil, nil, URLError(.timedOut))
        XCTAssertEqual(try assertSyncFailure(.growthcodeSyncTimeout)?.attributes["host"], "ids.api.gcprivacy.id")
    }

    func testNetworkError() throws {
        answer = (nil, nil, URLError(.cannotFindHost))
        XCTAssertEqual(try assertSyncFailure(.growthcodeSyncNetwork)?.attributes["errName"], "NSURLErrorDomain(-1003)")
    }

    func testCancelledIsNotAFailure() throws {
        answer = (nil, nil, URLError(.cancelled))
        let lines = try debugLines { run(try enabledConfig()) }
        XCTAssertEqual(lines, ["[SellwildGrowthCode] sync cancelled"])
        XCTAssertNil(storedSyncTime)
        capture.none()
    }

    func testHTTPError() throws {
        try reply(try GrowthCodeFactory.syncResponse(), status: 503)
        let event = try assertSyncFailure(.growthcodeSyncHttp)
        XCTAssertEqual(event?.attributes["httpStatus"], "503")
    }

    func testBodyThatIsNotJSON() throws {
        let url = try XCTUnwrap(URL(string: endpoint))
        answer = (Data("<html/>".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
        let event = try assertSyncFailure(.growthcodeSyncParse)
        XCTAssertEqual(event?.attributes["errName"], "NSCocoaErrorDomain(3840)")
    }

    func testEmptyBody() throws {
        let url = try XCTUnwrap(URL(string: endpoint))
        answer = (Data(), HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil), nil)
        XCTAssertEqual(try assertSyncFailure(.growthcodeSyncParse)?.attributes["msg"], "GrowthCode sync response has no body")
    }

    func testBodyThatIsNotAnObject() throws {
        try reply([try GrowthCodeFactory.syncResponse()])
        XCTAssertEqual(try assertSyncFailure(.growthcodeSyncParse)?.attributes["msg"], "GrowthCode sync response is not a JSON object")
    }

    func testEidBlobProblemsAreReported() throws {
        try reply(try GrowthCodeFactory.syncResponse(["eb": "{not json"]))
        run(try enabledConfig())
        XCTAssertEqual(storedSyncTime, now, "the sync itself worked")
        let event = capture.only(.growthcodeEidInvalid, label: .growthcode)
        XCTAssertEqual(event?.attributes["msg"], "eid blob is not valid JSON")
        XCTAssertEqual(event?.attributes["severity"], "warn")
        XCTAssertTrue(SellwildEidRegistry.current.isEmpty)
    }

    // MARK: Pure parts

    func testEidBlobParsing() throws {
        let text = String(decoding: try Factory.data(EidBlobFactory.make()), as: UTF8.self)
        let full = SellwildGrowthCode.eidBlob(text)
        XCTAssertNil(full.problem)
        XCTAssertEqual(full.eids.map(\.source), ["uidapi.com", "id5-sync.com"])
        XCTAssertEqual(full.eids.last?.uids.map(\.atype), [1, 0], "text atype parsed, missing atype is 0")
        XCTAssertEqual(full.eids.last?.uids.last?.ext?["stype"] as? String, "ppuid")

        XCTAssertEqual(SellwildGrowthCode.eidBlob("{}").problem, "eid blob is not a list of objects")
        let partial = try Factory.offSchema(because: "source must not be empty: the entry the parser drops") {
            try EidBlobFactory.make(["source": ""])
        } + [["source": "x.com", "uids": []], ["source": "y.com", "uids": [["id": ""]]]]
        let dropped = SellwildGrowthCode.eidBlob(String(decoding: try Factory.data(partial), as: UTF8.self))
        XCTAssertEqual(dropped.eids.map(\.source), ["id5-sync.com"])
        XCTAssertEqual(dropped.problem, "3 eid entries or uids without a source, uids or id were dropped")
        capture.none()

        XCTAssertTrue(SellwildGrowthCode.parseEidBlob("[1]").isEmpty)
        capture.only(.growthcodeEidInvalid, label: .growthcode)
    }

    func testSyncOutcome() throws {
        let url = try XCTUnwrap(URL(string: endpoint))
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let body = try Factory.data(try GrowthCodeFactory.syncResponse(["gc_id": "a"]))
        XCTAssertEqual(try SellwildGrowthCode.syncOutcome(data: body, response: ok, error: nil).get()["gc_id"] as? String, "a")
        guard case .failure(.parse(nil, "GrowthCode sync response has no body")) = SellwildGrowthCode.syncOutcome(data: nil, response: ok, error: nil) else {
            return XCTFail("no body")
        }
        let plain = URLResponse(url: url, mimeType: nil, expectedContentLength: 2, textEncodingName: nil)
        let empty = try Factory.data(try GrowthCodeFactory.variant("empty"))
        XCTAssertNoThrow(try SellwildGrowthCode.syncOutcome(data: empty, response: plain, error: nil).get(),
                         "a response that is not HTTP has no status to judge")
    }

    func testRequestAndFormBody() throws {
        XCTAssertNil(SellwildGrowthCode.syncRequest(endpoint: "http://exa mple", pid: "p", syncUrl: "u", gcid: nil, maid: nil))
        let request = try XCTUnwrap(SellwildGrowthCode.syncRequest(endpoint: "https://gc.invalid/sync?v=4", pid: "p 1", syncUrl: "site.example",
                                                                   gcid: "g&1", maid: nil))
        XCTAssertEqual(request.url?.absoluteString, "https://gc.invalid/sync?v=4&pid=p%201&u=site.example")
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self), "gcid=g%261&h=site.example",
                       "a sync URL that is not a URL is sent as the host itself")
        XCTAssertEqual(SellwildGrowthCode.formBody(gcid: "", host: nil, maid: nil), "")
    }

    func testAdvertisingIdAndThrottle() {
        XCTAssertNil(SellwildGrowthCode.maid(fromIDFA: "00000000-0000-0000-0000-000000000000"))
        XCTAssertEqual(SellwildGrowthCode.maid(fromIDFA: "ABC")?.1, "IDFA")
        XCTAssertTrue(SellwildGrowthCode.shouldSync(gcid: nil, lastSyncMs: now, ttlHours: 48, nowMs: now))
        XCTAssertTrue(SellwildGrowthCode.shouldSync(gcid: "g", lastSyncMs: nil, ttlHours: 48, nowMs: now))
        XCTAssertFalse(SellwildGrowthCode.shouldSync(gcid: "g", lastSyncMs: now - 1, ttlHours: 48, nowMs: now))
        XCTAssertTrue(SellwildGrowthCode.shouldSync(gcid: "g", lastSyncMs: now - 48 * 3_600_000, ttlHours: 48, nowMs: now))
    }

    func testLiveEnvironment() throws {
        let live = SellwildGrowthCode.Environment.live
        XCTAssertTrue(live.defaults === UserDefaults.standard)
        XCTAssertEqual(live.nowMs(), Date().timeIntervalSince1970 * 1000, accuracy: 5_000)
        // The simulator hands out the zeroed IDFA without ATT authorization.
        XCTAssertNil(live.advertisingId())

        let session = StubURLProtocol.makeSession()
        defer { session.finishTasksAndInvalidate() }
        StubURLProtocol.handler = { _ in try .json(try GrowthCodeFactory.syncResponse()) }
        let done = expectation(description: "send")
        var status: Int?
        SellwildGrowthCode.Environment.sender(session)(URLRequest(url: try XCTUnwrap(URL(string: endpoint)))) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(status, 200)
    }
}
