import XCTest
@testable import SellwildSDK

/// `SellwildAdSizes.renderedSize`: a bid with no `w`/`h` reports 0×0 from the
/// prebidOnly render callback; the host must get the primary size instead.
final class SellwildAdSizesTests: XCTestCase {

    private let mrec = CGSize(width: 300, height: 250)

    func testKeepsReportedSize() {
        XCTAssertEqual(SellwildAdSizes.renderedSize(reported: CGSize(width: 320, height: 50), primary: mrec),
                       CGSize(width: 320, height: 50))
    }

    func testZeroSizeFallsBackToPrimary() {
        XCTAssertEqual(SellwildAdSizes.renderedSize(reported: .zero, primary: mrec), mrec)
    }

    func testHalfZeroSizeFallsBackToPrimary() {
        XCTAssertEqual(SellwildAdSizes.renderedSize(reported: CGSize(width: 300, height: 0), primary: mrec), mrec)
        XCTAssertEqual(SellwildAdSizes.renderedSize(reported: CGSize(width: 0, height: 250), primary: mrec), mrec)
    }
}
