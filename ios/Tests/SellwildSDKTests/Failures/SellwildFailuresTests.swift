import XCTest
@testable import SellwildSDK

/// The logFailure shell: context, wrapper, the typed call, debug echo, the
/// reentrancy guard, the never-throw wrapper and thread safety. The decision
/// itself is covered by the golden vectors (SellwildFailuresCoreTests).
final class SellwildFailuresTests: XCTestCase {

    private var capture: FailureCapture!

    private enum Boom: Error { case push, flush }

    override func setUp() {
        super.setUp()
        SellwildFailures.resetForTests()
        capture = FailureCapture()
        capture.install()
    }

    override func tearDown() {
        SellwildFailures.resetForTests()
        capture = nil
        super.tearDown()
    }

    // MARK: Events

    func testFirstFailureIsQueuedAndFlushedWithTheContext() throws {
        SellwildFailures.setContext { $0.partnerCode = "weatherbug" }
        SellwildFailures.log(code: .listingsFetchHttp, component: .listings, message: "HTTP 503",
                             httpStatus: 503, url: "https://cache.sellwild.com/listings-img-data-sm?v=2", zoneId: "43")

        let event = try XCTUnwrap(capture.events.first)
        XCTAssertEqual(capture.events.count, 1)
        XCTAssertEqual(capture.flushes, 1, "the first failure of the session is sent at once")
        XCTAssertEqual(event.event, "clientFailure")
        XCTAssertEqual(event.action, "listings.fetch.http")
        XCTAssertEqual(event.label, "listings")
        XCTAssertEqual(event.uid, FailureCapture.uid)
        XCTAssertEqual(event.createdTime, FailureCapture.now)
        XCTAssertEqual(event.attributes, [
            "code": "weatherbug", "client": "ios", "clientVersion": SellwildSDK.sdkVersion, "severity": "error",
            "fv": "2", "msg": "HTTP 503", "httpStatus": "503", "host": "cache.sellwild.com", "zoneId": "43",
            "seq": "1", "repeat": "1"
        ].merging(FailureCapture.appAttributes) { $1 })
        XCTAssertTrue(capture.echoes.isEmpty, "no echo unless debug is on")
    }

    func testLaterFailuresBatchUnlessFatal() {
        SellwildFailures.log(code: .configFetchHttp, component: .remoteConfig)
        SellwildFailures.log(code: .configFetchParse, component: .remoteConfig)
        XCTAssertEqual(capture.events.count, 2)
        XCTAssertEqual(capture.flushes, 1)

        SellwildFailures.log(code: .configUrlInvalid, component: .configure, severity: .fatal)
        XCTAssertEqual(capture.events.map { $0.attributes["severity"] }, ["error", "error", "fatal"])
        XCTAssertEqual(capture.flushes, 2)
        XCTAssertEqual(SellwildFailures.coreState.sessionCount, 3)
    }

    func testErrorGivesNameAndMessage() throws {
        SellwildFailures.log(code: .configFetchTimeout, component: .remoteConfig,
                             error: URLError(.timedOut), message: "remote config")
        let event = try XCTUnwrap(capture.events.first)
        XCTAssertEqual(event.attributes["errName"], "NSURLErrorDomain(-1001)")
        XCTAssertEqual(event.attributes["msg"], "remote config: \(URLError(.timedOut).localizedDescription)")
    }

