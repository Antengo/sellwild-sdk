import XCTest
@testable import SellwildSDK

/// SellwildConfig's stored remote payload and value types, and
/// SellwildRemoteConfig's apply and public entry point. Payloads come from
/// the app-config factory.
final class SellwildConfigLogicTests: FailureCapturingTestCase {

    // MARK: remoteValues

    func testRemoteValuesParseTheStoredPayload() throws {
        let config = try AppConfigFactory.config(["GPID_BASE": "/1/app"])
        XCTAssertEqual(config.remoteValues?["GPID_BASE"] as? String, "/1/app")
        XCTAssertNil(SellwildConfig(partnerCode: "p").remoteValues, "nothing stored")
        capture.none()
    }

    func testStoredPayloadThatIsNotJSONIsReported() {
        var config = SellwildConfig(partnerCode: "p")
        config.remoteJSON = Data("{\"CODE\":".utf8)
        XCTAssertNil(config.remoteValues)
        let event = capture.only(.configRemoteValuesParse, label: .remoteConfig)
        XCTAssertEqual(event?.attributes["errName"], "NSCocoaErrorDomain(3840)")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    func testStoredPayloadThatIsNotAnObjectIsReported() throws {
        var config = SellwildConfig(partnerCode: "p")
        config.remoteJSON = try Factory.data([try AppConfigFactory.remote()])
        XCTAssertNil(config.remoteValues)
        let event = capture.only(.configRemoteValuesParse, label: .remoteConfig)
        XCTAssertEqual(event?.attributes["msg"], "stored remote config is not a JSON object")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    /// `remoteValues` is read on every ad load, feed load and refresh. A bad
    /// stored payload stays bad, so it is reported once per launch
    /// (FAILURES.md 9.1), for each way it can be bad.
    func testABadStoredPayloadIsReportedOncePerLaunch() throws {
        var notJSON = SellwildConfig(partnerCode: "p")
        notJSON.remoteJSON = Data("{\"CODE\":".utf8)
        for _ in 0..<3 { XCTAssertNil(notJSON.remoteValues) }
        capture.only(.configRemoteValuesParse, label: .remoteConfig)

        resetCapture()
        var notAnObject = SellwildConfig(partnerCode: "p")
        notAnObject.remoteJSON = try Factory.data([try AppConfigFactory.remote()])
        for _ in 0..<3 { XCTAssertNil(notAnObject.remoteValues) }
        XCTAssertNil(notJSON.remoteValues)
        XCTAssertEqual(capture.only(.configRemoteValuesParse, label: .remoteConfig)?.attributes["msg"],
                       "stored remote config is not a JSON object")
    }

    // MARK: Value types

    func testEveryAdSize() {
        XCTAssertEqual(AdSize.allCases.map(\.cgSize), [
            CGSize(width: 320, height: 50), CGSize(width: 300, height: 250), CGSize(width: 728, height: 90),
            CGSize(width: 300, height: 600), CGSize(width: 160, height: 600),
        ])
        XCTAssertEqual(AdSize.allCases.map(\.rawValue), AdSize.allCases.map { "\(Int($0.cgSize.width))x\(Int($0.cgSize.height))" })
    }

    func testOptionalConfigValues() {
        let s2s = PrebidServerConfig(accountId: "acct", endpoint: "https://prebid.sellwild.com/openrtb2/auction", bidders: ["ix"])
        XCTAssertEqual(s2s.timeout, 1500)
        XCTAssertNil(s2s.syncEndpoint)
        let s2sFull = PrebidServerConfig(accountId: "a", endpoint: "e", bidders: [], timeout: 900, syncEndpoint: "s")
        XCTAssertEqual(s2sFull.timeout, 900)
        XCTAssertEqual(s2sFull.syncEndpoint, "s")

        let growth = SellwildGrowthCodeConfig(enabled: true, partnerId: "gc", endpoint: "e", syncUrl: "u", sendMaid: false, ttlHours: 24)
        XCTAssertEqual(growth.partnerId, "gc")
        XCTAssertEqual(growth.ttlHours, 24)
        XCTAssertNil(SellwildGrowthCodeConfig().enabled)

        let localized = SellwildLocalizedListingsConfig(enabled: false, source: "s", baseUrl: "b", urlTemplate: "t", frequency: 25, forceState: "AL")
        XCTAssertEqual(localized.frequency, 25)
        XCTAssertEqual(localized.forceState, "AL")
        XCTAssertNil(SellwildLocalizedListingsConfig().baseUrl)
    }

    // MARK: SellwildSDK.apply

    func testApplyMapsEveryKnownKey() throws {
        let raw = try AppConfigFactory.remote([
            "NAME": "Full", "TITLE": "Shop", "COL1": "LLG", "BH_TAG": "bh", "LINK_TEXT": "More",
            "LINK_COLOR": "#123456", "BG_COLOR": "#000000", "MARGIN_BOTTOM": 4, "COLORS": ["#1", "#2"],
            "OVERLAY_TITLE": true, "WATERMARK": true, "BANNER_ZID": "b1", "BOTTOM_BANNER_ZID": "b2",
            "HIDE_BANNER_TOP": true, "HIDE_BANNER_BOTTOM": true, "GAM": "/1/gam", "AD_DISABLE_DISPLAY": true,
            "AD_REFRESH_MAX": 3, "AD_REFRESH_MAX_MOBILE": 5, "AD_REFRESH_INTERVAL": 45000, "MAX_FAILED_AUCTIONS": 4,
            "GPP_ENABLED": true, "TCF_VERSION": 2, "IAB_CATS": ["IAB1"], "ENABLE_FULLSCREEN_VIDEO": true,
            "VIDEO_TAKEOVERS_PER_SESSION": 2, "BOLTIVE_CLIENT_ID": "bc", "DEBUG": true, "PBS_DEBUG": true,
            "APP_BUNDLE_ID_IOS": "123", "APP_STORE_URL_IOS": "https://apps.apple.com/app/id123",
            "MOBILE_BANNER_ZID_IOS": "ios-banner", "MOBILE_ZID_IOS": ["ios-feed"],
        ])
        let c = SellwildSDK.apply(raw, to: SellwildConfig(partnerCode: "p"))
        XCTAssertEqual(c.name, "Full")
        XCTAssertEqual(c.title, "Shop")
        XCTAssertEqual(c.col1, "LLG")
        XCTAssertEqual(c.bhTag, "bh")
        XCTAssertEqual(c.linkText, "More")
        XCTAssertEqual(c.linkColor, "#123456")
        XCTAssertEqual(c.bgColor, "#000000")
        XCTAssertEqual(c.marginBottom, 4)
        XCTAssertEqual(c.colors, ["#1", "#2"])
        XCTAssertTrue(c.overlayTitle)
        XCTAssertTrue(c.watermark)
        XCTAssertEqual(c.bannerZid, "b1")
        XCTAssertEqual(c.bottomBannerZid, "b2")
        XCTAssertTrue(c.hideBannerTop)
        XCTAssertTrue(c.hideBannerBottom)
        XCTAssertEqual(c.gamTag, "/1/gam")
        XCTAssertTrue(c.adDisableDisplay)
        XCTAssertEqual(c.adRefreshMax, 3)
        XCTAssertEqual(c.adRefreshMaxMobile, 5)
        XCTAssertEqual(c.adRefreshInterval, 45)
        XCTAssertEqual(c.maxFailedAuctions, 4)
        XCTAssertTrue(c.gppEnabled)
        XCTAssertEqual(c.tcfVersion, 2)
        XCTAssertEqual(c.iabCats, ["IAB1"])
        XCTAssertTrue(c.enableFullscreenVideo)
        XCTAssertEqual(c.videoTakeoversPerSession, 2)
        XCTAssertEqual(c.boltiveClientId, "bc")
        XCTAssertTrue(c.debug)
        XCTAssertTrue(c.pbsDebug)
        XCTAssertEqual(c.appBundleId, "123", "the iOS key wins")
        XCTAssertEqual(c.appStoreUrl, "https://apps.apple.com/app/id123")
        XCTAssertEqual(c.mobileBannerZid, "ios-banner")
        XCTAssertEqual(c.mobileZids, ["ios-feed"])
    }

    func testPlatformWideZoneFallsBackForBothPlacements() throws {
        let raw = try AppConfigFactory.remote(["MOBILE_ZID_ALL_IOS": "ios-all", "MOBILE_ZID": ["shared"], "MOBILE_BANNER_ZID": "shared-banner"])
        let c = SellwildSDK.apply(raw, to: SellwildConfig(partnerCode: "p"))
        XCTAssertEqual(c.mobileZids, ["ios-all"])
        XCTAssertEqual(c.mobileBannerZid, "ios-all")

        let shared = SellwildSDK.apply(try AppConfigFactory.remote(["MOBILE_ZID": ["shared"], "MOBILE_BANNER_ZID": "shared-banner"]),
                                       to: SellwildConfig(partnerCode: "p"))
        XCTAssertEqual(shared.mobileZids, ["shared"])
        XCTAssertEqual(shared.mobileBannerZid, "shared-banner")
    }

    // MARK: Public configure

    func testPublicConfigureUsesTheEnvironment() async throws {
        let saved = SellwildSDK.environment
        defer { SellwildSDK.environment = saved }
        let session = StubURLProtocol.makeSession()
        defer { session.finishTasksAndInvalidate() }
        let raw = try AppConfigFactory.make()
        StubURLProtocol.handler = { _ in try .json(raw) }
        var booted: [String] = []
        SellwildSDK.environment = SellwildSDK.ConfigureEnvironment(
            session: session, makeURL: { URL(string: $0) },
            events: SellwildAPIClient(session: session, eventTransport: CapturingEventTransport().transport,
                                      eventClock: ManualEventClock().clock),
            bootstrap: { booted.append($0.partnerCode); return true }
        )

        let config = await SellwildSDK.configure(partnerCode: "weatherbug", slug: "weatherbug-weatherbug") { $0.appBundleId = "com.example" }
        XCTAssertEqual(config.listingsUrl, raw["LISTINGS"] as? String)
        XCTAssertEqual(config.appBundleId, "com.example", "overrides run last")
        XCTAssertEqual(booted, ["weatherbug"])
        XCTAssertEqual(StubURLProtocol.requests.first?.timeoutInterval, 5, "the default timeout")
        capture.none()
    }

    func testConfigURLAndRequest() throws {
        XCTAssertEqual(SellwildSDK.configURLString(partnerCode: "weatherbug", slug: "weatherbug-main"),
                       "https://widget.sellwild.com/app/weatherbug/weatherbug-main.json")
        let request = SellwildSDK.configRequest(url: try XCTUnwrap(URL(string: "https://widget.sellwild.com/app/a/b.json")), timeout: 2)
        XCTAssertEqual(request.timeoutInterval, 2)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "SellwildSDK/\(SellwildSDK.sdkVersion) (ios)")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testLiveEnvironmentBootstrapsPrebid() {
        // The live bootstrap is SellwildPrebidMobile.bootstrap itself; only
        // its identity is checked here (running it starts GMA and Prebid).
        let live = SellwildSDK.ConfigureEnvironment.live
        XCTAssertTrue(live.session === URLSession.shared)
        XCTAssertTrue(SellwildSDK.environment.events === SellwildAPIClient.shared)
        // The live URL builder is Foundation's own parser: no encoding added.
        XCTAssertEqual(live.makeURL("https://widget.sellwild.com/app/weatherbug/weatherbug.json")?.path,
                       "/app/weatherbug/weatherbug.json")
        XCTAssertEqual(live.makeURL("https://widget.sellwild.com/app/a b/c.json") == nil,
                       URL(string: "https://widget.sellwild.com/app/a b/c.json") == nil,
                       "a space is handled the way URL(string:) handles it on this OS")
    }
}
