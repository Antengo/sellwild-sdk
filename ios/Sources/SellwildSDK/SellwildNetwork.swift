import Foundation

/// The URLSession every SDK request goes through: config, listings, events and
/// GrowthCode. Explicit timeouts, the closest match to Android's
/// HttpURLConnection (connect 10 s, read 15 s): no data for 15 s ends a
/// request, and no whole transfer runs past 30 s. URLSession has no separate
/// connect timeout.
enum SellwildNetwork {
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 30

    /// The configuration the session is built from (pure).
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    static let session = URLSession(configuration: configuration())
}
