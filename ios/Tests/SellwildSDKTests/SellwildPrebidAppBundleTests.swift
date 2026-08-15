import XCTest
@testable import SellwildSDK

/// Unit tests for the OpenRTB `app.bundle` derivation. On iOS/iPadOS `app.bundle`
/// must be the numeric App Store ID (buyers key on it), parsed from the store URL —
/// NOT the reverse-DNS bundle the app carries. Both the native path
/// (`SellwildPrebidMobile`) and the WebView widget (`SellwildWidgetView`) rely on
/// `appStoreId(from:)` for this, so pin its behavior here.
final class SellwildPrebidAppBundleTests: XCTestCase {

    func testParsesNumericAppStoreId() {
        XCTAssertEqual(
            SellwildPrebidMobile.appStoreId(from: "https://apps.apple.com/us/app/weatherbug/id281940292"),
            "281940292"
        )
    }

    func testParsesIdWithTrailingSlashQueryOrFragment() {
        XCTAssertEqual(SellwildPrebidMobile.appStoreId(from: "https://apps.apple.com/app/id123456/"), "123456")
        XCTAssertEqual(SellwildPrebidMobile.appStoreId(from: "https://apps.apple.com/app/id123456?mt=8"), "123456")
        XCTAssertEqual(SellwildPrebidMobile.appStoreId(from: "https://apps.apple.com/app/id123456#x"), "123456")
    }

    func testLegacyItunesHostAlsoParses() {
        XCTAssertEqual(SellwildPrebidMobile.appStoreId(from: "https://itunes.apple.com/us/app/x/id999"), "999")
    }

    func testNilWhenNoIdSegment() {
        XCTAssertNil(SellwildPrebidMobile.appStoreId(from: "https://apps.apple.com/us/app/weatherbug"))
        XCTAssertNil(SellwildPrebidMobile.appStoreId(from: nil))
        XCTAssertNil(SellwildPrebidMobile.appStoreId(from: ""))
    }

    func testDoesNotFalseMatchIdInsideSlug() {
        // Anchored on a URL boundary: "idea-app" (no digit after id) and a trailing
        // non-boundary char must NOT be treated as an app id.
        XCTAssertNil(SellwildPrebidMobile.appStoreId(from: "https://apps.apple.com/app/idea-app/foo"))
        XCTAssertNil(SellwildPrebidMobile.appStoreId(from: "https://apps.apple.com/app/id281940292abc"))
    }
}