    func testErrorNames() {
        struct Plain: Error {}
        enum Kind: Error { case bad }
        XCTAssertEqual(SellwildFailures.errorName(Plain()), "Plain")
        XCTAssertEqual(SellwildFailures.errorName(Kind.bad), "Kind")
        XCTAssertEqual(SellwildFailures.errorName(NSError(domain: "SellwildTest", code: 7)), "SellwildTest(7)")
        XCTAssertEqual(SellwildFailures.errorName(URLError(.notConnectedToInternet)), "NSURLErrorDomain(-1009)")
        XCTAssertEqual(SellwildFailures.errorName(CocoaError(.fileNoSuchFile)), "NSCocoaErrorDomain(4)")
        XCTAssertThrowsError(try JSONDecoder().decode([Int].self, from: Data("{}".utf8))) { error in
            XCTAssertEqual(SellwildFailures.errorName(error), "DecodingError")
        }
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: Data("{".utf8))) { error in
            XCTAssertEqual(SellwildFailures.errorName(error), "NSCocoaErrorDomain(3840)")
        }
    }

    // MARK: Context

    // MARK: Input cap (FAILURES.md 3.3 item 4)

    private struct DescribedError: LocalizedError {
        let errorDescription: String?
    }

    func testMessageAndErrorMessageAreCutTo1000UnitsBeforeTheCore() throws {
        // 998 digits sanitize to "<n>", so whatever follows them would be sent.
        let long = String(repeating: "1", count: 998) + "ABCDEFG"

        SellwildFailures.log(code: .listingsFetchHttp, component: .listings,
                             error: DescribedError(errorDescription: long), message: long)

        let event = try XCTUnwrap(capture.events.first)
        XCTAssertEqual(event.attributes["msg"], "<n>AB")
        XCTAssertEqual(event.attributes["errName"], "DescribedError")
    }

    func testTheCutIsExactAndASplitSurrogatePairBecomesTheReplacementCharacter() {
        SellwildFailures.log(code: .listingsFetchHttp, component: .listings,
                             message: String(repeating: "1", count: 996) + "WXYZ")
        SellwildFailures.log(code: .listingsFetchHttp, component: .listings,
                             message: String(repeating: "1", count: 997) + "WXYZ")
        // The cut falls inside the emoji's surrogate pair: TS, Kotlin and Dart
        // keep a lone high surrogate that cleanText turns into U+FFFD.
        SellwildFailures.log(code: .listingsFetchHttp, component: .listings,
                             message: String(repeating: "1", count: 999) + "\u{1F600}tail")

        XCTAssertEqual(capture.events.map { $0.attributes["msg"] }, ["<n>WXYZ", "<n>WXY", "<n>\u{FFFD}"])
    }

    func testCapInputKeepsTheFirst1000UnitsAndNeverHalfAScalar() throws {
        XCTAssertNil(SellwildFailures.capInput(nil))
        XCTAssertEqual(SellwildFailures.capInput("short"), "short")
        let exact = String(repeating: "a", count: 1000)
        XCTAssertEqual(SellwildFailures.capInput(exact), exact)
        XCTAssertEqual(SellwildFailures.capInput(exact + "b"), exact)

        let split = try XCTUnwrap(SellwildFailures.capInput(String(repeating: "a", count: 999) + "\u{1F600}"))
        XCTAssertEqual(split.utf16.count, 1000)
        XCTAssertEqual(split.unicodeScalars.last, "\u{FFFD}")

        let whole = try XCTUnwrap(SellwildFailures.capInput(String(repeating: "a", count: 998) + "\u{1F600}z"))
        XCTAssertEqual(whole.utf16.count, 1000)
        XCTAssertEqual(whole.unicodeScalars.last, "\u{1F600}")
        XCTAssertEqual(SellwildFailures.capInput("abcdef", max: 3), "abc")
    }

    func testContextDefaultsAreUnsetAndOn() {
        let context = SellwildFailures.context
        XCTAssertNil(context.partnerCode)
        XCTAssertFalse(context.debug)
        XCTAssertNil(context.eventsEnabled)
        XCTAssertNil(context.failuresEnabled)
        XCTAssertNil(context.failuresEnabledOverride)
        XCTAssertNil(context.failuresSampleRate)
        XCTAssertNil(context.wrapper)
        XCTAssertEqual(context.client, "ios")
        XCTAssertEqual(context.clientVersion, SellwildSDK.sdkVersion)
        XCTAssertTrue(context.isEnabled)
        XCTAssertEqual(context.sampleRate, 1)
    }

    func testFlagsUseTheContractCoercion() {
        SellwildFailures.setContext {
            $0.eventsEnabled = " TRUE "
            $0.failuresEnabled = "Off"
            $0.failuresSampleRate = " .25 "
        }
        XCTAssertFalse(SellwildFailures.context.isEnabled)
        XCTAssertEqual(SellwildFailures.context.sampleRate, 0.25)

        SellwildFailures.setContext { $0.failuresEnabledOverride = true }
        XCTAssertTrue(SellwildFailures.context.isEnabled, "a local override wins over the remote value")

        SellwildFailures.setContext { $0.eventsEnabled = 0 }
        XCTAssertFalse(SellwildFailures.context.isEnabled, "EVENTS_ENABLED is the master switch")
    }

    func testDisabledFailuresAreDroppedAndEchoedWithTheReason() {
        SellwildFailures.setContext {
            $0.debug = true
            $0.failuresEnabled = true
            $0.failuresEnabledOverride = false
        }
        SellwildFailures.log(code: .listingsFetchNetwork, component: .listings, message: "offline")
        XCTAssertTrue(capture.events.isEmpty)
        XCTAssertEqual(capture.flushes, 0)
        XCTAssertEqual(capture.echoes,
                       ["[Sellwild] failure listings.fetch.network listings error failures_disabled offline"])

        SellwildFailures.setContext {
            $0.failuresEnabledOverride = nil
            $0.eventsEnabled = "false"
        }
        SellwildFailures.log(code: .listingsFetchNetwork, component: .listings)
        XCTAssertTrue(capture.events.isEmpty)
        XCTAssertEqual(capture.echoes.last, "[Sellwild] failure listings.fetch.network listings error events_disabled")
        XCTAssertEqual(SellwildFailures.coreState, SellwildFailuresCore.State(), "a drop leaves the state alone")
    }

    func testSampledOutSessionSendsOnlyFatal() {
        // fnv1a32("<FailureCapture.uid>:failures") / 2^32 is above 0.01.
        XCTAssertFalse(SellwildFailuresCore.isSampled(uid: FailureCapture.uid, rate: 0.01))
        SellwildFailures.setContext { $0.failuresSampleRate = "0.01" }
        SellwildFailures.log(code: .feedCellInvalid, component: .feed)
        XCTAssertTrue(capture.events.isEmpty)
        SellwildFailures.log(code: .feedCellInvalid, component: .feed, severity: .fatal)
        XCTAssertEqual(capture.events.count, 1)
    }

    func testSentFailureIsEchoedInDebug() {
        SellwildFailures.setContext { $0.debug = true }
        SellwildFailures.log(code: .configFetchHttp, component: .remoteConfig, severity: .warn,
                             message: "HTTP 403 from https://widget.sellwild.com/app/x/y.json")
        XCTAssertEqual(capture.echoes,
                       ["[Sellwild] failure config.fetch.http remoteConfig warn sent HTTP 403 from widget.sellwild.com"])
        XCTAssertEqual(capture.events.count, 1)
    }

    func testWrapper() {
        SellwildFailures.setWrapper("react-native")
        XCTAssertEqual(SellwildFailures.context.wrapper, "react-native")
        SellwildFailures.log(code: .bridgeConfigInvalid, component: .bridge)
        SellwildFailures.setWrapper("unity")
        SellwildFailures.log(code: .bridgePropsInvalid, component: .bridge)
        SellwildFailures.setWrapper(nil)
        SellwildFailures.log(code: .bridgeGeoInvalid, component: .bridge)
        XCTAssertEqual(capture.events.map { $0.attributes["wrapper"] }, ["react-native", nil, nil])
    }

    func testSetContextClosureMayReadTheContext() {
        SellwildFailures.setContext { $0.partnerCode = "first" }
        SellwildFailures.setContext { $0.partnerCode = (SellwildFailures.context.partnerCode ?? "") + "-second" }
        XCTAssertEqual(SellwildFailures.context.partnerCode, "first-second")
    }

    // MARK: Guards

    func testNestedLogFromInsideLogIsIgnored() {
        capture.onPush = { _ in
            SellwildFailures.log(code: .storageWriteException, component: .storage)
        }
        SellwildFailures.log(code: .listingsFetchHttp, component: .listings)
        XCTAssertEqual(capture.events.map(\.action), ["listings.fetch.http"])
        XCTAssertEqual(SellwildFailures.coreState.sessionCount, 1)

        // The guard is released afterwards.
        capture.onPush = nil
        SellwildFailures.log(code: .storageWriteException, component: .storage)
        XCTAssertEqual(capture.events.count, 2)
    }

    func testAThrowingSinkIsCountedNotRethrown() {
        capture.pushError = Boom.push
        SellwildFailures.log(code: .listingsFetchHttp, component: .listings)
        XCTAssertEqual(SellwildFailures.internalErrorCount, 1)
        XCTAssertTrue(capture.echoes.isEmpty)

        capture.pushError = nil
        capture.flushError = Boom.flush
        SellwildFailures.setContext { $0.debug = true }
        SellwildFailures.log(code: .configUrlInvalid, component: .configure, severity: .fatal)
        XCTAssertEqual(SellwildFailures.internalErrorCount, 2)
        XCTAssertEqual(capture.echoes.count, 2)
        XCTAssertEqual(capture.echoes.last?.hasPrefix("[Sellwild] failure internal Boom "), true,
                       capture.echoes.last ?? "")

        SellwildFailures.resetForTests()
        XCTAssertEqual(SellwildFailures.internalErrorCount, 0)
    }

    func testConcurrentCallsKeepTheSessionCap() {
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            SellwildFailures.log(code: .feedImageNetwork, component: .feed, message: "image \(i)")
        }
        XCTAssertEqual(capture.events.count, SellwildFailuresCore.Limits.sessionEmits)
        XCTAssertEqual(Set(capture.events.compactMap { $0.attributes["seq"] }).count,
                       SellwildFailuresCore.Limits.sessionEmits)
        XCTAssertEqual(capture.events.filter { $0.attributes["capped"] == "1" }.count, 1)
        XCTAssertEqual(SellwildFailures.coreState.sessionCount, SellwildFailuresCore.Limits.sessionEmits)
    }

    func testResetRestoresAFreshSession() {
        SellwildFailures.setContext { $0.partnerCode = "p"; $0.debug = true }
        SellwildFailures.setWrapper("flutter")
        SellwildFailures.log(code: .bridgeGeoInvalid, component: .geo)
        SellwildFailures.resetForTests()
        XCTAssertNil(SellwildFailures.context.partnerCode)
        XCTAssertNil(SellwildFailures.context.wrapper)
        XCTAssertEqual(SellwildFailures.coreState, SellwildFailuresCore.State())
    }

    // MARK: Live dependencies

    private func queueClient(_ transport: CapturingEventTransport, _ clock: ManualEventClock) -> SellwildAPIClient {
        SellwildAPIClient(session: StubURLProtocol.makeSession(), eventTransport: transport.transport,
                          eventClock: clock.clock)
    }

    func testLiveDependenciesUseTheQueueClockTheSessionUidAndPrint() throws {
        let clock = ManualEventClock()
        let live = SellwildFailures.Dependencies.live(client: queueClient(CapturingEventTransport(), clock))
        XCTAssertEqual(live.now(), clock.nowMs)
        clock.nowMs += 5
        XCTAssertEqual(live.now(), clock.nowMs)
        XCTAssertEqual(live.uid(), SellwildSession.shared.uid)
        let out = try StdoutCapture.run { live.echo("[Sellwild] failure live echo") }
        XCTAssertTrue(out.contains("[Sellwild] failure live echo\n"), out)

        // The SDK default is the shared client, on the system clock.
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let now = SellwildFailures.Dependencies.live().now()
        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThan(now - before, 60_000)
    }

    func testQueueEventKeepsTheFailureUidAndTime() {
        let failure = SellwildFailuresCore.Event(event: "clientFailure", action: "config.fetch.http",
                                                 label: "remoteConfig",
                                                 attributes: ["fv": "2"], uid: "u-1", createdTime: 42)
        let event = SellwildEvent(failure: failure)
        XCTAssertEqual(event.event, "clientFailure")
        XCTAssertEqual(event.action, "config.fetch.http")
        XCTAssertEqual(event.label, "remoteConfig")
        XCTAssertEqual(event.attributes, ["fv": "2"])
        XCTAssertEqual(event.uid, "u-1")
        XCTAssertEqual(event.createdTime, 42)
    }
}

