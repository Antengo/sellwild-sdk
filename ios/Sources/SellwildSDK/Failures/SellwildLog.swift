import Foundation

/// Debug trace for things that are not failures (failures go to
/// `SellwildFailures.log`). Every call is a no-op unless the SDK debug flag
/// is on; `SellwildSDK.configure` sets it from `SellwildConfig.debug`.
///
///     SellwildLog.debug("[SellwildPrebidMobile] bootstrap done")
///
/// This and the `SellwildFailures` debug echo are the only places in the SDK
/// allowed to print.
public enum SellwildLog {

    private static let lock = NSLock()
    private static var enabled = false
    private static let printLine: (String) -> Void = { print($0) }
    private static var write = printLine

    /// On when the SDK debug flag is on.
    public static var isEnabled: Bool {
        get { locked { enabled } }
        set { locked { enabled = newValue } }
    }

    /// Prints `message` when debug is on. The message is not built otherwise.
    public static func debug(_ message: @autoclosure () -> String) {
        let (on, output) = locked { (enabled, write) }
        guard on else { return }
        output(message())
    }

    /// Replaces where lines go (tests capture them); nil restores `print`.
    static func setOutput(_ output: ((String) -> Void)?) {
        locked { write = output ?? printLine }
    }

    private static func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
