import XCTest
@testable import SellwildSDK

final class SellwildRemoteConfigTests: XCTestCase {

    func testApplyPopulatesIdentityFields() {
        let base = SellwildConfig(partnerCode: "weatherbug")
        let raw: [String: Any] = [
            "CODE": "weatherbug",
            "SLUG": "weatherbug-main",
            "NAME": "WeatherBug",
            "LISTINGS": "https://cache.sellwild.com/listings-img-data-sm",
        ]
        let merged = SellwildSDK.apply(raw, to: base)
        XCTAssertEqual(merged.partnerCode, "weatherbug")
        XCTAssertEqual(merged.slug, "weatherbug-main")
        XCTAssertEqual(merged.name, "WeatherBug")
        XCTAssertEqual(
            merged.listingsUrl,
            "https://cache.sellwild.com/listings-img-data-sm"
        )
    }

    func testApplyPopulatesAdZonesAndRefresh() {
        let base = SellwildConfig(partnerCode: "weatherbug")
        let raw: [String: Any] = [
            "MOBILE_ZID": ["12345", "67890"],
            // AD_REFRESH_INTERVAL is milliseconds (matches web + CMS); iOS stores
            // it as seconds, so 30000 ms → 30.0 s.
            "AD_REFRESH_INTERVAL": 30000.0,
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
        // With no explicit listingsUrl, the SDK falls back to the general
        // listings cache (not a partner-scoped URL).
        XCTAssertEqual(
            config.effectiveListingsUrl,
            "https://cache.sellwild.com/listings-img-data-sm"
        )
        XCTAssertEqual(config.effectiveListingsUrl, SellwildConfig.defaultListingsCacheURL)
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

    /// Verifies remote-config passthrough: arbitrary CDN keys (including
    /// bidders the SDK was never built to know about — MEDIANET, AMX, SOVRN)
    /// must surface via `remoteValues` so the WebView attribute serializer
    /// can forward them to the widget.
    func testRemoteJSONExposesUnmappedKeys() throws {
        var config = SellwildConfig(partnerCode: "weatherbug")
        let payload: [String: Any] = [
            "CODE": "weatherbug",
            "MEDIANET": ["cid": "8CU123ABC"],
            "AMX": ["tagId": "amx-tag-1"],
            "SOVRN": ["tagid": 12345],
            "ONETAG": ["pubId": "abc"],
            "YIELDMO": ["placementId": "ym-1"],
        ]
        config.remoteJSON = try JSONSerialization.data(withJSONObject: payload)

        let values = try XCTUnwrap(config.remoteValues)
        XCTAssertEqual((values["MEDIANET"] as? [String: Any])?["cid"] as? String, "8CU123ABC")
        XCTAssertEqual((values["AMX"] as? [String: Any])?["tagId"] as? String, "amx-tag-1")
        XCTAssertEqual((values["SOVRN"] as? [String: Any])?["tagid"] as? Int, 12345)
        XCTAssertNotNil(values["ONETAG"])
        XCTAssertNotNil(values["YIELDMO"])
    }
}
