import XCTest
import SellwildPrebidSDK
@testable import SellwildSDK

/// The Prebid fork only emits `imp.ext.skadn` when `Targeting.sourceapp` is set
/// (it must be the numeric App Store ID). The SDK stopped setting it in 1.5.0,
/// which silently dropped SKAdNetwork from every iOS bid request. Pin that the
/// app-identity step sets it again.
final class SellwildPrebidSkadnSourceAppTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Targeting.shared.sourceapp = nil
        Targeting.shared.itunesID = nil
    }

    override func tearDown() {
        Targeting.shared.sourceapp = nil
        Targeting.shared.itunesID = nil
        super.tearDown()
    }

    func testStoreURLSetsSkadnSourceAppToNumericStoreId() {
        SellwildPrebidMobile.applyAppIdentity(storeURL: "https://apps.apple.com/us/app/example/id123456789")
        XCTAssertEqual(Targeting.shared.sourceapp, "123456789")
        XCTAssertEqual(Targeting.shared.itunesID, "123456789")
    }

    func testNoStoreURLLeavesSourceAppUnset() {
        SellwildPrebidMobile.applyAppIdentity(storeURL: nil)
        XCTAssertNil(Targeting.shared.sourceapp)
    }

    func testStoreURLWithoutNumericIdLeavesSourceAppUnset() {
        SellwildPrebidMobile.applyAppIdentity(storeURL: "https://apps.apple.com/us/app/example")
        XCTAssertNil(Targeting.shared.sourceapp)
    }
}
