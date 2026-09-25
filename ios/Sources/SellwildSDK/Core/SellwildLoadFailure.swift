import Foundation

/// How a URL load ended, for the fetches that report failures (remote config,
/// listings, the localized cache, GrowthCode, house images). Pure: it only
/// looks at the values a completion handler gets.
enum SellwildLoadFailure {

    /// What a transport error means for reporting.
    enum Transport: Equatable {
        /// The caller cancelled the load. Not a failure (FAILURES.md 4.3).
        case cancelled
        /// The request did not answer within its timeout.
        case timeout
        /// Any other network-level failure: DNS, offline, TLS, reset.
        case network
    }

    static func transport(_ error: Error) -> Transport {
        switch (error as? URLError)?.code {
        case .cancelled?: return .cancelled
        case .timedOut?: return .timeout
        default: return .network
        }
    }

    /// The status of an HTTP response outside 2xx, else nil. A response that
    /// is not HTTP (a custom protocol) has no status to judge, so it is nil.
    static func httpFailureStatus(_ response: URLResponse?) -> Int? {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return nil }
        return http.statusCode
    }
}
