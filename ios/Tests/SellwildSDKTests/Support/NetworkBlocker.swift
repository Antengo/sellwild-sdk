import Foundation
import XCTest

/// Fails every real network request made while this test bundle runs.
///
/// It is installed once per test process, before XCTest builds or runs any
/// test (see the image-load hook at the bottom of this file). From then on
/// `URLSession.shared`, `Data(contentsOf:)` on http(s) URLs, and every session
/// built from `URLSessionConfiguration.default` or `.ephemeral` go through it.
/// Local `file:` and `data:` URLs pass through untouched.
///
/// A blocked request fails with `URLError(.notConnectedToInternet)`. Its
/// message names the method and URL, and the URL is recorded. A test that
/// leaves a blocked request unclaimed fails at teardown, so nothing is sent
/// or dropped silently.
///
/// - A test that expects a blocked request claims it with `takeBlocked()`.
/// - A test that needs HTTP injects `StubURLProtocol.makeSession()`.
/// - Not seen here: WKWebView loads (out of process), background session
///   configurations, sessions whose `protocolClasses` a test replaces, and
///   Network.framework or socket traffic.
///
/// When a request is blamed: the unclaimed check is a teardown block, and
/// XCTest runs teardown blocks before `tearDown()`. A request that starts
/// after the check (from `tearDown()`, or from async work the test left
/// running) fails the NEXT test instead. Its message still names the test it
/// started during. A request that starts after the last test's check cannot
/// fail any test, so it is written to `leftoversFile()` and
/// `scripts/coverage/ios.sh` fails the run.
///
/// Two leaks this timing used to turn into random failures are closed where
/// they start, for the whole process:
/// - The SDK's shared events queue sends to a stub (`SharedEventsQueue`),
///   emptied before every test. It posted over `URLSession.shared` and
///   retried a blocked batch every 10 s.
/// - When a test ends, the tasks still open on its stub sessions are
///   cancelled (`StubURLProtocol.cancelRunningTasks()`), before the check,
///   so they cannot reach the next test's stub handler.
final class NetworkBlocker: URLProtocol {

    struct BlockedRequest: Equatable {
        let method: String
        let url: URL?
        /// Name of the test that was running when the request started, or nil
        /// when it started between tests (a leftover from an earlier test).
        let startedDuring: String?
    }

    enum InstallOrigin: Equatable {
        /// The `__mod_init_func` hook: the bundle image loaded. Covers every
        /// run, including `-only-testing` runs and parallel test clones.
        case imageLoad
        /// XCTest asked `NetworkBlockerBootstrap` for its suite. Fallback for
        /// compilers without `@section`; covers full-bundle runs only.
        case testSuite
    }

    /// Set to `true` in the `userInfo` of every error this class produces.
    static let userInfoKey = "SellwildNetworkBlocked"

    /// Overrides where `testBundleDidFinish` reports leftover requests. Tests
    /// run in the simulator, so `scripts/coverage/ios.sh` passes it as
    /// `TEST_RUNNER_SELLWILD_NETWORK_LEFTOVERS`.
    static let leftoversEnvironmentKey = "SELLWILD_NETWORK_LEFTOVERS"

    private static let lock = NSLock()
    private static var unclaimed: [BlockedRequest] = []
    private static var log: [BlockedRequest] = []
    private static var currentTest: String?
    private static var origin: InstallOrigin?
    private static var bundleStartSeen = false
    private static var configurationsPatched = false

    // MARK: Installation

    /// Registers the blocker for the whole process. Safe to call repeatedly;
    /// only the first call does anything.
    static func install(origin: InstallOrigin) {
        lock.lock()
        let first = self.origin == nil
        if first { self.origin = origin }
        lock.unlock()
        guard first else { return }

        URLProtocol.registerClass(NetworkBlocker.self)
        patchSessionConfigurations()
        SharedEventsQueue.install()
        XCTestObservationCenter.shared.addTestObserver(Observation())
    }

    /// How the blocker was installed, or nil if it never was.
    static var installOrigin: InstallOrigin? { locked { origin } }

    /// True once XCTest reported the bundle start to the blocker's observer,
    /// which proves the blocker was in place before the first test ran.
    static var sawBundleStart: Bool { locked { bundleStartSeen } }