// fv 2: the call-site stack, the app context and the call-site context.
extension SellwildFailuresTests {

    func testTheStackIsWhereLogWasCalledWithoutTheFailuresFrames() throws {
        capture.stack = [
            "0   SellwildSDK  0x0000000104a20000 $s11SellwildSDK0A8FailuresO3log4code + 120",
            "1   SellwildSDK  0x0000000104a20100 $s11SellwildSDK0A8FailuresO3log4code + 64",
            "2   SellwildSDK  0x0000000104a2c3e4 $s11SellwildSDK0A9APIClientC13fetchListingsyyF + 412",
            "3   UIKitCore    0x00000001850f4a10 -[UIView layoutSubviews] + 140"
        ]
        SellwildFailures.log(code: .listingsFetchHttp, component: .listings, message: "HTTP 503")

        XCTAssertEqual(capture.events.first?.attributes["stack"],
                       "2 SellwildSDK 0x0000000104a2c3e4 $s11SellwildSDK0A9APIClientC13fetchListingsyyF + 412\n"
                       + "3 UIKitCore 0x00000001850f4a10 -[UIView layoutSubviews] + 140")
    }

    func testCallerStackKeepsAtMost30FramesAndNothingWhenOnlyFailuresFramesAreLeft() {
        XCTAssertNil(SellwildFailures.callerStack([]))
        XCTAssertNil(SellwildFailures.callerStack(["0 capture", "1 SellwildFailures.log(code:)"]))
        XCTAssertEqual(SellwildFailures.callerStack(["0 capture", "1 $s16SellwildSDKTests0a8FailuresC4testyyF"]),
                       "1 $s16SellwildSDKTests0a8FailuresC4testyyF", "a caller named Failures is kept")
        let many = (0..<40).map { "\($0) App 0x0 frame\($0)" }
        XCTAssertEqual(SellwildFailures.callerStack(many)?.split(separator: "\n").count, 30)
    }

