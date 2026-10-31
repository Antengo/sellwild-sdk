import Foundation
import UIKit
#if canImport(MetricKit)
import MetricKit
#endif

extension NSLock {
    /// `body` under the lock (NSLocking.withLock needs iOS 16).
    func locked<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

/// Sellwild views in a window now, for the memory report.
enum SellwildViews {
    private static let lock = NSLock()
    private static var counts = (ad: 0, feed: 0)

    static var adViews: Int { lock.locked { counts.ad } }
    static var feedViews: Int { lock.locked { counts.feed } }

    static func adView(attached: Bool) {
        lock.locked { counts.ad += attached ? 1 : -1 }
    }

    static func feedView(attached: Bool) {
        lock.locked { counts.feed += attached ? 1 : -1 }
    }

    static func resetForTests() {
        lock.locked { counts = (0, 0) }
    }
}

/// The process-wide guards (contracts/FAILURES.md 18.2, 18.3), installed once
/// by `configure` and the first ad or feed view: the OS's memory warning, and
/// MetricKit's crash, hang, CPU and disk-write diagnostics. No signal or
/// exception handler: it would fight the host app's crash reporter.
enum SellwildGuards {
    private static let lock = NSLock()
    private static var installed = false
    private static var memoryReported = false
    private static var observer: NSObjectProtocol?
    #if canImport(MetricKit)
    private static var subscriber: AnyObject?
    #endif

    /// Installs the guards once per process. Main thread.
    static func install(center: NotificationCenter = .default) {
        let first = lock.locked { () -> Bool in
            defer { installed = true }
            return !installed
        }
        guard first else { return }
        observer = center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                      object: nil, queue: nil) { _ in memoryWarning() }
        #if canImport(MetricKit)
        if #available(iOS 14.0, *) {
            let metrics = SellwildMetricSubscriber()
            MXMetricManager.shared.add(metrics)
            subscriber = metrics
        }
        #endif
    }

    /// One sdk.memory.warning per process, with the footprint and the live views.
    static func memoryWarning(footprint: () -> UInt64? = physicalFootprint) {
        let first = lock.locked { () -> Bool in
            defer { memoryReported = true }
            return !memoryReported
        }
        guard first else { return }
        var context: [String: Any] = ["adViews": SellwildViews.adViews, "feedViews": SellwildViews.feedViews]
        context["footprintMb"] = footprint().map { Int($0 / 1_048_576) }
        SellwildFailures.log(code: .sdkMemoryWarning, component: .sdk, severity: .warn,
                             message: "memory warning", context: context)
    }

    /// `task_vm_info.phys_footprint`: what iOS counts against the app's memory limit.
    static func physicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// Reports what one MetricKit diagnostic payload holds (JSON form).
    static func report(diagnosticJSON data: Data) {
        for report in SellwildDiagnostics.reports(fromJSON: data) {
            SellwildFailures.logReport(code: report.code, component: .sdk, severity: report.severity,
                                       message: report.message, stack: report.stack)
        }
    }

    /// Tests: install again, report memory again.
    static func resetForTests(center: NotificationCenter = .default) {
        lock.locked {
            installed = false
            memoryReported = false
        }
        if let observer { center.removeObserver(observer) }
        observer = nil
        #if canImport(MetricKit)
        if #available(iOS 14.0, *), let metrics = subscriber as? SellwildMetricSubscriber {
            MXMetricManager.shared.remove(metrics)
        }
        subscriber = nil
        #endif
    }
}

#if canImport(MetricKit)
/// MetricKit hands diagnostics to this on a later launch (iOS 14+).
@available(iOS 14.0, *)
final class SellwildMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // sellwild-coverage:exclude-begin(os-report) only MetricKit creates an MXDiagnosticPayload (no public init).
        payloads.map { $0.jsonRepresentation() }.forEach(SellwildGuards.report(diagnosticJSON:))
        // sellwild-coverage:exclude-end
    }
}
#endif
