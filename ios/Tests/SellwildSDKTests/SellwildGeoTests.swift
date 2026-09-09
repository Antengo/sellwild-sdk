import XCTest
@testable import SellwildSDK

/// Unit tests for `SellwildGeo` — the North America alpha-2 → alpha-3 country
/// map used to seed `device.geo.country` from the CloudFront viewer header, and
/// the `ortbGeoDict` serialization. All pure, independent of the network path.
final class SellwildGeoTests: XCTestCase {

    // MARK: northAmericaAlpha3

    func testNorthAmericaCoreCountries() {
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "US"), "USA")
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "CA"), "CAN")
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "MX"), "MEX")
    }

    func testNorthAmericaExtendedCountries() {
        // Central America + rest of Northern America are mapped too.
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "GT"), "GTM")
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "CR"), "CRI")
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "PA"), "PAN")
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "GL"), "GRL")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "us"), "USA")
        XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: "Mx"), "MEX")
    }

    func testOutsideNorthAmericaReturnsNil() {
        // Anything outside the NA set is skipped (not sent unmapped).
        XCTAssertNil(SellwildGeo.northAmericaAlpha3(alpha2: "GB"))
        XCTAssertNil(SellwildGeo.northAmericaAlpha3(alpha2: "IN"))
        XCTAssertNil(SellwildGeo.northAmericaAlpha3(alpha2: "DE"))
        XCTAssertNil(SellwildGeo.northAmericaAlpha3(alpha2: ""))
    }

    // MARK: ortbGeoDict

    func testOrtbGeoDictMapsCountryAndRegion() {
        let geo = SellwildGeo(country: "USA", state: "NY")
        let dict = geo.ortbGeoDict
        XCTAssertEqual(dict["country"] as? String, "USA")
        XCTAssertEqual(dict["region"] as? String, "NY")   // state -> region
    }
}