    /// True when `.default` and `.ephemeral` configurations carry the blocker.
    static var sessionConfigurationsPatched: Bool { locked { configurationsPatched } }

    /// `URLProtocol.registerClass` only reaches `URLSession.shared`. Sessions
    /// built from a fresh configuration take their protocol list from it, so
    /// the two configuration factories are swapped for versions that put the
    /// blocker first. A test that sets its own `protocolClasses` replaces the
    /// list and keeps full control.
    private static func patchSessionConfigurations() {
        let type: AnyClass = URLSessionConfiguration.self
        let pairs: [(Selector, Selector)] = [
            (#selector(getter: URLSessionConfiguration.default),
             #selector(URLSessionConfiguration.sellwildTests_blockedDefault)),
            (#selector(getter: URLSessionConfiguration.ephemeral),
             #selector(URLSessionConfiguration.sellwildTests_blockedEphemeral)),
        ]
        var patched = 0
        for (original, replacement) in pairs {
            guard let originalMethod = class_getClassMethod(type, original),
                  let replacementMethod = class_getClassMethod(type, replacement)
            else { continue }
            method_exchangeImplementations(originalMethod, replacementMethod)
            patched += 1
        }
        // A partial patch leaves the flag false, and the self-test fails.
        locked { configurationsPatched = patched == pairs.count }
    }

    // MARK: Claiming blocked requests

    /// Returns the blocked requests no test has claimed yet and marks them
    /// claimed. Call it in a test that expects a blocked request.
    static func takeBlocked() -> [BlockedRequest] {
        locked {
            let taken = unclaimed
            unclaimed = []
            return taken
        }
    }

    /// Every request blocked in this process, claimed or not, oldest first.
    static var history: [BlockedRequest] { locked { log } }

    /// True when `error` came from this blocker.
    static func isBlocked(_ error: Error?) -> Bool {
        guard let error = error else { return false }
        return (error as NSError).userInfo[userInfoKey] as? Bool == true
    }

    /// Claims every unclaimed request and returns a failure message naming
    /// them, or nil when there were none. The teardown hook fails the test
    /// with this message.
    static func claimUnclaimedFailureMessage() -> String? {
        let current = locked { currentTest }
        return failureMessage(for: takeBlocked(), currentTest: current)
    }

    /// The failure message for `leftovers`, reported while `currentTest` runs
    /// (nil after the last test), or nil when there are none.
    static func failureMessage(for leftovers: [BlockedRequest], currentTest: String?) -> String? {
        guard !leftovers.isEmpty else { return nil }
        let lines = leftovers.map { request -> String in
            let started = request.startedDuring.map { "during \($0)" } ?? "between tests"
            return "\(request.method) \(request.url?.absoluteString ?? "<no url>") (started \(started))"
        }
        let late = leftovers.contains { $0.startedDuring == nil || $0.startedDuring != currentTest }
        return "NetworkBlocker stopped \(leftovers.count) real network request(s) that no test claimed: "
            + lines.joined(separator: "; ")
            + ". Inject StubURLProtocol.makeSession(), or call NetworkBlocker.takeBlocked() if the block is expected."
            + (late ? " Requests that did not start in the running test are reported late: they began after the check for the test they started in, or between tests." : "")
    }

    // MARK: Leftovers after the last test

    /// `$SELLWILD_NETWORK_LEFTOVERS` when set and not empty, else
    /// `.coverage-tmp/ios-network-leftovers.txt` in this repo.
    static func leftoversFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[leftoversEnvironmentKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return Fixtures.repoRoot.appendingPathComponent(".coverage-tmp/ios-network-leftovers.txt")
    }

    /// Claims every unclaimed request and appends their failure message to
    /// `file`. Returns false, and writes nothing, when there were none.
    @discardableResult
    static func reportLeftovers(to file: URL) throws -> Bool {
        guard let message = claimUnclaimedFailureMessage() else { return false }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let earlier = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : Data()
        try (earlier + Data((message + "\n").utf8)).write(to: file, options: .atomic)
        return true
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        let scheme = request.url?.scheme?.lowercased() ?? ""
        return scheme != "file" && scheme != "data"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let url = request.url
        NetworkBlocker.locked {
            let blocked = BlockedRequest(method: method, url: url, startedDuring: NetworkBlocker.currentTest)
            NetworkBlocker.unclaimed.append(blocked)
            NetworkBlocker.log.append(blocked)
        }
        var info: [String: Any] = [
            NSLocalizedDescriptionKey: "NetworkBlocker: real network is blocked in tests: \(method) \(url?.absoluteString ?? "<no url>")",
            NetworkBlocker.userInfoKey: true,
        ]
        if let url = url { info[NSURLErrorFailingURLErrorKey] = url }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet, userInfo: info))
    }