    func testTheCallSiteContextAndTheSlugAreSent() throws {
        SellwildFailures.setContext { $0.slug = "weatherbug-main" }
        SellwildFailures.log(code: .listingsFetchHttp, component: .listings, message: "HTTP 503",
                             context: ["file": "listings-weatherbug.json", "attempt": 2, "Bad": "x"])

        let attributes = try XCTUnwrap(capture.events.first?.attributes)
        XCTAssertEqual(attributes["ctx.file"], "listings-weatherbug.json")
        XCTAssertEqual(attributes["ctx.attempt"], "2")
        XCTAssertNil(attributes["ctx.Bad"])
        XCTAssertEqual(attributes["slug"], "weatherbug-main")
    }

    func testURLFileName() {
        let listings = "https://cache.sellwild.com/listings-weatherbug.json?v=2#top"
        XCTAssertEqual(SellwildFailures.urlFileName(listings), "listings-weatherbug.json")
        XCTAssertEqual(SellwildFailures.urlFileName("https://cache.sellwild.com/a/b/"), "")
        XCTAssertEqual(SellwildFailures.urlFileName("listings.json"), "listings.json")
        XCTAssertEqual(SellwildFailures.urlFileName("?q"), "")
    }

    func testAppInfoFromTheBundleAndTheSimulator() {
        let info = SellwildAppInfo(bundle: ["CFBundleIdentifier": "com.example", "CFBundleShortVersionString": "6.1"],
                                   osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1,
                                                                     patchVersion: 0),
                                   environment: ["SIMULATOR_MODEL_IDENTIFIER": "iPhone17,1"], machine: "arm64")
        XCTAssertEqual([info.appId, info.appVersion, info.os, info.device], ["com.example", "6.1", "iOS 26.1",
                                                                             "iPhone17,1"])
        let device = SellwildAppInfo(bundle: [:], osVersion: OperatingSystemVersion(majorVersion: 18,
                                                                                    minorVersion: 4, patchVersion: 2),
                                     environment: [:], machine: "iPhone16,2")
        XCTAssertEqual([device.appId, device.appVersion, device.os, device.device], [nil, nil, "iOS 18.4.2",
                                                                                     "iPhone16,2"])
        XCTAssertNotNil(SellwildAppInfo.machineIdentifier())
    }
}

