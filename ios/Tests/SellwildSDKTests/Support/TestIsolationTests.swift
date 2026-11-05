import XCTest
@testable import SellwildSDK

/// Self-tests for what the test process does so one test's leftovers cannot
/// fail another: the shared events queue sends to a stub, and the stub tasks
/// a test leaves open are cancelled when it ends. Every URL here uses the
/// reserved `.invalid` TLD.
final class TestIsolationTests: XCTestCase {

    private var eventsWereEnabled = true

    override func setUp() {
        super.setUp()
        // An earlier test may have run a live configure that turned events off.
        eventsWereEnabled = SellwildAPIClient.shared.eventsEnabled
        SellwildAPIClient.shared.eventsEnabled = true
    }

    override func tearDown() {
        SellwildAPIClient.shared.eventsEnabled = eventsWereEnabled
        SellwildFailures.resetForTests()
        super.tearDown()
    }

    private func events(_ batches: [URLRequest]) -> [[String: Any]] {
        batches.flatMap { request in
            (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
        }
    }

    // MARK: Shared events queue

    func testTheSharedEventsQueueSendsToTheStubNotTheNetwork() throws {
        SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: "isolation"))
        let batches = SharedEventsQueue.drain()

        XCTAssertEqual(events(batches).compactMap { $0["label"] as? String }, ["isolation"])
        let request = try XCTUnwrap(batches.first)
        XCTAssertEqual(request.url?.absoluteString, "https://events.sellwild.com/events/queue")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty, "nothing reached URLSession.shared")
        XCTAssertTrue(SharedEventsQueue.drain().isEmpty, "a drain returns each batch once")
    }

    func testAFailureReportedOnLiveDependenciesGoesToTheStub() {
        // What failed CI: a photo download a test left running failed after
        // tearDown reset SellwildFailures to its live dependencies.
        SellwildFailures.resetForTests()
        SellwildFailures.log(code: .feedImageNetwork, component: .feed, severity: .warn, message: "late photo")

        let sent = events(SharedEventsQueue.drain())
        XCTAssertEqual(sent.compactMap { $0["action"] as? String }, ["feed.image.network"])
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty)
    }

    func testTheStubAnswers204SoNoBatchIsKeptForARetry() {
        var answer: (Int?, Error?)?
        var request = URLRequest(url: URL(string: "https://events.invalid/events/queue")!)
        request.httpMethod = "POST"
        SharedEventsQueue.sink.send(request) { status, error in answer = (status, error) }

        XCTAssertEqual(answer?.0, 204)
        XCTAssertNil(answer?.1)
        XCTAssertFalse(SellwildAPIClient.shouldRetryEventBatch(statusCode: answer?.0, error: answer?.1))
        XCTAssertEqual(SharedEventsQueue.drain().map(\.url), [request.url])
    }

    func testInstallIsSafeToRepeat() {
        SharedEventsQueue.install()
        SellwildAPIClient.shared.sendEvent(SellwildEvent(event: "adRenderSucceeded", label: "again"))
        XCTAssertEqual(events(SharedEventsQueue.drain()).compactMap { $0["label"] as? String }, ["again"])
    }

    // MARK: Stub tasks a test leaves open

    func testCancelRunningTasksCancelsATaskTheStubHasNotAnswered() {
        let session = StubURLProtocol.makeSession()
        let entered = expectation(description: "stub started")
        let release = DispatchSemaphore(value: 0)
        // The stub holds the answer until the task has ended, as a download
        // still open when a test ends has none yet.
        StubURLProtocol.handler = { _ in
            entered.fulfill()
            _ = release.wait(timeout: .now() + 10)
            return .init(status: 200)
        }
        let done = expectation(description: "task finished")
        var failure: Error?
        let task = session.dataTask(with: URL(string: "https://stub.invalid/left-open.png")!) { _, _, error in
            failure = error
            done.fulfill()
        }
        task.resume()
        wait(for: [entered], timeout: 10)

        StubURLProtocol.cancelRunningTasks()
        wait(for: [done], timeout: 10)
        release.signal()

        XCTAssertEqual((failure as? URLError)?.code, .cancelled)
        XCTAssertEqual(SellwildLoadFailure.transport(failure ?? URLError(.unknown)), .cancelled,
                       "the SDK reads it as cancelled, which it never reports")
    }

    func testCancelRunningTasksLeavesAnsweredTasksAndLaterSessionsAlone() throws {
        let session = StubURLProtocol.makeSession()
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("ok".utf8)) }
        let first = expectation(description: "first request")
        var body: Data?
        session.dataTask(with: URL(string: "https://stub.invalid/answered")!) { data, _, _ in
            body = data
            first.fulfill()
        }.resume()
        wait(for: [first], timeout: 10)

        StubURLProtocol.cancelRunningTasks()
        XCTAssertEqual(body, Data("ok".utf8))

        // The session still works, and is no longer tracked: a second call
        // does not cancel what it runs now.
        StubURLProtocol.cancelRunningTasks()
        let second = expectation(description: "second request")
        var error: Error?
        session.dataTask(with: URL(string: "https://stub.invalid/after")!) { _, _, failure in
            error = failure
            second.fulfill()
        }.resume()
        wait(for: [second], timeout: 10)
        XCTAssertNil(error)
        XCTAssertEqual(StubURLProtocol.requests.map(\.url?.path), ["/answered", "/after"])
    }

    func testCancelRunningTasksReturnsForInvalidatedSessions() {
        // Many tests invalidate their session before they end.
        StubURLProtocol.makeSession().invalidateAndCancel()
        StubURLProtocol.makeSession().finishTasksAndInvalidate()
        let returned = expectation(description: "cancelRunningTasks returned")
        DispatchQueue.global().async {
            StubURLProtocol.cancelRunningTasks()
            returned.fulfill()
        }
        wait(for: [returned], timeout: 5)
    }
}
