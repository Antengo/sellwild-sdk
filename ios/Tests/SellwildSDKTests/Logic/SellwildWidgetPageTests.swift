import XCTest
@testable import SellwildSDK

/// The deprecated widget's page (`SellwildWidgetPage`): the element
/// attributes, the Prebid.js pre-config, the HTML, navigation errors, and the
/// bridge messages (from the bridge-message factory).
final class SellwildWidgetPageTests: XCTestCase {

    private func typedConfig() throws -> SellwildConfig {
        var config = try AppConfigFactory.config(partnerCode: "demo")
        config.listingsUrl = "https://cache.sellwild.com/listings-sm"
        config.adType = "GAMPrebid"
        config.gamTag = "/1/tag"
        config.gptProxyUrl = "https://gpt.example/proxy"
        config.disableGpt = true
        config.bannerZid = "10"
        config.bottomBannerZid = "11"
        config.mobileBannerZid = "12"
        config.mobileZids = ["43", "44"]
        config.hideBannerTop = true
        config.hideBannerBottom = true
        config.adRefreshMax = 3
        config.adRefreshMaxMobile = 2
        config.adRefreshInterval = 30
        config.boltive = true
        config.boltiveClientId = "bolt"
        config.lotame = true
        config.title = "Deals"
        config.linkText = "More"
        config.fontSize = 14
        config.colors = ["#111", "#222"]
        config.debug = true
        config.enableInterstitial = true
        config.enableFullscreenVideo = true
        config.interstitialsPerSession = 2
        config.videoTakeoversPerSession = 1
        return config
    }

    // MARK: Attributes

