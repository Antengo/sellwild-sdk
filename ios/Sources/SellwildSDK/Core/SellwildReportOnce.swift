import Foundation

/// Remembers the config problems already reported this launch, so a bad value
/// that stays in the config is reported once (FAILURES.md 9.1), not on every
/// read. Config values are read on every ad load, feed load and refresh;
/// without this latch the dedupe gate (a few events per key per minute) would
/// be the only brake.
///
///     if SellwildReportOnce.first(.growthcodeConfigMissing) {
///         SellwildFailures.log(code: .growthcodeConfigMissing, ...)
///     }
enum SellwildReportOnce {

    private static let lock = NSLock()
    private static var seen = Set<String>()

    /// true the first time this launch that `code` is seen with `scope`, false
    /// after that. `scope` tells two problems with the same code apart (a
    /// zone, a state, the message).
    static func first(_ code: SellwildFailureCode, _ scope: String = "") -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seen.insert("\(code.rawValue)|\(scope)").inserted
    }

    /// Forgets every problem, as a new launch would. Tests call it between cases.
    static func resetForTests() {
        lock.lock()
        seen.removeAll()
        lock.unlock()
    }
}
