import XCTest
@testable import SellwildSDK

/// Unit tests for `SellwildAdStack` parsing + resolution — the decision of
/// WHICH ad SDK stack a placement runs (GAM vs Prebid), independent of UIKit.
final class SellwildAdStackTests: XCTestCase {

    func testParseIsCaseAndAliasTolerant() {
        XCTAssertEqual(SellwildAdStack.parse("BOTH"), .both)
        XCTAssertEqual(SellwildAdStack.parse("default"), .both)
        XCTAssertEqual(SellwildAdStack.parse("GAM"), .gamOnly)
        XCTAssertEqual(SellwildAdStack.parse("gam-only"), .gamOnly)
        XCTAssertEqual(SellwildAdStack.parse("google"), .gamOnly)
        XCTAssertEqual(SellwildAdStack.parse("PREBID_ONLY"), .prebidOnly)
        XCTAssertEqual(SellwildAdStack.parse("prebid"), .prebidOnly)
    }

    func testParseReturnsNilForUnknown() {
        XCTAssertNil(SellwildAdStack.parse("xyz"))
        XCTAssertNil(SellwildAdStack.parse(nil))
        XCTAssertNil(SellwildAdStack.parse(42))
    }

    func testResolveDefaultsToPrebidOnly() {
        // Unknown stack (no config, or config naming no stack) must never
        // resolve to a stack that issues a GAM request.
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: nil, zoneId: "43"), .prebidOnly)
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: nil, zoneId: nil), .prebidOnly)
        XCTAssertEqual(
            SellwildAdStack.resolve(remoteValues: ["CODE": "acme"], zoneId: "43"),
            .prebidOnly
        )
        // An unparseable value is treated as unknown too.
        XCTAssertEqual(
            SellwildAdStack.resolve(remoteValues: ["AD_STACK": "xyz"], zoneId: "43"),
            .prebidOnly
        )
    }

    func testResolveExplicitBothStillHonoured() {
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: ["AD_STACK": "default"], zoneId: "43"), .both)
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: ["AD_STACK": "both"], zoneId: nil), .both)
        XCTAssertEqual(
            SellwildAdStack.resolve(remoteValues: ["AD_STACK_BY_ZONE": ["43": "both"]], zoneId: "43"),
            .both
        )
    }

    func testResolveGlobalHardWinsOverPerZone() {
        let remote: [String: Any] = [
            "AD_STACK": "PREBID",
            "AD_STACK_BY_ZONE": ["43": "GAM"],
        ]
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: remote, zoneId: "43"), .prebidOnly)
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: remote, zoneId: nil), .prebidOnly)
    }

    func testResolvePerZoneWhenNoGlobal() {
        let remote: [String: Any] = [
            "AD_STACK_BY_ZONE": ["43": "gamOnly", "99": "prebidOnly"],
        ]
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: remote, zoneId: "43"), .gamOnly)
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: remote, zoneId: "99"), .prebidOnly)
        XCTAssertEqual(SellwildAdStack.resolve(remoteValues: remote, zoneId: "7"), .prebidOnly)
    }

    func testResolveOverrideBeatsRemote() {
        let remote: [String: Any] = ["AD_STACK": "GAM"]
        XCTAssertEqual(
            SellwildAdStack.resolve(remoteValues: remote, zoneId: "43", override: .prebidOnly),
            .prebidOnly
        )
    }

    func testRawValuesMatchReactNativeBridgeStrings() {
        // The RN bridge reconstructs the override via SellwildAdStack(rawValue:),
        // so the raw values must equal the JS-side AdStack union strings.
        XCTAssertEqual(SellwildAdStack.both.rawValue, "both")
        XCTAssertEqual(SellwildAdStack.gamOnly.rawValue, "gamOnly")
        XCTAssertEqual(SellwildAdStack.prebidOnly.rawValue, "prebidOnly")
        XCTAssertEqual(SellwildAdStack(rawValue: "prebidOnly"), .prebidOnly)
    }
}
