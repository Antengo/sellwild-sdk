import XCTest
import SellwildSDK

/// Emits payloads the SDK itself builds, so `node contracts/scripts/validate.mjs
/// --out ios` (run by `scripts/coverage/ios.sh`) checks real iOS output against
/// the schemas, not just hand-made fixtures. Each body is captured by
/// `StubURLProtocol`, so no request leaves the process.
///
/// Phase-3 tests emit their own variants (factory output, clientFailure
/// events) with `ContractEmitter.emit`.
final class ContractOutputTests: XCTestCase {

    func testEventsQueueBodyIsEmittedForValidation() throws {
        let session = StubURLProtocol.makeSession()
        // Let the in-flight task finish: a cancelled POST would re-queue the
        // batch on the client's 10 s timer.
        defer { session.finishTasksAndInvalidate() }
        let posted = expectation(description: "events POST")
        StubURLProtocol.handler = { _ in
            posted.fulfill()
            return .init(status: 200)
        }
        let client = SellwildAPIClient(session: session)
        client.partnerCode = "sellwild-test"

        // The shape SellwildAdView sends. A new client sends its first event at
        // once instead of waiting for the batch timer.
        client.sendEvent(SellwildEvent(event: "adError", action: "No ad to show.", label: "43"))
        wait(for: [posted], timeout: 10)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/events/queue")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let batch = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?["event"] as? String, "adError")
        XCTAssertEqual(batch.first?["label"] as? String, "43")
        XCTAssertEqual(batch.first?["attributes"] as? [String: String],
                       ["type": "ios", "sdkVersion": SellwildSDK.sdkVersion, "code": "sellwild-test"])

        let file = try ContractEmitter.emit(jsonData: body, schema: "events-batch", variant: "sdk-ad-error")
        XCTAssertEqual(file.standardizedFileURL,
                       ContractEmitter.outputDirectory().appendingPathComponent("events-batch.sdk-ad-error.json").standardizedFileURL)
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty, "the stub session never reaches the blocker")
    }
}
