import XCTest
@testable import SellwildSDK

final class SellwildRemoteConfigTests: XCTestCase {

    func testApplyPopulatesIdentityFields() {
        let base = SellwildConfig(partnerCode: "weatherbug")
        let raw: [String: Any] = [
            "CODE": "weatherbug",
            "SLUG": "weatherbug-main",
            "NAME": "WeatherBug",
            "LISTINGS": "https://api.sellwild.com/widget/listings?partner=weatherbug",
        ]
        let merged = SellwildSDK.apply(raw, to: base)
        XCTAssertEqual(merged.partnerCode, "weatherbug")
        XCTAssertEqual(merged.slug, "weatherbug-main")
        XCTAssertEqual(merged.name, "WeatherBug")
        XCTAssertEqual(
            merged.listingsUrl,
            "https://api.sellwild.com/widget/listings?partner=weatherbug"
        )
    }

    func testApplyPopulatesAdZonesAndRefresh() {
        let base = SellwildConfig(partnerCode: "weatherbug")
        let raw: [String: Any] = [
            "MOBILE_ZID": ["12345", "67890"],
            "AD_REFRESH_INTERVAL": 30.0,
            "ENABLE_INTERSTITIAL": true,
            "INTERSTITIALS_PER_SESSION": 2,
        ]
        let merged = SellwildSDK.apply(raw, to: base)
        XCTAssertEqual(merged.mobileZids, ["12345", "67890"])
        XCTAssertEqual(merged.adRefreshInterval, 30.0)
        XCTAssertTrue(merged.enableInterstitial)
        XCTAssertEqual(merged.interstitialsPerSession, 2)
    }

    func testApplyPopulatesAppIdentity() {
        let base = SellwildConfig(partnerCode: "weatherbug")
        let raw: [String: Any] = [
            "APP_BUNDLE_ID": "com.aws.android",
            "APP_STORE_URL": "https://apps.apple.com/app/id123",
        ]
        let merged = SellwildSDK.apply(raw, to: base)
        XCTAssertEqual(merged.appBundleId, "com.aws.android")
        XCTAssertEqual(merged.appStoreUrl, "https://apps.apple.com/app/id123")
    }

    func testApplyIgnoresUnknownKeys() {
        let base = SellwildConfig(partnerCode: "weatherbug")
        let raw: [String: Any] = ["FUTURE_FEATURE_FLAG": true]
        let merged = SellwildSDK.apply(raw, to: base)
        XCTAssertEqual(merged.partnerCode, "weatherbug")
    }

    func testEffectiveListingsUrlFallsBackWhenUnset() {
        let config = SellwildConfig(partnerCode: "weatherbug")
        XCTAssertNil(config.listingsUrl)
        XCTAssertEqual(
            config.effectiveListingsUrl,
            "https://api.sellwild.com/widget/listings?partner=weatherbug"
        )
    }

    func testEffectiveListingsUrlPrefersExplicitValue() {
        var config = SellwildConfig(partnerCode: "weatherbug")
        config.listingsUrl = "https://custom.example.com/listings"
        XCTAssertEqual(config.effectiveListingsUrl, "https://custom.example.com/listings")
    }

    func testPartnerCodeOnlyInitializerCompiles() {
        let config = SellwildConfig(partnerCode: "weatherbug")
        XCTAssertEqual(config.partnerCode, "weatherbug")
        XCTAssertNil(config.listingsUrl)
    }
}