    func testTypedAttributesAreWrittenAndEmptyOnesLeftOut() throws {
        let attributes = SellwildWidgetPage.attributes(config: try typedConfig()).attributes
        for expected in [
            #"partner-code="demo""#, #"listings="https://cache.sellwild.com/listings-sm""#, #"customize="false""#,
            #"ad-type="GAMPrebid""#, #"gam-tag="/1/tag""#, #"gpt-proxy-url="https://gpt.example/proxy""#,
            #"disable-gpt="true""#, #"banner-zid="10""#, #"bottom-banner-zid="11""#, #"mobile-banner-zid="12""#,
            #"mobile-zid="43,44""#, #"hide-banner-top="true""#, #"hide-banner-bottom="true""#,
            #"ad-refresh-max="3""#, #"ad-refresh-max-mobile="2""#, #"ad-refresh-interval="30000""#,
            #"boltive="true""#, #"boltive-client-id="bolt""#, #"lotame="true""#, #"title="Deals""#,
            #"link-text="More""#, #"font-size="14""#, ##"colors="#111,#222""##, #"debug="true""#,
            #"enable-interstitial="true""#, #"enable-fullscreen-video="true""#,
            #"interstitials-per-session="2""#, #"video-takeovers-per-session="1""#,
        ] {
            XCTAssertTrue(attributes.contains(expected), expected)
        }

        var bare = SellwildConfig(partnerCode: "demo")
        bare.colors = []
        bare.fontSize = 0
        bare.interstitialsPerSession = 0
        let minimal = SellwildWidgetPage.attributes(config: bare).attributes
        XCTAssertTrue(minimal.contains(#"ad-type="PrebidOnly""#), "adType defaults so AdStack still loads Prebid")
        XCTAssertFalse(minimal.contains { $0.hasPrefix("gam-tag=") || $0.hasPrefix("mobile-zid=") || $0.hasPrefix("colors=")
            || $0.hasPrefix("boltive-client-id=") || $0.hasPrefix("font-size=") || $0.hasPrefix("debug=") })
    }

    func testRemoteValuesPassThroughExceptTypedKeysAndEmptyValues() throws {
        let config = try AppConfigFactory.config([
            "APP_THEME": "dark \"x\"", "APP_ON": true, "APP_OFF": false, "APP_NULL": NSNull(), "APP_EMPTY": "",
            "APP_COUNT": 3, "APP_LIST": ["a", "b"], "APP_MAP": ["k": "v"], "TITLE": "typed", "GAM": "/1/gam",
        ])
        let (attributes, dropped) = SellwildWidgetPage.attributes(config: config)
        XCTAssertTrue(attributes.contains(#"APP_THEME="dark &quot;x&quot;""#))
        XCTAssertTrue(attributes.contains(#"APP_ON="true""#))
        XCTAssertTrue(attributes.contains(#"APP_COUNT="3""#))
        XCTAssertTrue(attributes.contains(#"APP_LIST="[&quot;a&quot;,&quot;b&quot;]""#))
        XCTAssertTrue(attributes.contains(#"APP_MAP="{&quot;k&quot;:&quot;v&quot;}""#))
        XCTAssertFalse(attributes.contains { $0.hasPrefix("APP_OFF=") || $0.hasPrefix("APP_NULL=") || $0.hasPrefix("APP_EMPTY=") })
        XCTAssertFalse(attributes.contains { $0.hasPrefix("TITLE=") || $0.hasPrefix("GAM=") }, "typed keys are written once")
        XCTAssertTrue(dropped.isEmpty)
    }

    func testARemoteValueThatCannotBeWrittenIsLeftOut() throws {
        let config = try AppConfigFactory.config(["APP_LIST": ["a"], "APP_TEXT": "ok"])
        let (attributes, dropped) = SellwildWidgetPage.attributes(config: config) { _ in throw PlannedError() }
        XCTAssertTrue(attributes.contains(#"APP_TEXT="ok""#))
        XCTAssertFalse(attributes.contains { $0.hasPrefix("APP_LIST=") })
        XCTAssertTrue(dropped.map(\.name).contains("APP_LIST"), "every list and object is left out, not only APP_LIST")
        XCTAssertFalse(dropped.map(\.name).contains("APP_TEXT"))
        guard case .serialization(let error) = dropped.first(where: { $0.name == "APP_LIST" })?.problem else {
            return XCTFail("serialization")
        }
        XCTAssertEqual(error as? PlannedError, PlannedError())

        guard case .failure(.notJSON) = SellwildWidgetPage.remoteAttribute(name: "X", value: Date()) else {
            return XCTFail("a Date is not JSON")
        }
        XCTAssertEqual(try SellwildWidgetPage.remoteAttribute(name: "X", value: ["a"]).get(), #"X="[&quot;a&quot;]""#)
    }

    // MARK: Pre-config and page

    func testPreConfigUsesTheNumericStoreIdAndTheS2SConfig() throws {
        var config = try AppConfigFactory.config(partnerCode: "demo")
        config.appStoreUrl = "https://apps.apple.com/us/app/x/id281940292"
        config.appBundleId = "com.example.app"
        config.prebidServer = PrebidServerConfig(accountId: "acct", endpoint: "https://pbs/auction",
                                                 bidders: ["ix", "openx"], timeout: 900, syncEndpoint: "https://pbs/sync")
        config.debug = true
        let script = SellwildWidgetPage.prebidPreConfigScript(config: config)
        XCTAssertTrue(script.contains(#""bundle": "281940292""#))
        XCTAssertFalse(script.contains("com.example.app"), "the store id wins over the configured bundle")
        XCTAssertTrue(script.contains(#""storeurl": "https://apps.apple.com/us/app/x/id281940292""#))
        XCTAssertTrue(script.contains(#""bidders": ["ix", "openx"]"#))
        XCTAssertTrue(script.contains(#""timeout": 900"#))
        XCTAssertTrue(script.contains(#""syncEndpoint": {"p1Consent": "https://pbs/sync""#))
        XCTAssertTrue(script.contains(#", "debug": true"#))
    }

    func testPreConfigFallsBackToTheBundleAndLeavesOutWhatIsNotSet() throws {
        var config = try AppConfigFactory.config(partnerCode: "demo")
        config.appBundleId = "com.example.app"
        config.appStoreUrl = ""
        config.prebidServer = PrebidServerConfig(accountId: "acct", endpoint: "https://pbs/auction", bidders: ["ix"])
        let script = SellwildWidgetPage.prebidPreConfigScript(config: config)
        XCTAssertTrue(script.contains(#""bundle": "com.example.app""#))
        XCTAssertFalse(script.contains("storeurl"))
        XCTAssertTrue(script.contains("s2sConfig"))
        XCTAssertFalse(script.contains("syncEndpoint"))
        XCTAssertFalse(script.contains(#""debug""#))

        config.appBundleId = ""
        config.prebidServer = nil
        let bare = SellwildWidgetPage.prebidPreConfigScript(config: config)
        XCTAssertFalse(bare.contains("bundle"))
        XCTAssertFalse(bare.contains("s2sConfig"))
        XCTAssertTrue(bare.contains(#""publisher": {"id": "demo"}"#))
    }

    func testPageLoadsTheWidgetBundleAndTheBridgeScript() throws {
        var config = try AppConfigFactory.config(partnerCode: "demo")
        let html = SellwildWidgetPage.html(config: config, attributes: [#"a="1""#, #"b="2""#])
        XCTAssertTrue(html.contains(#"<script async src="https://widget.sellwild.com/partner.js"></script>"#))
        XCTAssertTrue(html.contains("a=\"1\"\n    b=\"2\""))
        XCTAssertTrue(html.contains("window.webkit.messageHandlers.sellwildWidget.postMessage"))
        XCTAssertTrue(html.contains("window.__sellwildBridgeFailures = (window.__sellwildBridgeFailures || 0) + 1;"),
                      "a message the bridge cannot post is counted, not swallowed")
        XCTAssertTrue(html.contains("window.pbjs.setConfig"))
        config.widgetJsUrl = "https://cdn.example/partner.js"
        XCTAssertTrue(SellwildWidgetPage.html(config: config, attributes: []).contains(#"src="https://cdn.example/partner.js""#))
        XCTAssertEqual(SellwildWidgetPage.baseURL?.absoluteString, "https://widget.sellwild.com")
    }

    func testOnlyAMainFrameHTTPErrorStatusIsAFailure() throws {
        let url = try XCTUnwrap(URL(string: "https://widget.sellwild.com/page"))
        func http(_ status: Int) throws -> URLResponse {
            try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        }
        XCTAssertEqual(SellwildWidgetPage.httpFailureStatus(try http(400), isForMainFrame: true), 400)
        XCTAssertEqual(SellwildWidgetPage.httpFailureStatus(try http(503), isForMainFrame: true), 503)
        XCTAssertNil(SellwildWidgetPage.httpFailureStatus(try http(399), isForMainFrame: true))
        XCTAssertNil(SellwildWidgetPage.httpFailureStatus(try http(200), isForMainFrame: true))
        XCTAssertNil(SellwildWidgetPage.httpFailureStatus(try http(500), isForMainFrame: false),
                     "a sub-frame (an ad iframe) is not the widget page")
        let notHTTP = URLResponse(url: url, mimeType: "text/html", expectedContentLength: 0, textEncodingName: nil)
        XCTAssertNil(SellwildWidgetPage.httpFailureStatus(notHTTP, isForMainFrame: true),
                     "the page's own HTML string has no status")
    }

    func testCancelledNavigationsAreNotFailures() {
        XCTAssertFalse(SellwildWidgetPage.isNavigationFailure(URLError(.cancelled)))
        XCTAssertFalse(SellwildWidgetPage.isNavigationFailure(NSError(domain: "WebKitErrorDomain", code: 102)))
        XCTAssertTrue(SellwildWidgetPage.isNavigationFailure(URLError(.notConnectedToInternet)))
        XCTAssertTrue(SellwildWidgetPage.isNavigationFailure(NSError(domain: "WebKitErrorDomain", code: 101)))
    }

    // MARK: Bridge messages

    private func parse(_ variant: String, _ overrides: [String: Any] = [:]) throws -> SellwildWidgetPage.Parsed {
        SellwildWidgetPage.parse(body: try BridgeMessageFactory.text(BridgeMessageFactory.variant(variant, overrides)))
    }

    func testEveryValidMessageParsesWithoutAProblem() throws {
        guard case .listingClick(let byURL)? = try parse("listing-click-url").message else { return XCTFail("url click") }
        XCTAssertEqual(byURL.url, "https://sellwild.com/listing/105140231")
        XCTAssertEqual(byURL.id, "", "a stub with only the URL")

        let stub = try parse("listing-click-stub")
        guard case .listingClick(let listing)? = stub.message else { return XCTFail("listing click") }
        XCTAssertEqual(listing.id, "105140231", "the full listing wins over the URL")
        XCTAssertNil(stub.problem)

        guard case .adImpression(let zone)? = try parse("ad-impression-text-zone").message else { return XCTFail("impression") }
        XCTAssertEqual(zone, "43")
        guard case .adImpression(let numeric)? = try parse("ad-impression-number-zone").message else { return XCTFail("impression") }
        XCTAssertEqual(numeric, "", "known drift: a number zone reads as \"\" (Android keeps \"43\")")
        guard case .adImpression(let none)? = try parse("ad-impression-no-zone").message else { return XCTFail("impression") }
        XCTAssertEqual(none, "")

        guard case .loaded? = try parse("widget-loaded").message else { return XCTFail("loaded") }
        guard case .error(let message)? = try parse("error").message else { return XCTFail("error") }
        XCTAssertEqual(message, "Uncaught TypeError: Cannot read properties of undefined")
        guard case .error(nil)? = try parse("error", ["message": Factory.remove]).message else { return XCTFail("no text") }

        for name in try BridgeMessageFactory.variantNames() {
            XCTAssertNil(try parse(name).problem, name)
        }
    }

    func testAListingThatDoesNotDecodeFallsBackToItsURLAndIsReported() throws {
        let parsed = try parse("listing-click-stub", ["listing": ["title": 5]])
        guard case .listingClick(let listing)? = parsed.message else { return XCTFail("the URL still opens") }
        XCTAssertEqual(listing.url, "https://sellwild.com/listing/105140231")
        XCTAssertEqual(parsed.problem?.code, .bridgeMessageInvalid)
        XCTAssertEqual(parsed.problem?.message, "LISTING_CLICK listing could not be decoded")
        XCTAssertNotNil(parsed.problem?.error)

        let noURL = try parse("listing-click-stub", ["listing": ["title": 5], "url": Factory.remove])
        XCTAssertNil(noURL.message)
        XCTAssertEqual(noURL.problem?.code, .bridgeMessageInvalid)
    }

    func testBrokenMessagesAreReportedWithTheirCode() throws {
        let body = try Factory.offSchema(because: "the page posted an object, not JSON text") { try BridgeMessageFactory.make() }
        XCTAssertEqual(SellwildWidgetPage.parse(body: body).problem?.code, .bridgeMessageInvalid)

        let notJSON = SellwildWidgetPage.parse(body: "{not json")
        XCTAssertEqual(notJSON.problem?.code, .bridgeMessageParse)
        XCTAssertNotNil(notJSON.problem?.error)
        XCTAssertNil(notJSON.message)

        XCTAssertEqual(SellwildWidgetPage.parse(body: "[1,2]").problem?.message, "bridge message is not a JSON object")

        let noType = try Factory.offSchema(because: "a message with no type") {
            try BridgeMessageFactory.make(["type": Factory.remove])
        }
        XCTAssertEqual(SellwildWidgetPage.parse(body: try BridgeMessageFactory.text(noType)).problem?.message, "bridge message has no type")

        let unknown = try Factory.offSchema(because: "a type the bridge does not send") {
            try BridgeMessageFactory.make(["type": "RESIZE"])
        }
        let unsupported = SellwildWidgetPage.parse(body: try BridgeMessageFactory.text(unknown))
        XCTAssertEqual(unsupported.problem?.code, .bridgeMessageUnsupported)
        XCTAssertNil(unsupported.message)

        let listingText = try Factory.offSchema(because: "listing must be an object") {
            try BridgeMessageFactory.variant("listing-click-url", ["listing": "105140231"])
        }
        let wrongListing = SellwildWidgetPage.parse(body: try BridgeMessageFactory.text(listingText))
        XCTAssertEqual(wrongListing.problem?.message, "LISTING_CLICK listing is not an object")
        guard case .listingClick? = wrongListing.message else { return XCTFail("the URL still opens") }

        let empty = try BridgeMessageFactory.variant("listing-click-url", ["url": Factory.remove])
        let nothing = SellwildWidgetPage.parse(body: try BridgeMessageFactory.text(empty))
        XCTAssertNil(nothing.message)
        XCTAssertEqual(nothing.problem?.message, "LISTING_CLICK has no listing or url")
    }
}
