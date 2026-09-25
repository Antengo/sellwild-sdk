import Foundation

/// Something scheduled that can still be called off.
protocol SellwildScheduled: AnyObject {
    func cancel()
}

/// Runs work once, later. The ad view's refresh and cold-start timers go
/// through it, so tests can fire them by hand instead of waiting.
protocol SellwildScheduler {
    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> SellwildScheduled
}

/// The real scheduler: a one-shot `Timer` on the main run loop in `.common`
/// mode, so a due refresh still fires while a table view is scrolling
/// (default-mode timers pause during scroll tracking).
struct SellwildRunLoopScheduler: SellwildScheduler {
    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> SellwildScheduled {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in work() }
        RunLoop.main.add(timer, forMode: .common)
        return ScheduledTimer(timer: timer)
    }

    /// Cancelling invalidates the timer.
    final class ScheduledTimer: SellwildScheduled {
        let timer: Timer

        init(timer: Timer) {
            self.timer = timer
        }

        func cancel() {
            timer.invalidate()
        }
    }
}
