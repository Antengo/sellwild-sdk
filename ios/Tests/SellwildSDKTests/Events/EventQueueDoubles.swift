import Foundation
@testable import SellwildSDK

/// An events transport that records each batch POST instead of sending it.
/// Answers at once (on the client's queue) with `error`, or nil.
final class CapturingEventTransport {

    private let lock = NSLock()
    private var sent: [URLRequest] = []
    private var pending: [(Error?) -> Void] = []

    /// What each send reports. nil is success.
    var error: Error?
    /// Keep the completions instead of calling them (`completePending`).
    var holdCompletions = false

    var requests: [URLRequest] { locked { sent } }

    /// The events of every batch, in send order.
    var batches: [[[String: Any]]] {
        requests.map { request in
            (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
        }
    }

    /// Labels of every event sent, in order.
    var labels: [String] {
        batches.flatMap { $0.compactMap { $0["label"] as? String } }
    }

    var transport: SellwildEventTransport {
        SellwildEventTransport { [self] request, completion in
            let (hold, error) = self.locked { () -> (Bool, Error?) in
                self.sent.append(request)
                if self.holdCompletions { self.pending.append(completion) }
                return (self.holdCompletions, self.error)
            }
            if !hold { completion(error) }
        }
    }

    func completePending(with error: Error?) {
        let completions = locked { () -> [(Error?) -> Void] in
            defer { pending = [] }
            return pending
        }
        completions.forEach { $0(error) }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// An events clock that never fires on its own: `fire()` runs what is due.
final class ManualEventClock {

    private struct Item {
        let delay: TimeInterval
        let queue: DispatchQueue
        let work: () -> Void
        var cancelled = false
    }

    private let lock = NSLock()
    private var items: [Item] = []
    var nowMs: Int64 = 1_790_000_000_000

    /// Delays of every timer scheduled so far.
    var scheduledDelays: [TimeInterval] { locked { items.map(\.delay) } }
    /// Timers scheduled and not yet fired or cancelled.
    var pendingCount: Int { locked { items.filter { !$0.cancelled }.count } }

    var clock: SellwildEventClock {
        SellwildEventClock(
            now: { [self] in self.locked { self.nowMs } },
            schedule: { [self] delay, queue, work in
                let index = self.locked { () -> Int in
                    self.items.append(Item(delay: delay, queue: queue, work: work))
                    return self.items.count - 1
                }
                return { self.locked { self.items[index].cancelled = true } }
            }
        )
    }

    /// Runs every pending timer on its queue and waits for it.
    func fire() {
        let due = locked { () -> [Item] in
            let due = items.filter { !$0.cancelled }
            for i in items.indices { items[i].cancelled = true }
            return due
        }
        for item in due { item.queue.sync(execute: item.work) }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
