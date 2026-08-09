import XCTest
@testable import SellwildSDK

/// Unit tests for `SellwildNative.resolveConfigId` — the precedence that picks
/// the native placement id, independent of the Prebid fork request/render.
///
/// Chain: NATIVE_ZID_IOS → NATIVE_ZID_ALL_IOS → NATIVE_ZID → <mobile zoneId>.
final class SellwildNativeTests: XCTestCase {

    private let zone = "banner-zone-43"

    func testFallsBackToZoneWhenNoNativeKeys() {
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: nil, zoneId: zone), zone)
        XCTAssertEqual(
            SellwildNative.resolveConfigId(remoteValues: ["CODE": "weatherbug"], zoneId: zone),
            zone
        )
    }

    func testSharedNativeKeyUsedWhenNoPlatformKeys() {
        XCTAssertEqual(
            SellwildNative.resolveConfigId(remoteValues: ["NATIVE_ZID": "native-shared"], zoneId: zone),
            "native-shared"
        )
    }

    func testPlatformAllBeatsShared() {
        let remote: [String: Any] = [
            "NATIVE_ZID_ALL_IOS": "native-ios-all",
            "NATIVE_ZID": "native-shared",
        ]
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: remote, zoneId: zone), "native-ios-all")
    }

    func testPerPlatformBeatsEverything() {
        let remote: [String: Any] = [
            "NATIVE_ZID_IOS": "native-ios",
            "NATIVE_ZID_ALL_IOS": "native-ios-all",
            "NATIVE_ZID": "native-shared",
        ]
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: remote, zoneId: zone), "native-ios")
    }

    func testArrayValueTakesFirstNonEmpty() {
        let remote: [String: Any] = ["NATIVE_ZID_IOS": ["", "native-ios-a", "native-ios-b"]]
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: remote, zoneId: zone), "native-ios-a")
    }

    func testEmptyValueFallsThroughToNextTier() {
        // Empty per-platform string/array must not shadow a valid lower tier.
        let remote: [String: Any] = [
            "NATIVE_ZID_IOS": "",
            "NATIVE_ZID_ALL_IOS": [String](),
            "NATIVE_ZID": "native-shared",
        ]
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: remote, zoneId: zone), "native-shared")
    }
}
