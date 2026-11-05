import XCTest
@testable import SellwildSDK

/// How a URL load ended, as every reporting fetch reads it: the HTTP status
/// that counts as a failure (outside 2xx, edges included) and what a
/// transport error means.
final class SellwildLoadFailureTests: XCTestCase {

    private let url = URL(string: "https://cache.sellwild.com/listings-img-data-sm")!

    private func http(_ status: Int) -> HTTPURLResponse? {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
    }

    func testHTTPFailureStatusIsEveryStatusOutside2xx() {
        let table: [(Int, Int?)] = [
            (100, 100), (199, 199), (200, nil), (204, nil), (299, nil), (300, 300), (304, 304), (403, 403), (404, 404), (500, 500),
        ]
        for (status, expected) in table {
            XCTAssertEqual(SellwildLoadFailure.httpFailureStatus(http(status)), expected, "HTTP \(status)")
        }
    }

    func testAResponseThatIsNotHTTPHasNoStatusToJudge() {
        let plain = URLResponse(url: url, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil)
        XCTAssertNil(SellwildLoadFailure.httpFailureStatus(plain))
        XCTAssertNil(SellwildLoadFailure.httpFailureStatus(nil))
    }

    func testTransportErrors() {
        let table: [(Error, SellwildLoadFailure.Transport)] = [
            (URLError(.cancelled), .cancelled),
            (URLError(.timedOut), .timeout),
            (URLError(.notConnectedToInternet), .network),
            (URLError(.cannotFindHost), .network),
            (URLError(.secureConnectionFailed), .network),
            (NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut), .timeout),
            (NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled), .cancelled),
            (PlannedError(), .network),
        ]
        for (error, expected) in table {
            XCTAssertEqual(SellwildLoadFailure.transport(error), expected, "\(error)")
        }
    }
}
