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
            "fv": "1", "msg": "HTTP 503", "httpStatus": "503", "host": "cache.sellwild.com", "zoneId": "43",
            "seq": "1", "repeat": "1",
        ])
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
        XCTAssertEqual(capture.echoes, ["[Sellwild] failure listings.fetch.network listings error failures_disabled offline"])

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
        XCTAssertEqual(capture.echoes, ["[Sellwild] failure config.fetch.http remoteConfig warn sent HTTP 403 from widget.sellwild.com"])
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
        XCTAssertEqual(capture.echoes.last?.hasPrefix("[Sellwild] failure internal Boom "), true, capture.echoes.last ?? "")

        SellwildFailures.resetForTests()
        XCTAssertEqual(SellwildFailures.internalErrorCount, 0)
    }

    func testConcurrentCallsKeepTheSessionCap() {
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            SellwildFailures.log(code: .feedImageNetwork, component: .feed, message: "image \(i)")
        }
        XCTAssertEqual(capture.events.count, SellwildFailuresCore.Limits.sessionEmits)
        XCTAssertEqual(Set(capture.events.compactMap { $0.attributes["seq"] }).count, SellwildFailuresCore.Limits.sessionEmits)
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
        SellwildAPIClient(session: StubURLProtocol.makeSession(), eventTransport: transport.transport, eventClock: clock.clock)
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
        XCTAssertEqual(event["attributes"] as? [String: String], [
            "code": "weatherbug", "client": "ios", "clientVersion": SellwildSDK.sdkVersion, "severity": "error",
            "fv": "1", "msg": "HTTP 403", "httpStatus": "403", "host": "widget.sellwild.com", "seq": "1", "repeat": "1",
            "type": "ios", "sdkVersion": SellwildSDK.sdkVersion,
        ])
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

    func testQueueEventKeepsTheFailureUidAndTime() {
        let failure = SellwildFailuresCore.Event(event: "clientFailure", action: "config.fetch.http", label: "remoteConfig",
                                                 attributes: ["fv": "1"], uid: "u-1", createdTime: 42)
        let event = SellwildEvent(failure: failure)
        XCTAssertEqual(event.event, "clientFailure")
        XCTAssertEqual(event.action, "config.fetch.http")
        XCTAssertEqual(event.label, "remoteConfig")
        XCTAssertEqual(event.attributes, ["fv": "1"])
        XCTAssertEqual(event.uid, "u-1")
        XCTAssertEqual(event.createdTime, 42)
    }
}