// The live events queue path.
extension SellwildFailuresTests {

    func testLoggedFailuresArePostedThroughTheEventsQueue() throws {
        let transport = CapturingEventTransport()
        let clock = ManualEventClock()
        let client = queueClient(transport, clock)
        client.partnerCode = "weatherbug"
        SellwildFailures.setDependencies(.live(client: client))
        SellwildFailures.setContext { $0.partnerCode = "weatherbug" }
        let actions = { transport.batches.last?.compactMap { $0["action"] as? String } }

        // The queue has already used its own send-at-once on an ordinary
        // event, so only the flush sends the first failure now.
        client.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: "43"))
        client.waitForEventQueue()
        XCTAssertEqual(transport.requests.count, 1)

        SellwildFailures.log(code: .configFetchHttp, component: .remoteConfig, message: "HTTP 403", httpStatus: 403,
                             url: "https://widget.sellwild.com/app/weatherbug/app.json")
        client.waitForEventQueue()
        XCTAssertEqual(transport.requests.count, 2, "the first failure of the session is sent at once")
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.url?.absoluteString, "https://events.sellwild.com/events/queue")
        XCTAssertEqual(request.httpMethod, "POST")
        let event = try XCTUnwrap(transport.batches.last?.first)
        XCTAssertEqual(transport.batches.last?.count, 1)
        XCTAssertEqual(event["event"] as? String, "clientFailure")
        XCTAssertEqual(event["action"] as? String, "config.fetch.http")
        XCTAssertEqual(event["label"] as? String, "remoteConfig")
        XCTAssertEqual(event["uid"] as? String, SellwildSession.shared.uid)
        XCTAssertEqual((event["createdTime"] as? NSNumber)?.int64Value, clock.nowMs)
        var sent = try XCTUnwrap(event["attributes"] as? [String: String])
        // The live dependencies send where log was called: this test.
        let stack = try XCTUnwrap(sent.removeValue(forKey: "stack"))
        // The first frame is this test (mangled: SellwildSDKTests ... FailuresC).
        XCTAssertTrue(stack.split(separator: "\n").first?.contains("SellwildSDKTests") == true, stack)
        XCTAssertEqual(sent, [
            "code": "weatherbug", "client": "ios", "clientVersion": SellwildSDK.sdkVersion, "severity": "error",
            "fv": "2", "msg": "HTTP 403", "httpStatus": "403", "host": "widget.sellwild.com", "seq": "1", "repeat": "1",
            "type": "ios", "sdkVersion": SellwildSDK.sdkVersion
        ].merging(FailureCapture.appAttributes) { $1 })
        try ContractEmitter.emit(jsonData: try XCTUnwrap(request.httpBody), schema: "events-batch",
                                 variant: "ios-log-failure-first")

        // A later failure waits for the 10 s batch timer.
        SellwildFailures.log(code: .configFetchParse, component: .remoteConfig)
        client.waitForEventQueue()
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(clock.pendingCount, 1)
        clock.fire()
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(actions(), ["config.fetch.parse"])

        // A fatal one is sent at once and cancels the timer its push started.
        SellwildFailures.log(code: .configUrlInvalid, component: .configure, severity: .fatal)
        client.waitForEventQueue()
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(actions(), ["config.url.invalid"])
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertEqual(SellwildFailures.internalErrorCount, 0)
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty)
    }
}
