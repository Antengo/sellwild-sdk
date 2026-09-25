import Foundation
import XCTest
@testable import SellwildSDK

/// A seeded random source (SplitMix64), so a random pick or shuffle in the
/// SDK can be replayed exactly in a test.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension AppConfigFactory {
    /// The `minimal` app-config fixture with `overrides`, through JSON: a
    /// remote config exactly as the SDK sees it in
    /// `SellwildConfig.remoteValues` (numbers are NSNumber, null is NSNull).
    /// With overrides it is emitted for the validator (`Factory.used`), so an
    /// input outside the schema must be built inside `Factory.offSchema`.
    static func remote(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        let data = try Factory.data(variant("minimal", overrides))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Factory.Failure.notAnObject("minimal")
        }
        return object
    }

    /// A config whose `remoteJSON` holds `remote(overrides)`, the way
    /// `SellwildSDK.configure` stores it.
    static func config(_ overrides: [String: Any] = [:], partnerCode: String = "minimal") throws -> SellwildConfig {
        var config = SellwildConfig(partnerCode: partnerCode)
        config.remoteJSON = try Factory.data(remote(overrides))
        return config
    }
}

/// Failure-report assertions shared by the logic tests. Install a
/// `FailureCapture` first (see `FailureCapture`).
///
/// Both check the log calls as well as the events: the dedupe gate folds a
/// second identical call within 60 s, so a site that logs twice still
/// yields one event. `calls` counts every call, dropped ones included.
extension FailureCapture {
    /// The one failure event, after checking there is exactly one with `code`
    /// and `label`, from exactly one log call.
    @discardableResult
    func only(_ code: SellwildFailureCode, label: SellwildFailureComponent,
              file: StaticString = #filePath, line: UInt = #line) -> SellwildFailuresCore.Event? {
        let all = events
        XCTAssertEqual(all.map(\.action), [code.rawValue], "expected exactly one \(code.rawValue)", file: file, line: line)
        XCTAssertEqual(calls, 1, "expected exactly one log call for \(code.rawValue)", file: file, line: line)
        guard all.count == 1, let event = all.first else { return nil }
        XCTAssertEqual(event.label, label.rawValue, file: file, line: line)
        return event
    }

    /// Checks that nothing was reported, and that log was not called at all.
    func none(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(events.map(\.action), [], "expected no failure", file: file, line: line)
        XCTAssertEqual(calls, 0, "expected no log call", file: file, line: line)
    }
}

/// A base for tests that capture failure reports: a fresh launch (failure
/// session and report-once latch) and a capturing sink per test.
class FailureCapturingTestCase: XCTestCase {

    var capture: FailureCapture!

    override func setUp() {
        super.setUp()
        newLaunch()
    }

    /// A fresh failure session and an empty capture, mid-test. The
    /// report-once latch (`SellwildReportOnce`) keeps what it has seen, as
    /// it would later in the same launch.
    func resetCapture() {
        SellwildFailures.resetForTests()
        capture = FailureCapture()
        capture.install()
    }

    /// `resetCapture`, and the report-once latch forgets what it has seen, as
    /// after a relaunch.
    func newLaunch() {
        SellwildReportOnce.resetForTests()
        resetCapture()
    }

    override func tearDown() {
        SellwildReportOnce.resetForTests()
        SellwildFailures.resetForTests()
        SellwildLog.isEnabled = false
        SellwildLog.setOutput(nil)
        capture = nil
        super.tearDown()
    }

    /// Debug lines written through `SellwildLog` while `body` runs.
    func debugLines(_ body: () throws -> Void) rethrows -> [String] {
        let lock = NSLock()
        var lines: [String] = []
        SellwildLog.isEnabled = true
        SellwildLog.setOutput { line in lock.lock(); lines.append(line); lock.unlock() }
        defer {
            SellwildLog.isEnabled = false
            SellwildLog.setOutput(nil)
        }
        try body()
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// An error a test throws on purpose.
struct PlannedError: LocalizedError, Equatable {
    var errorDescription: String? { "planned test error" }
}
