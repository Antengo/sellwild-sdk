import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import SellwildSDK

/// The batching events queue in SellwildAPIClient, driven through an injected
/// transport (captures each POST) and a manual clock (the 10 s batch timer).
/// Nothing here reaches the network.
final class SellwildEventQueueTests: XCTestCase {

    private var transport: CapturingEventTransport!
    private var clock: ManualEventClock!
    private var client: SellwildAPIClient!

    private enum Outage: Error { case down }

    override func setUp() {
        super.setUp()
        transport = CapturingEventTransport()
        clock = ManualEventClock()
        client = SellwildAPIClient(session: StubURLProtocol.makeSession(),
                                   eventTransport: transport.transport, eventClock: clock.clock)
    }

    override func tearDown() {
        client = nil
        clock = nil
        transport = nil
        SellwildFailures.resetForTests()
        super.tearDown()
    }

    private func send(_ labels: [String]) {
        for label in labels { client.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: label)) }
        client.waitForEventQueue()
    }

    private func labels(_ range: ClosedRange<Int>) -> [String] {
        range.map { "z\($0)" }
    }

    // MARK: Batching

    func testFirstEventIsPostedAtOnceAndStamped() throws {
        client.partnerCode = "weatherbug"
        send(["43"])

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://events.sellwild.com/events/queue")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let event = try XCTUnwrap(transport.batches.first?.first)
        XCTAssertEqual(event["event"] as? String, "adRenderSucceeded")
        XCTAssertEqual(event["label"] as? String, "43")
        XCTAssertEqual(event["attributes"] as? [String: String],
                       ["type": "ios", "sdkVersion": SellwildSDK.sdkVersion, "code": "weatherbug"])
        XCTAssertTrue(clock.scheduledDelays.isEmpty)
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty)
    }

    func testCallerAttributesAreKeptAndReservedKeysWin() throws {
        client.sendEvent(SellwildEvent(event: "custom", attributes: ["type": "spoof", "extra": "kept"]))
        client.waitForEventQueue()
        let attributes = try XCTUnwrap(transport.batches.first?.first?["attributes"] as? [String: String])
        XCTAssertEqual(attributes, ["type": "ios", "sdkVersion": SellwildSDK.sdkVersion, "extra": "kept"],
                       "no partner code set: attributes.code is left out")
    }

    func testLaterEventsWaitForTheBatchTimer() {
        send(labels(1...3))
        XCTAssertEqual(transport.labels, ["z1"])
        XCTAssertEqual(clock.scheduledDelays, [10], "one 10 s timer for the whole batch")

        clock.fire()
        XCTAssertEqual(transport.batches.map(\.count), [1, 2])
        XCTAssertEqual(transport.labels, ["z1", "z2", "z3"])

        // An empty queue sends nothing, even when flushed.
        client.flushEvents()
        client.waitForEventQueue()
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testAFullBatchIsSentWithoutTheTimer() {
        send(labels(1...101))
        XCTAssertEqual(transport.batches.map(\.count), [1, 100])
        XCTAssertEqual(clock.pendingCount, 0, "sending the batch cancels its timer")
    }

    func testFlushEventsSendsNowAndCancelsTheTimer() {
        send(labels(1...2))
        XCTAssertEqual(clock.pendingCount, 1)
        client.flushEvents()
        client.waitForEventQueue()
        XCTAssertEqual(transport.labels, ["z1", "z2"])
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testKillSwitchDropsEvents() {
        client.eventsEnabled = false
        send(["43"])
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(clock.scheduledDelays.isEmpty)
    }

    func testClientFailureKeepsTheCodeLogFailureSet() throws {
        // A partner code over the 64 the contract allows on a clientFailure.
        let long = String(repeating: "p", count: 70)
        client.partnerCode = long
        let decision = SellwildFailuresCore.decide(
            state: .init(), input: .init(code: "config.fetch.http", component: "remoteConfig"),
            context: .init(partnerCode: long, client: "ios", clientVersion: SellwildSDK.sdkVersion),
            uid: FailureCapture.uid, now: FailureCapture.now
        )
        let event = try XCTUnwrap(decision.event)
        let logged = try XCTUnwrap(event.attributes["code"])
        XCTAssertEqual(logged.unicodeScalars.count, 64)
        client.sendEvent(SellwildEvent(failure: event))
        client.waitForEventQueue()
        let failure = try XCTUnwrap(transport.batches.first?.first?["attributes"] as? [String: String])
        XCTAssertEqual(failure["code"], logged)
        XCTAssertEqual(failure["type"], "ios")
        try ContractEmitter.emit(jsonData: try XCTUnwrap(transport.requests.first?.httpBody),
                                 schema: "events-batch", variant: "ios-queue-client-failure-long-code")

        // Every other event gets the queue's code, and so would a
        // clientFailure without one.
        client.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: "43"))
        client.sendEvent(SellwildEvent(event: "clientFailure", action: "config.fetch.http", label: "remoteConfig"))
        client.flushEvents()
        client.waitForEventQueue()
        XCTAssertEqual(transport.batches.last?.map { ($0["attributes"] as? [String: String])?["code"] }, [long, long])
    }

    func testSettingsMayChangeOnAnyThread() {
        // configure sets these off the main thread while events are sent.
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            client.partnerCode = "p\(i % 2)"
            client.eventsEnabled = true
            client.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: "z\(i)"))
        }
        client.flushEvents()
        client.waitForEventQueue()
        let codes = transport.batches.flatMap { $0.map { ($0["attributes"] as? [String: String])?["code"] } }
        XCTAssertEqual(codes.count, 100)
        XCTAssertEqual(Set(codes), ["p0", "p1"])
        XCTAssertTrue(client.eventsEnabled)
    }

    // MARK: Failures of the transport

    func testFailedBatchIsRequeuedAndRetriedOnTheTimer() {
        transport.error = Outage.down
        send(["z1"])
        XCTAssertEqual(transport.labels, ["z1"])
        client.waitForEventQueue()  // the requeue hop
        XCTAssertEqual(clock.pendingCount, 1, "a failed send schedules a retry")

        transport.error = nil
        clock.fire()
        XCTAssertEqual(transport.labels, ["z1", "z1"], "the same event, sent again")
    }

    func testQueueIsCappedAtTheNewest1000() {
        // One event at a time, each failed batch back in the queue before the
        // next event, so the queue is full when the last events arrive.
        transport.error = Outage.down
        for label in labels(1...1_005) {
            send([label])
            client.waitForEventQueue()
        }

        transport.error = nil
        let failed = transport.batches.reduce(0) { $0 + $1.count }
        for _ in 0..<12 {
            client.flushEvents()
            client.waitForEventQueue()
        }
        let delivered = Array(transport.labels.dropFirst(failed))
        XCTAssertEqual(delivered, labels(6...1_005), "the oldest five are dropped, order is kept")
    }

    func testRequeueDropsTheOldestWhenNewEventsFilledTheQueue() {
        // Requeues that land after a burst of new events: how many are kept
        // is fixed, which ones depends on the interleaving.
        transport.error = Outage.down
        send(labels(1...1_205))
        client.waitForEventQueue()

        transport.error = nil
        let failed = transport.batches.reduce(0) { $0 + $1.count }
        for _ in 0..<12 {
            client.flushEvents()
            client.waitForEventQueue()
        }
        let delivered = Array(transport.labels.dropFirst(failed))
        XCTAssertEqual(delivered.count, 1_000)
        XCTAssertEqual(Set(delivered).count, 1_000)
    }

    func testTransportAnswerAfterTheClientIsGoneIsIgnored() {
        transport.holdCompletions = true
        send(["z1"])
        XCTAssertEqual(transport.requests.count, 1)

        weak var released: SellwildAPIClient?
        released = client
        client = nil
        XCTAssertNil(released, "the queue does not keep the client alive")
        transport.completePending(with: Outage.down)
    }

    // MARK: Lifecycle

    #if canImport(UIKit)
    func testBackgroundingTheAppFlushesTheQueue() {
        send(labels(1...2))
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        client.waitForEventQueue()
        XCTAssertEqual(transport.labels, ["z1", "z2"])
    }
    #endif

    // MARK: Transport never reports itself (A7)

    func testTransportFailuresNeverReachLogFailure() {
        SellwildFailures.resetForTests()
        let capture = FailureCapture()
        capture.install()

        transport.error = Outage.down
        send(labels(1...150))
        clock.fire()
        client.flushEvents()
        client.waitForEventQueue()
        client.waitForEventQueue()
        XCTAssertGreaterThan(transport.requests.count, 2)

        XCTAssertTrue(capture.events.isEmpty)
        XCTAssertEqual(SellwildFailures.coreState, SellwildFailuresCore.State(), "log was never called")
    }

    func testTransportSourceNeverCallsLogFailure() throws {
        let source = try String(contentsOf: Fixtures.repoRoot.appendingPathComponent("ios/Sources/SellwildSDK/SellwildAPI.swift"),
                                encoding: .utf8)
        for name in ["func sendEvent(", "func flushEvents(", "func flushEventsLocked(", "func scheduleEventFlushLocked(",
                     "func stampEvent(", "struct SellwildEventTransport", "struct SellwildEventClock"] {
            let body = try XCTUnwrap(Self.body(of: name, in: source), name)
            XCTAssertFalse(body.contains("SellwildFailures"), "\(name) must not report failures (FAILURES.md 8.4)")
        }
    }

    /// The text of the declaration starting at `name`, through its matching brace.
    private static func body(of name: String, in source: String) -> String? {
        guard let start = source.range(of: name) else { return nil }
        var depth = 0
        var opened = false
        for index in source[start.lowerBound...].indices {
            switch source[index] {
            case "{": depth += 1; opened = true
            case "}": depth -= 1
            default: break
            }
            if opened && depth == 0 { return String(source[start.lowerBound...index]) }
        }
        return nil
    }

    // MARK: Seams

    func testDefaultTransportUsesTheSession() {
        let session = StubURLProtocol.makeSession()
        defer { session.finishTasksAndInvalidate() }
        let answered = expectation(description: "stub answered")
        StubURLProtocol.handler = { _ in
            answered.fulfill()
            return .init(status: 503)
        }
        var request = URLRequest(url: URL(string: "https://events.invalid/events/queue")!)
        request.httpMethod = "POST"
        let done = expectation(description: "completion")
        SellwildEventTransport.session(session).send(request) { error in
            XCTAssertNil(error, "HTTP errors are not transport errors")
            done.fulfill()
        }
        wait(for: [answered, done], timeout: 10)
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "POST")
    }

    func testSystemClock() {
        let now = SellwildEventClock.system.now()
        XCTAssertLessThan(abs(now - Int64(Date().timeIntervalSince1970 * 1000)), 60_000)

        let queue = DispatchQueue(label: "com.sellwild.tests.clock")
        let fired = expectation(description: "timer fired")
        // The returned closure owns the timer, as the client's does.
        let keep = SellwildEventClock.system.schedule(0.01, queue) { fired.fulfill() }
        let cancelled = expectation(description: "cancelled timer never fires")
        cancelled.isInverted = true
        let cancel = SellwildEventClock.system.schedule(0.01, queue) { cancelled.fulfill() }
        cancel()
        wait(for: [fired, cancelled], timeout: 1)
        keep()
    }

    func testPublicInitKeepsTheSharedDefaults() {
        let plain = SellwildAPIClient()
        XCTAssertLessThan(abs(plain.eventClock.now() - Int64(Date().timeIntervalSince1970 * 1000)), 60_000)
        XCTAssertEqual(client.eventClock.now(), clock.nowMs)
    }
}
