import XCTest
import UIKit
@testable import SellwildSDK

/// sdkTiming (golden vectors and the shell), the MetricKit diagnostic parser,
/// the memory warning and the SDK session's timeouts (FAILURES.md 18).
final class SellwildTimingAndGuardsTests: FailureCapturingTestCase {

    typealias Timing = SellwildTimingCore

    private var pushed: [Timing.Event] = []
    private var clock: TimeInterval = 100

    override func setUp() {
        super.setUp()
        pushed = []
        clock = 100
        SellwildTiming.setDependencies(SellwildTiming.Dependencies(
            push: { [unowned self] in self.pushed.append($0) },
            now: { 1_790_000_000_000 },
            uid: { "u-1" },
            monotonic: { [unowned self] in self.clock }
        ))
        SellwildTiming.remote = ["TIMING_SAMPLE_RATE": 1]
    }

    // MARK: Golden vectors

    private func golden() throws -> [String: Any] {
        try Fixtures.dict("golden/sdk-timing.vectors.json")
    }

    func testEveryTimingVectorIsReproducedExactly() throws {
        let vectors = try XCTUnwrap(try golden()["vectors"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)
        for vector in vectors {
            let name = try XCTUnwrap(vector["name"] as? String)
            let c = try XCTUnwrap(vector["context"] as? [String: Any])
            let input = try XCTUnwrap(vector["input"] as? [String: Any])
            let expected = try XCTUnwrap(vector["expected"] as? [String: Any])
            let before = try XCTUnwrap((vector["stateBefore"] as? [String: Any])?["sessionCount"] as? Int)
            let decision = Timing.decide(
                state: .init(sessionCount: before),
                input: .init(step: input["step"], ms: input["ms"], zoneId: input["zoneId"]),
                context: .init(partnerCode: c["partnerCode"], client: c["client"], clientVersion: c["clientVersion"],
                               appId: c["appId"], appVersion: c["appVersion"], os: c["os"], device: c["device"],
                               net: c["net"], eventsEnabled: c["eventsEnabled"], timingEnabled: c["timingEnabled"],
                               timingSampleRate: c["timingSampleRate"]),
                uid: c["uid"],
                now: try XCTUnwrap((c["now"] as? NSNumber)?.int64Value)
            )
            XCTAssertEqual(decision.reason, expected["reason"] as? String, name)
            XCTAssertEqual(decision.state.sessionCount,
                           (expected["stateAfter"] as? [String: Any])?["sessionCount"] as? Int, name)
            if let event = expected["event"] as? [String: Any] {
                let got = try XCTUnwrap(decision.event, name)
                XCTAssertEqual(got.event, event["event"] as? String, name)
                XCTAssertEqual(got.action, event["action"] as? String, name)
                XCTAssertEqual(got.label, event["label"] as? String, name)
                XCTAssertEqual(got.attributes, event["attributes"] as? [String: String], name)
                XCTAssertEqual(got.uid, event["uid"] as? String, name)
                XCTAssertEqual(got.createdTime, (event["createdTime"] as? NSNumber)?.int64Value, name)
            } else {
                XCTAssertNil(decision.event, name)
            }
        }
    }

    func testTheUnitTablesAndLimits() throws {
        let file = try golden()
        let units = try XCTUnwrap(file["units"] as? [String: [[String: Any]]])
        for row in units["budgetFor"] ?? [] {
            let args = try XCTUnwrap(row["input"] as? [Any])
            XCTAssertEqual(Timing.budgetFor(args[0], remote: args[1] as? [String: Any]),
                           row["expected"] as? Int, "\(args)")
        }
        for row in units["isSlow"] ?? [] {
            let args = try XCTUnwrap(row["input"] as? [Any])
            XCTAssertEqual(Timing.isSlow(args[0], ms: args[1], remote: args[2] as? [String: Any]),
                           row["expected"] as? Bool, "\(args)")
        }
        for row in units["timingRate"] ?? [] {
            let input = row["input"] is NSNull ? nil : row["input"]
            XCTAssertEqual(Timing.timingRate(input), row["expected"] as? Double, "\(String(describing: input))")
        }
        XCTAssertEqual(file["budgets"] as? [String: Int], Timing.budgets)
        XCTAssertEqual(file["budgetKeys"] as? [String: String], Timing.budgetKeys)
        XCTAssertEqual(file["slowCodes"] as? [String: String], Timing.slowCodes)
        XCTAssertEqual(file["steps"] as? [String], Timing.steps)
        let limits = try XCTUnwrap(file["limits"] as? [String: Any])
        XCTAssertEqual(limits["sessionTimings"] as? Int, Timing.Limits.sessionTimings)
        XCTAssertEqual(limits["defaultRate"] as? Double, Timing.Limits.defaultRate)
        XCTAssertEqual(Timing.parseBudgetMs("+250"), 250)
        XCTAssertNil(Timing.parseBudgetMs(""))
        XCTAssertNil(Timing.parseBudgetMs(Double.nan))
    }

    // MARK: Shell

    func testARecordedStepCarriesThePartnerAndAppContext() throws {
        SellwildFailures.setContext { $0.partnerCode = "weatherbug" }
        SellwildTiming.record(step: "listings.fetch", ms: 812.4)

        let event = try XCTUnwrap(pushed.first)
        XCTAssertEqual(event.action, "listings.fetch")
        XCTAssertEqual(event.attributes["ms"], "812")
        XCTAssertEqual(event.attributes["code"], "weatherbug")
        XCTAssertEqual(event.attributes["client"], "ios")
        XCTAssertEqual(event.attributes["os"], SellwildAppInfo.current.os)
        XCTAssertEqual(event.uid, "u-1")
        capture.none()
    }

    func testEachSlowStepLogsItsCodeWithTheMsAndBudgetEvenWhenSampledOut() throws {
        SellwildTiming.remote = ["TIMING_SAMPLE_RATE": 0, "TIMING_BUDGET_CONFIG_MS": "100"]

        SellwildTiming.record(step: "config.fetch", ms: 101)
        SellwildTiming.record(step: "listings.fetch", ms: 4001)
        SellwildTiming.record(step: "ad.firstLoad", ms: 6000.6, zoneId: "43")
        SellwildTiming.record(step: "listings.decode", ms: 99_999)

        XCTAssertTrue(pushed.isEmpty)
        XCTAssertEqual(capture.events.map(\.action), ["config.fetch.slow", "listings.fetch.slow", "ad.load.slow"])
        XCTAssertEqual(capture.events.map(\.label), ["remoteConfig", "listings", "banner"])
        let ad = try XCTUnwrap(capture.events.last?.attributes)
        XCTAssertEqual(ad["ctx.ms"], "6001")
        XCTAssertEqual(ad["ctx.budgetMs"], "6000")
        XCTAssertEqual(ad["zoneId"], "43")
    }

    func testStartTimesWithTheMonotonicClockAndClaimOnceIsOncePerKey() throws {
        let done = SellwildTiming.start("ad.firstLoad", zoneId: "43")
        clock += 0.25
        XCTAssertEqual(done(), 250, accuracy: 0.001)
        XCTAssertEqual(pushed.first?.attributes["zoneId"], "43")
        XCTAssertTrue(SellwildTiming.claimOnce("feed.firstListing"))
        XCTAssertFalse(SellwildTiming.claimOnce("feed.firstListing"))
        XCTAssertGreaterThan(SellwildTiming.Dependencies.live.monotonic(), 0)
    }

    func testTheLiveDependenciesSendThroughTheSharedQueue() throws {
        XCTAssertEqual(SellwildTiming.remote?["TIMING_SAMPLE_RATE"] as? Int, 1)
        let event = SellwildTimingCore.Event(event: "sdkTiming", action: "config.fetch", label: "timing",
                                             attributes: ["step": "config.fetch", "ms": "5"], uid: "u", createdTime: 7)
        SellwildTiming.Dependencies.live.push(event)

        let sent = SharedEventsQueue.drain().flatMap { request -> [[String: Any]] in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [[String: Any]] ?? []
        }
        let timings = sent.filter { $0["event"] as? String == "sdkTiming" }
        XCTAssertEqual(timings.compactMap { $0["action"] as? String }, ["config.fetch"])
        XCTAssertEqual(SellwildTiming.Dependencies.live.uid(), SellwildSession.shared.uid)
        XCTAssertGreaterThan(SellwildTiming.Dependencies.live.now(), 0)
    }

    // MARK: MetricKit diagnostics

    /// The shape of `MXDiagnosticPayload.jsonRepresentation()` (as recorded
    /// from Xcode's simulated MetricKit payloads, addresses trimmed).
    private func payload(binary: String = "SellwildSDK") throws -> Data {
        let frames: [String: Any] = [
            "binaryName": binary, "binaryUUID": "70B89F27-1634-3580-A695-57CDB41D7743",
            "offsetIntoBinaryTextSegment": 13_412, "sampleCount": 1, "address": 74_565,
            "subFrames": [[
                "binaryName": "UIKitCore", "offsetIntoBinaryTextSegment": 2_204_528, "sampleCount": 1,
                "subFrames": [["binaryName": "App", "offsetIntoBinaryTextSegment": 9_000, "sampleCount": 1]]
            ]]
        ]
        let other: [String: Any] = ["binaryName": "libsystem_kernel.dylib", "offsetIntoBinaryTextSegment": 4_812]
        func tree(_ attributed: Bool) -> [String: Any] {
            ["callStackPerThread": true, "callStacks": [
                ["threadAttributed": false, "callStackRootFrames": [other]],
                ["threadAttributed": attributed, "callStackRootFrames": [frames]]
            ]]
        }
        let json: [String: Any] = [
            "timeStampBegin": "2026-10-29 10:00:00", "timeStampEnd": "2026-10-30 10:00:00",
            "crashDiagnostics": [[
                "callStackTree": tree(true),
                "diagnosticMetaData": ["exceptionType": 1, "exceptionCode": 0, "signal": 11,
                                       "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11",
                                       "appVersion": "6.12.0", "osVersion": "iPhone OS 26.1 (23B85)"]
            ]],
            "hangDiagnostics": [["callStackTree": tree(false), "diagnosticMetaData": ["hangDuration": "3.12 sec"]]],
            "cpuExceptionDiagnostics": [["callStackTree": tree(true),
                                         "diagnosticMetaData": ["totalCPUTime": "91 sec"]]],
            "diskWriteExceptionDiagnostics": [["callStackTree": tree(true), "diagnosticMetaData": [:]]]
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testDiagnosticsWithASellwildFrameAreReportedWithTheirStack() throws {
        let reports = SellwildDiagnostics.reports(fromJSON: try payload())

        XCTAssertEqual(reports.map(\.code), [.sdkCrashException, .sdkHangTimeout, .sdkCpuException,
                                             .sdkDiskWriteException])
        XCTAssertEqual(reports.map(\.severity), [.fatal, .error, .warn, .warn])
        XCTAssertEqual(reports[0].message,
                       "crash: exception type 1: code 0: signal 11: Namespace SIGNAL, Code 11 Segmentation fault: 11")
        XCTAssertEqual(reports[1].message, "hang: 3.12 sec")
        XCTAssertEqual(reports[2].message, "cpu exception: 91 sec")
        XCTAssertEqual(reports[3].message, "disk writes: unknown")
        XCTAssertEqual(reports[0].stack, "SellwildSDK +13412\nUIKitCore +2204528\nApp +9000")
        XCTAssertEqual(reports[1].stack, reports[0].stack, "a stack that is not attributed still counts")
    }

    func testDiagnosticsWithoutASellwildFrameOrUnreadableAreNotReported() throws {
        XCTAssertEqual(SellwildDiagnostics.reports(fromJSON: try payload(binary: "App")), [])
        XCTAssertEqual(SellwildDiagnostics.reports(fromJSON: Data("not json".utf8)), [])
        XCTAssertEqual(SellwildDiagnostics.reports(fromJSON: Data("{}".utf8)), [])
        XCTAssertTrue(SellwildDiagnostics.isSellwildBinary("SellwildPrebidSDK"))
        XCTAssertNil(SellwildDiagnostics.sellwildStack(nil))
        let crash = try JSONSerialization.data(withJSONObject: ["crashDiagnostics": [[
            "callStackTree": ["callStacks": [["callStackRootFrames": [["binaryName": "SellwildSDK"]]]]],
            "diagnosticMetaData": ["exceptionType": "", "signal": true]
        ]]])
        let report = SellwildDiagnostics.reports(fromJSON: crash).first
        XCTAssertEqual(report?.message, "crash: signal 1")
        XCTAssertEqual(report?.stack, "SellwildSDK +?")
    }

    func testAPayloadIsLoggedWithItsOwnStack() throws {
        SellwildGuards.report(diagnosticJSON: try payload())

        XCTAssertEqual(capture.events.map(\.action), ["sdk.crash.exception", "sdk.hang.timeout",
                                                      "sdk.cpu.exception", "sdk.disk_write.exception"])
        XCTAssertEqual(capture.events.first?.attributes["stack"], "SellwildSDK +13412\nUIKitCore +2204528\nApp +9000")
        XCTAssertEqual(capture.events.first?.label, "sdk")
    }

    func testTheMetricKitSubscriberTakesAnEmptyDelivery() {
        if #available(iOS 14.0, *) {
            SellwildMetricSubscriber().didReceive([])
        }
        capture.none()
    }

    func testDiagnosticsWithMissingFieldsStillReadAndDefault() throws {
        let json: [String: Any] = [
            "hangDiagnostics": [["callStackTree": ["callStacks": [
                ["threadAttributed": true],
                ["callStackRootFrames": [[
                    "offsetIntoBinaryTextSegment": 1, "subFrames": [["binaryName": "SellwildSDK"]]
                ]]]
            ]]]],
            "cpuExceptionDiagnostics": [["callStackTree": ["callStacks": [
                ["callStackRootFrames": [["binaryName": "SellwildPrebidSDK", "offsetIntoBinaryTextSegment": 2]]]
            ]], "diagnosticMetaData": [:]]]
        ]
        let reports = SellwildDiagnostics.reports(fromJSON: try JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(reports.map(\.message), ["hang: unknown duration", "cpu exception: unknown CPU time"])
        XCTAssertEqual(reports.first?.stack, "? +1\nSellwildSDK +?")
    }

    func testTimingTakesAUidThatIsNotText() {
        XCTAssertFalse(Timing.isTimingSampled(uid: 7, rate: 0.01))
        let decision = Timing.decide(state: .init(), input: .init(step: "config.fetch", ms: 1),
                                     context: .init(timingSampleRate: 1), uid: 7, now: 1)
        XCTAssertEqual(decision.event?.uid, "")
        capture.none()
    }

    // MARK: Network

    func testTheSDKSessionHasExplicitTimeouts() {
        let configuration = SellwildNetwork.configuration()
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
        XCTAssertEqual(SellwildNetwork.session.configuration.timeoutIntervalForRequest, 15)
        XCTAssertTrue(SellwildAPIClient().eventClock.now() > 0)
        capture.none()
    }
}

// The memory warning (FAILURES.md 18.3).
extension SellwildTimingAndGuardsTests {

    func testAMemoryWarningIsReportedOncePerProcessWithTheFootprintAndViews() throws {
        let center = NotificationCenter()
        SellwildGuards.install(center: center)
        SellwildGuards.install(center: center)
        SellwildViews.adView(attached: true)
        SellwildViews.adView(attached: true)
        SellwildViews.adView(attached: false)
        SellwildViews.feedView(attached: true)

        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        XCTAssertEqual(capture.events.count, 1)
        let attributes = try XCTUnwrap(capture.events.first?.attributes)
        XCTAssertEqual(capture.events.first?.action, "sdk.memory.warning")
        XCTAssertEqual(attributes["ctx.adViews"], "1")
        XCTAssertEqual(attributes["ctx.feedViews"], "1")
        XCTAssertGreaterThan(Int(try XCTUnwrap(attributes["ctx.footprintMb"])) ?? 0, 0)
        SellwildGuards.resetForTests(center: center)
    }

    func testAFootprintThatCannotBeReadIsLeftOut() throws {
        SellwildGuards.memoryWarning(footprint: { nil })
        XCTAssertNil(capture.events.first?.attributes["ctx.footprintMb"])
        XCTAssertEqual(capture.events.first?.attributes["ctx.adViews"], "0")
    }
}
