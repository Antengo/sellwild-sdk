import XCTest
@testable import SellwildSDK

/// Unit tests for the Boltive policy: the on/off switch precedence, the client
/// id requirement, and the sampling / per-session / per-slot caps.
final class SellwildBoltiveTests: XCTestCase {

    private let zone = "43"
    private let on: [String: Any] = ["MOBILE_BOLTIVE_ENABLED": true, "MOBILE_BOLTIVE_CLIENT_ID": "abc"]

    func testOffByDefault() {
        XCTAssertNil(SellwildBoltive.policy(remoteValues: nil, zoneId: zone))
        XCTAssertNil(SellwildBoltive.policy(remoteValues: ["MOBILE_BOLTIVE_CLIENT_ID": "abc"], zoneId: zone))
    }

    func testRequiresClientId() {
        XCTAssertNil(SellwildBoltive.policy(remoteValues: ["MOBILE_BOLTIVE_ENABLED": true], zoneId: zone))
        XCTAssertNil(SellwildBoltive.policy(
            remoteValues: ["MOBILE_BOLTIVE_ENABLED": true, "MOBILE_BOLTIVE_CLIENT_ID": "  "], zoneId: zone))
    }

    func testEnabledDefaults() {
        XCTAssertEqual(
            SellwildBoltive.policy(remoteValues: on, zoneId: zone),
            .init(clientId: "abc", sampleRate: 1, maxPerSession: 0, maxPerSlot: 0)
        )
    }

    func testStringAndNumberTruthiness() {
        XCTAssertTrue(SellwildBoltive.isEnabled(remoteValues: ["MOBILE_BOLTIVE_ENABLED": "true"], zoneId: zone))
        XCTAssertTrue(SellwildBoltive.isEnabled(remoteValues: ["MOBILE_BOLTIVE_ENABLED": 1], zoneId: zone))
        XCTAssertFalse(SellwildBoltive.isEnabled(remoteValues: ["MOBILE_BOLTIVE_ENABLED": "off"], zoneId: zone))
    }

    func testPlatformOverride() {
        var v = on
        v["MOBILE_BOLTIVE_ENABLED_IOS"] = false
        XCTAssertNil(SellwildBoltive.policy(remoteValues: v, zoneId: zone), "platform false is a hard kill")
        XCTAssertTrue(SellwildBoltive.isEnabled(remoteValues: ["MOBILE_BOLTIVE_ENABLED_IOS": true], zoneId: zone))
        XCTAssertFalse(SellwildBoltive.isEnabled(
            remoteValues: ["MOBILE_BOLTIVE_ENABLED_IOS": false, "MOBILE_BOLTIVE_ENABLED_BY_ZONE": [zone: true]],
            zoneId: zone))
    }

    func testPerZone() {
        let v: [String: Any] = ["MOBILE_BOLTIVE_ENABLED": false, "MOBILE_BOLTIVE_ENABLED_BY_ZONE": [zone: true]]
        XCTAssertTrue(SellwildBoltive.isEnabled(remoteValues: v, zoneId: zone))
        XCTAssertFalse(SellwildBoltive.isEnabled(remoteValues: v, zoneId: "other"))
        XCTAssertFalse(SellwildBoltive.isEnabled(remoteValues: v, zoneId: nil))
    }

    func testCapsAndSampleRateParsing() {
        var v = on
        v["MOBILE_BOLTIVE_SAMPLE_RATE"] = "0.25"
        v["MOBILE_BOLTIVE_MAX_PER_SESSION"] = 50
        v["MOBILE_BOLTIVE_MAX_PER_SLOT"] = "3"
        XCTAssertEqual(
            SellwildBoltive.policy(remoteValues: v, zoneId: zone),
            .init(clientId: "abc", sampleRate: 0.25, maxPerSession: 50, maxPerSlot: 3)
        )
        v["MOBILE_BOLTIVE_SAMPLE_RATE"] = 7
        v["MOBILE_BOLTIVE_MAX_PER_SLOT"] = -2
        let p = SellwildBoltive.policy(remoteValues: v, zoneId: zone)
        XCTAssertEqual(p?.sampleRate, 1, "clamped to [0, 1]")
        XCTAssertEqual(p?.maxPerSlot, 0, "negative = unlimited")
    }

    func testShouldMonitor() {
        let p = SellwildBoltive.Policy(clientId: "abc", sampleRate: 0.5, maxPerSession: 10, maxPerSlot: 2)
        XCTAssertTrue(SellwildBoltive.shouldMonitor(policy: p, slotCount: 0, sessionCount: 0, roll: 0.49))
        XCTAssertFalse(SellwildBoltive.shouldMonitor(policy: p, slotCount: 0, sessionCount: 0, roll: 0.5))
        XCTAssertFalse(SellwildBoltive.shouldMonitor(policy: p, slotCount: 2, sessionCount: 0, roll: 0), "slot cap")
        XCTAssertFalse(SellwildBoltive.shouldMonitor(policy: p, slotCount: 0, sessionCount: 10, roll: 0), "session cap")
        let none = SellwildBoltive.Policy(clientId: "abc", sampleRate: 0, maxPerSession: 0, maxPerSlot: 0)
        XCTAssertFalse(SellwildBoltive.shouldMonitor(policy: none, slotCount: 0, sessionCount: 0, roll: 0))
        let all = SellwildBoltive.Policy(clientId: "abc", sampleRate: 1, maxPerSession: 0, maxPerSlot: 0)
        XCTAssertTrue(SellwildBoltive.shouldMonitor(policy: all, slotCount: 999, sessionCount: 999, roll: 0.999))
    }

    func testControllerCountsOnlyMonitoredRenders() {
        let c = SellwildBoltiveController()
        let view = UIView()
        let start = SellwildBoltive.sessionCount
        XCTAssertFalse(c.renderDidSucceed(bannerView: view, network: .prebid, remoteValues: nil,
                                          zoneId: zone, tag: .init(), roll: 0) { _ in })
        XCTAssertEqual(c.slotCount, 0)
        var capped = on
        capped["MOBILE_BOLTIVE_MAX_PER_SLOT"] = 1
        XCTAssertTrue(c.renderDidSucceed(bannerView: view, network: .prebid, remoteValues: capped,
                                         zoneId: zone, tag: .init(), roll: 0) { _ in })
        XCTAssertFalse(c.renderDidSucceed(bannerView: view, network: .prebid, remoteValues: capped,
                                          zoneId: zone, tag: .init(), roll: 0) { _ in })
        XCTAssertEqual(c.slotCount, 1)
        XCTAssertEqual(SellwildBoltive.sessionCount, start + 1)
    }
}
