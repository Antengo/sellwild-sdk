import XCTest
@testable import SellwildSDK

/// Event batches are re-queued on network errors and retryable statuses;
/// permanent 4xx rejections are dropped.
final class SellwildEventRetryTests: XCTestCase {

    func testSuccessIsNotRetried() {
        XCTAssertFalse(SellwildAPIClient.shouldRetryEventBatch(statusCode: 200, error: nil))
        XCTAssertFalse(SellwildAPIClient.shouldRetryEventBatch(statusCode: 204, error: nil))
    }

    func testNetworkErrorIsRetried() {
        XCTAssertTrue(SellwildAPIClient.shouldRetryEventBatch(statusCode: nil, error: URLError(.notConnectedToInternet)))
        XCTAssertTrue(SellwildAPIClient.shouldRetryEventBatch(statusCode: nil, error: nil))
    }

    func testServerErrorsAndTransient4xxAreRetried() {
        XCTAssertTrue(SellwildAPIClient.shouldRetryEventBatch(statusCode: 500, error: nil))
        XCTAssertTrue(SellwildAPIClient.shouldRetryEventBatch(statusCode: 503, error: nil))
        XCTAssertTrue(SellwildAPIClient.shouldRetryEventBatch(statusCode: 408, error: nil))
        XCTAssertTrue(SellwildAPIClient.shouldRetryEventBatch(statusCode: 429, error: nil))
    }

    func testPermanent4xxIsDropped() {
        XCTAssertFalse(SellwildAPIClient.shouldRetryEventBatch(statusCode: 400, error: nil))
        XCTAssertFalse(SellwildAPIClient.shouldRetryEventBatch(statusCode: 403, error: nil))
        XCTAssertFalse(SellwildAPIClient.shouldRetryEventBatch(statusCode: 413, error: nil))
    }
}
