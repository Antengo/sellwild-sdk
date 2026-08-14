import XCTest
import UIKit
@testable import SellwildSDK

/// Unit tests for the OpenRTB `device.devicetype` mapping emitted on every
/// native Prebid auction. The iOS Prebid fork does not populate `devicetype`
/// (Android does end-to-end), so `SellwildPrebidMobile` injects it via the
/// global ORTB config. These pin the IAB enum mapping independent of a live
/// device idiom.
final class SellwildPrebidDeviceTypeTests: XCTestCase {

    func testPhoneMapsToIABPhone() {
        // IAB OpenRTB device.devicetype: 4 = PHONE.
        XCTAssertEqual(SellwildPrebidMobile.deviceType(for: .phone), 4)
    }

    func testPadMapsToIABTablet() {
        // IAB OpenRTB device.devicetype: 5 = TABLET.
        XCTAssertEqual(SellwildPrebidMobile.deviceType(for: .pad), 5)
    }

    func testUnspecifiedFallsBackToGenericMobile() {
        // Unknown idiom → 1 (MOBILE/TABLET) generic-mobile fallback.
        XCTAssertEqual(SellwildPrebidMobile.deviceType(for: .unspecified), 1)
    }

    func testExoticIdiomsFallBackToGenericMobile() {
        // tv / carPlay (and any future idiom) also fall back to 1 rather than
        // dropping the field — a value beats an omission for buyer targeting.
        XCTAssertEqual(SellwildPrebidMobile.deviceType(for: .tv), 1)
        XCTAssertEqual(SellwildPrebidMobile.deviceType(for: .carPlay), 1)
    }
}
