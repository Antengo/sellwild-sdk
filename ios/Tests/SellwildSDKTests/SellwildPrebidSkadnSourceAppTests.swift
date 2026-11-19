import XCTest
import SellwildPrebidSDK
@testable import SellwildSDK

/// The Prebid fork only emits `imp.ext.skadn` when `Targeting.sourceapp` is set
/// (it must be the numeric App Store ID). The SDK stopped setting it in 1.5.0,
/// which silently dropped SKAdNetwork from every iOS bid request. Pin that the
/// app-identity step sets it again.
final class SellwildPrebidSkadnSourceAppTests: XCTestCase {

    // Targeting.shared is process-global: save and restore everything touched.
    private var savedSourceApp: String?
    private var savedItunesID: String?
    private var savedStoreURL: String?

    override func setUp() {
        super.setUp()
        savedSourceApp = Targeting.shared.sourceapp
        savedItunesID = Targeting.shared.itunesID
        savedStoreURL = Targeting.shared.storeURL
        Targeting.shared.sourceapp = nil
        Targeting.shared.itunesID = nil
        Targeting.shared.storeURL = nil
    }

    override func tearDown() {
        Targeting.shared.sourceapp = savedSourceApp
        Targeting.shared.itunesID = savedItunesID
        Targeting.shared.storeURL = savedStoreURL
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

    func testNilStoreURLKeepsAnEarlierIdentity() {
        SellwildPrebidMobile.applyAppIdentity(storeURL: "https://apps.apple.com/us/app/example/id123456789")
        SellwildPrebidMobile.applyAppIdentity(storeURL: nil)
        XCTAssertEqual(Targeting.shared.sourceapp, "123456789")
        XCTAssertEqual(Targeting.shared.itunesID, "123456789")
        XCTAssertEqual(Targeting.shared.storeURL, "https://apps.apple.com/us/app/example/id123456789")
    }

    func testStoreURLWithoutNumericIdClearsAStaleId() {
        SellwildPrebidMobile.applyAppIdentity(storeURL: "https://apps.apple.com/us/app/example/id123456789")
        SellwildPrebidMobile.applyAppIdentity(storeURL: "https://apps.apple.com/us/app/other")
        XCTAssertNil(Targeting.shared.sourceapp)
        XCTAssertNil(Targeting.shared.itunesID)
        XCTAssertEqual(Targeting.shared.storeURL, "https://apps.apple.com/us/app/other")
    }
}
