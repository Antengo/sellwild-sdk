import XCTest
@testable import SellwildSDK

/// Unit tests for `SellwildNative.resolveConfigId` — the precedence that picks
/// the native placement id, independent of the Prebid fork request/render.
///
/// Chain: NATIVE_ZID_IOS → NATIVE_ZID_ALL_IOS → NATIVE_ZID → <mobile zoneId>.
final class SellwildNativeTests: XCTestCase {

    private let zone = "banner-zone-43"

    func testFallsBackToZoneWhenNoNativeKeys() throws {
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: nil, zoneId: zone), zone)
        XCTAssertEqual(
            SellwildNative.resolveConfigId(remoteValues: try AppConfigFactory.remote(["CODE": "weatherbug"]), zoneId: zone),
            zone
        )
    }

    func testSharedNativeKeyUsedWhenNoPlatformKeys() throws {
        XCTAssertEqual(
            SellwildNative.resolveConfigId(remoteValues: try AppConfigFactory.remote(["NATIVE_ZID": "native-shared"]), zoneId: zone),
            "native-shared"
        )
    }

    func testPlatformAllBeatsShared() throws {
        let remote = try AppConfigFactory.remote([
            "NATIVE_ZID_ALL_IOS": "native-ios-all",
            "NATIVE_ZID": "native-shared",
        ])
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: remote, zoneId: zone), "native-ios-all")
    }

    func testPerPlatformBeatsEverything() throws {
        let remote = try AppConfigFactory.remote([
            "NATIVE_ZID_IOS": "native-ios",
            "NATIVE_ZID_ALL_IOS": "native-ios-all",
            "NATIVE_ZID": "native-shared",
        ])
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: remote, zoneId: zone), "native-ios")
    }

    func testArrayValueTakesFirstNonEmpty() throws {
        let remote = try AppConfigFactory.remote(["NATIVE_ZID_IOS": ["", "native-ios-a", "native-ios-b"]])
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: remote, zoneId: zone), "native-ios-a")
    }

    func testEmptyValueFallsThroughToNextTier() throws {
        // Empty per-platform string/array must not shadow a valid lower tier.
        let remote = try AppConfigFactory.remote([
            "NATIVE_ZID_IOS": "",
            "NATIVE_ZID_ALL_IOS": [String](),
            "NATIVE_ZID": "native-shared",
        ])
        XCTAssertEqual(SellwildNative.resolveConfigId(remoteValues: remote, zoneId: zone), "native-shared")
    }
}
