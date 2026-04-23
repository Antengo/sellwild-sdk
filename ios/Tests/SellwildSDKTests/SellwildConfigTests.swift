import XCTest
@testable import SellwildSDK

final class SellwildConfigTests: XCTestCase {

    func testDefaultConfigValues() {
        let config = SellwildConfig(
            partnerCode: "test_partner",
            listingsUrl: "https://api.sellwild.com/widget/listings?partner=test"
        )

        XCTAssertEqual(config.partnerCode, "test_partner")
        XCTAssertEqual(config.titleSize, 16)
        XCTAssertEqual(config.fontSize, 13)
        XCTAssertFalse(config.boltive)
        XCTAssertFalse(config.lotame)
        XCTAssertFalse(config.debug)
        XCTAssertEqual(config.adRefreshInterval, 30.0)
        XCTAssertFalse(config.hideBannerTop)
        XCTAssertFalse(config.hideBannerBottom)
    }

    func testConfigCodable() throws {
        var config = SellwildConfig(
            partnerCode: "mypartner",
            listingsUrl: "https://api.sellwild.com/widget/listings?partner=mypartner"
        )
        config.title = "Shop Now"
        config.debug = true
        config.boltive = true
        config.boltiveClientId = "antengo"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SellwildConfig.self, from: data)

        XCTAssertEqual(decoded.partnerCode, config.partnerCode)
        XCTAssertEqual(decoded.title, config.title)
        XCTAssertEqual(decoded.debug, config.debug)
        XCTAssertEqual(decoded.boltiveClientId, config.boltiveClientId)
    }

    func testAdSizeCGSize() {
        XCTAssertEqual(AdSize.banner320x50.cgSize, CGSize(width: 320, height: 50))
        XCTAssertEqual(AdSize.mrec300x250.cgSize, CGSize(width: 300, height: 250))
        XCTAssertEqual(AdSize.leaderboard728x90.cgSize, CGSize(width: 728, height: 90))
    }
}
