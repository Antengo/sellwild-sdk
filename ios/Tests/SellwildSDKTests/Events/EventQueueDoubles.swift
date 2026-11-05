import Foundation
@testable import SellwildSDK

/// An events transport that records each batch POST instead of sending it.
/// Answers at once (on the client's queue) with `status` and `error`.
final class CapturingEventTransport {

    private let lock = NSLock()
    private var sent: [URLRequest] = []
    private var pending: [(Int?, Error?) -> Void] = []

    /// The HTTP status each send reports; nil is no response.
    var status: Int? = 200
    /// The transport error each send reports. nil is none.
    var error: Error?
    /// Keep the completions instead of calling them (`completePending`).
    var holdCompletions = false

    /// What one send answers, read under the lock.
    private struct Answer {
        let hold: Bool
        let status: Int?
        let error: Error?
    }

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
            let answer = self.locked { () -> Answer in
                self.sent.append(request)
                if self.holdCompletions { self.pending.append(completion) }
                return Answer(hold: self.holdCompletions, status: self.status, error: self.error)
            }
            if !answer.hold { completion(answer.error == nil ? answer.status : nil, answer.error) }
        }
    }

    func completePending(with error: Error?, status: Int? = 200) {
        let completions = locked { () -> [(Int?, Error?) -> Void] in
            defer { pending = [] }
            return pending
        }
        completions.forEach { $0(error == nil ? status : nil, error) }
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
