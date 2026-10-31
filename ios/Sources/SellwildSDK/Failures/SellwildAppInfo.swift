import Foundation

/// The app context logFailure sends on every event (FAILURES.md 6.3, fv 2):
/// read once per launch from the main bundle, ProcessInfo and uname.
struct SellwildAppInfo: Equatable {
    var appId: String?
    var appVersion: String?
    var os: String
    var device: String?

    static let current = SellwildAppInfo(
        bundle: Bundle.main.infoDictionary,
        osVersion: ProcessInfo.processInfo.operatingSystemVersion,
        environment: ProcessInfo.processInfo.environment,
        machine: machineIdentifier()
    )

    /// Pure: the simulator reports the Mac's `arm64` from uname, so its
    /// SIMULATOR_MODEL_IDENTIFIER wins when set.
    init(bundle: [String: Any]?, osVersion: OperatingSystemVersion, environment: [String: String], machine: String?) {
        appId = bundle?["CFBundleIdentifier"] as? String
        appVersion = bundle?["CFBundleShortVersionString"] as? String
        let patch = osVersion.patchVersion == 0 ? "" : ".\(osVersion.patchVersion)"
        os = "iOS \(osVersion.majorVersion).\(osVersion.minorVersion)\(patch)"
        device = environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
    }

    /// `utsname.machine`, e.g. `iPhone16,2`.
    static func machineIdentifier() -> String? {
        var info = utsname()
        uname(&info)
        let text = withUnsafeBytes(of: &info.machine) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8)
        }
        return text?.isEmpty == false ? text : nil
    }
}
