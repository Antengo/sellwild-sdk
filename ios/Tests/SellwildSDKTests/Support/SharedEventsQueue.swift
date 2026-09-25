import Foundation
@testable import SellwildSDK

/// Keeps the SDK's shared events queue (`SellwildAPIClient.shared`) off the
/// network for the whole test process, and empties it before every test.
///
/// Code on a live environment queues its events there: `SellwildFailures`
/// after `resetForTests()`, and the views' `.live` environments. So does work
/// a test left running that ends after its tearDown, such as a listing photo
/// that fails to download and is reported. The real queue posts over
/// `URLSession.shared`. `NetworkBlocker` fails that post, and the queue then
/// keeps the batch and retries it every 10 s, so one late report failed a test
/// at random each time the retry fired (CI run of PR #84).
///
/// `install()` points the shared queue at `sink`, which records each batch
/// and answers 204, so nothing is retried and nothing reaches the network.
/// `NetworkBlocker.install` calls it, and its observer calls `drain()`
/// before every test.
enum SharedEventsQueue {

    private static let lock = NSLock()
    private static var sent: [URLRequest] = []

    /// Records the batch and answers 204.
    static let sink = SellwildEventTransport { request, completion in
        locked { sent.append(request) }
        completion(204, nil)
    }

    /// Sends the shared queue's batches to `sink`. Safe to call repeatedly.
    static func install() {
        let client = SellwildAPIClient.shared
        client.eventQueue.sync { client.eventTransport = sink }
    }

    /// Sends what the shared queue holds to `sink` now, which also cancels its
    /// flush timer, and returns every batch `sink` took since the last drain,
    /// oldest first.
    @discardableResult
    static func drain() -> [URLRequest] {
        SellwildAPIClient.shared.flushEvents()
        SellwildAPIClient.shared.waitForEventQueue()
        return locked {
            defer { sent = [] }
            return sent
        }
    }

    private static func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
