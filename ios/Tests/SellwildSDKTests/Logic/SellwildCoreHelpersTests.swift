import XCTest
@testable import SellwildSDK

/// The small pure helpers under Core/: the Int conversion that cannot trap,
/// and the once-per-launch report latch.
final class SellwildCoreHelpersTests: XCTestCase {

    override func tearDown() {
        SellwildReportOnce.resetForTests()
        super.tearDown()
    }

    func testClampedInt() {
        let table: [(Double, Int?)] = [
            (0, 0), (25, 25), (12.9, 12), (-12.9, -12),
            (9_007_199_254_740_992, 9_007_199_254_740_992),
            (1e19, .max), (Double(Int.max), .max), (1e300, .max),
            (Double(Int.min), .min), (-1e19, .min), (-1e300, .min),
            (.infinity, nil), (-.infinity, nil), (.nan, nil),
        ]
        for (value, expected) in table {
            XCTAssertEqual(SellwildNumber.clampedInt(value), expected, "\(value)")
        }
    }

    func testReportOnceRemembersEachCodeAndScopeUntilANewLaunch() {
        SellwildReportOnce.resetForTests()
        XCTAssertTrue(SellwildReportOnce.first(.growthcodeConfigMissing))
        XCTAssertFalse(SellwildReportOnce.first(.growthcodeConfigMissing))
        XCTAssertTrue(SellwildReportOnce.first(.growthcodeConfigMissing, "zone 43"), "another scope")
        XCTAssertTrue(SellwildReportOnce.first(.localizedConfigInvalid), "another code")
        XCTAssertFalse(SellwildReportOnce.first(.growthcodeConfigMissing, "zone 43"))

        SellwildReportOnce.resetForTests()
        XCTAssertTrue(SellwildReportOnce.first(.growthcodeConfigMissing), "a new launch reports again")
    }
}
