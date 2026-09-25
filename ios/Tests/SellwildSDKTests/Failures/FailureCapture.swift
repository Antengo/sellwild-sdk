import Foundation
@testable import SellwildSDK

/// Dependencies for `SellwildFailures` that record instead of sending:
///
///     let capture = FailureCapture()
///     capture.install()           // SellwildFailures.setDependencies(capture.dependencies)
///     SellwildFailures.log(...)
///     capture.events              // what would have been queued
///     capture.calls               // every log call, dropped ones included
///
/// Call `SellwildFailures.resetForTests()` in tearDown.
final class FailureCapture {

    static let uid = "8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11"
    static let now: Int64 = 1_790_000_000_000

    private let lock = NSLock()
    private var pushed: [SellwildFailuresCore.Event] = []
    private var flushCount = 0
    private var lines: [String] = []
    private var callCount = 0

    /// Thrown by push (or flush) when set.
    var pushError: Error?
    var flushError: Error?
    /// Runs inside push, before it records.
    var onPush: ((SellwildFailuresCore.Event) -> Void)?
    var clock: Int64 = FailureCapture.now

    var events: [SellwildFailuresCore.Event] { locked { pushed } }
    var flushes: Int { locked { flushCount } }
    var echoes: [String] { locked { lines } }
    /// How many times `SellwildFailures.log` ran with this capture installed,
    /// including calls the pure core dropped (deduped, capped, sampled out or
    /// disabled). `log` reads the uid once per call, so this counts those reads.
    var calls: Int { locked { callCount } }

    var dependencies: SellwildFailures.Dependencies {
        SellwildFailures.Dependencies(
            now: { [self] in self.locked { self.clock } },
            uid: { [self] in
                self.locked { self.callCount += 1 }
                return FailureCapture.uid
            },
            push: { [self] event in
                self.onPush?(event)
                if let error = self.pushError { throw error }
                self.locked { self.pushed.append(event) }
            },
            flush: { [self] in
                if let error = self.flushError { throw error }
                self.locked { self.flushCount += 1 }
            },
            echo: { [self] line in self.locked { self.lines.append(line) } }
        )
    }

    func install() {
        SellwildFailures.setDependencies(dependencies)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
