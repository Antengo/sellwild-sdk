import XCTest
@testable import SellwildSDK

/// origin 81e762d: a batch answered with a retryable HTTP status goes back to
/// the queue like a transport error; a permanent 4xx is dropped. Driven
/// through the injected transport and manual clock, as SellwildEventQueueTests.
final class SellwildEventStatusRetryTests: XCTestCase {

    private var transport: CapturingEventTransport!
    private var clock: ManualEventClock!
    private var client: SellwildAPIClient!

    override func setUp() {
        super.setUp()
        makeClient()
    }

    /// A fresh client, transport and clock.
    private func makeClient() {
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

    private func send(_ label: String) {
        client.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: label))
        client.waitForEventQueue()
        client.waitForEventQueue()  // the requeue hop
    }

    func testARetryableStatusPutsTheBatchBackAndTheTimerSendsItAgain() {
        for status in [503, 408, 429] {
            makeClient()
            transport.status = status
            send("s\(status)")
            XCTAssertEqual(clock.pendingCount, 1, "\(status) schedules a retry")
            transport.status = 200
            clock.fire()
            client.waitForEventQueue()
            XCTAssertEqual(transport.labels, ["s\(status)", "s\(status)"], "\(status): the same event again")
        }
    }

    func testAPermanent4xxDropsTheBatch() {
        transport.status = 400
        send("bad")
        XCTAssertEqual(clock.pendingCount, 0, "no retry for a 400")
        transport.status = 200
        client.flushEvents()
        client.waitForEventQueue()
        XCTAssertEqual(transport.labels, ["bad"], "the rejected batch is not sent again")
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty)
    }
}