    override func stopLoading() {
        // Nothing to cancel: startLoading fails the request before returning.
    }

    // MARK: Test observation

    /// Tracks which test is running and fails any test that leaves a blocked
    /// request unclaimed. The check runs as a teardown block because XCTest
    /// cannot take a failure once `testCaseDidFinish` has been called. See
    /// "When a request is blamed" above for what that timing misses.
    ///
    /// Each test also starts with no stub handler, no captured stub requests
    /// and an empty shared events queue, and its stub tasks still open when
    /// it ends are cancelled.
    private final class Observation: NSObject, XCTestObservation {
        func testBundleWillStart(_ testBundle: Bundle) {
            NetworkBlocker.locked { NetworkBlocker.bundleStartSeen = true }
        }

        func testCaseWillStart(_ testCase: XCTestCase) {
            NetworkBlocker.locked { NetworkBlocker.currentTest = testCase.name }
            StubURLProtocol.reset()
            SharedEventsQueue.drain()
            // Registered first, so it runs after the test's own teardown
            // blocks, and before its tearDown().
            testCase.addTeardownBlock {
                StubURLProtocol.cancelRunningTasks()
                if let message = NetworkBlocker.claimUnclaimedFailureMessage() {
                    XCTFail(message)
                }
            }
        }

        func testCaseDidFinish(_ testCase: XCTestCase) {
            NetworkBlocker.locked { NetworkBlocker.currentTest = nil }
        }

        /// XCTest takes no failures once the bundle has finished, so requests
        /// blocked after the last test's check go to a file ios.sh checks.
        func testBundleDidFinish(_ testBundle: Bundle) {
            let file = NetworkBlocker.leftoversFile()
            do {
                try NetworkBlocker.reportLeftovers(to: file)
            } catch {
                // Nothing can fail a test now and tests may not print, so end
                // the run: xcodebuild reports the crash and this message.
                fatalError("NetworkBlocker could not report leftover requests to \(file.path): \(error)")
            }
        }
    }

    private static func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

extension URLSessionConfiguration {
    // After `patchSessionConfigurations` swaps implementations, calling these
    // names runs the ORIGINAL factories, so there is no recursion.

    @objc class func sellwildTests_blockedDefault() -> URLSessionConfiguration {
        let configuration = sellwildTests_blockedDefault()
        configuration.protocolClasses = [NetworkBlocker.self] + (configuration.protocolClasses ?? [])
        return configuration
    }

    @objc class func sellwildTests_blockedEphemeral() -> URLSessionConfiguration {
        let configuration = sellwildTests_blockedEphemeral()
        configuration.protocolClasses = [NetworkBlocker.self] + (configuration.protocolClasses ?? [])
        return configuration
    }
}

/// Fallback installer. XCTest asks every test class for its suite before the
/// first test runs, so a full-bundle run installs the blocker here even on a
/// compiler without `@section`. It holds no tests.
final class NetworkBlockerBootstrap: XCTestCase {
    override class var defaultTestSuite: XCTestSuite {
        NetworkBlocker.install(origin: .testSuite)
        return super.defaultTestSuite
    }
}

#if compiler(>=6.3)
/// Runs when the test bundle's image loads, before XCTest enumerates tests.
/// SwiftPM test bundles have no Info.plist principal class, and a class-level
/// hook is skipped when `-only-testing` filters that class out, so this is the
/// one hook that covers every run.
@used @section("__DATA,__mod_init_func,mod_init_funcs")
private let sellwildTestsInstallNetworkBlocker: @convention(c) () -> Void = {
    NetworkBlocker.install(origin: .imageLoad)
}
#endif
