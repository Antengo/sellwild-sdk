import XCTest
import SellwildPrebidSDK
@testable import SellwildSDK

/// The pure ad helpers around the auction: gpid serialization, the URL
/// allow-list, bridged geo, native and outstream-video settings. Remote
/// values come from the app-config factory; Prebid objects are built locally
/// and never loaded.
final class SellwildAdLogicTests: FailureCapturingTestCase {

    // MARK: SellwildGpid

    func testImpExtWithAValueJSONCannotHoldIsReportedAndSendsNoGpid() {
        XCTAssertNil(SellwildGpid.impExtJSON(gpid: "/1234/app#1", bidderParams: ["IX": ["when": Date()]]))
        let event = capture.only(.adGpidException, label: .banner)
        XCTAssertEqual(event?.attributes["errName"], "ImpExtError")
        XCTAssertEqual(event?.attributes["msg"], "imp.ext could not be serialized, so no gpid is sent: a bidder param is not a JSON value")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    func testImpExtWithJSONValuesReportsNothing() throws {
        let json = try XCTUnwrap(SellwildGpid.impExtJSON(gpid: "g", bidderParams: ["IX": ["siteId": "1"]]))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let ext = try XCTUnwrap(object["ext"] as? [String: Any])
        XCTAssertEqual(ext["gpid"] as? String, "g")
        XCTAssertNotNil((ext["prebid"] as? [String: Any])?["bidder"] as? [String: Any])
        XCTAssertNil(SellwildGpid.impExtJSON(gpid: nil), "nothing to emit")
        capture.none()
    }

    // MARK: SellwildSafeURL

    func testOnlyHTTPAndHTTPSAreOpened() {
        XCTAssertEqual(SellwildSafeURL.external("https://sellwild.com/a")?.host, "sellwild.com")
        XCTAssertEqual(SellwildSafeURL.external("HTTP://sellwild.com")?.scheme, "HTTP")
        XCTAssertNil(SellwildSafeURL.external(nil))
        XCTAssertNil(SellwildSafeURL.external("tel:5551234"))
        XCTAssertNil(SellwildSafeURL.external("file:///etc/hosts"))
        XCTAssertNil(SellwildSafeURL.external("no scheme"))
        XCTAssertNil(SellwildSafeURL.external("relative/path"))
        XCTAssertEqual(SellwildSafeURL.imageURL("https://cache.sellwild.com/a.png")?.path, "/a.png")
        XCTAssertNil(SellwildSafeURL.imageURL("data:image/png;base64,AAAA"))
        XCTAssertEqual(SellwildSafeURL.maxImageBytes, 8 * 1024 * 1024)
    }

    // MARK: SellwildGeo

    func testBridgedGeoKeepsKnownFieldsAndClearsOnEmpty() throws {
        let geo = try XCTUnwrap(SellwildGeo(bridged: [
            "country": "USA", "state": "GA", "city": "Atlanta", "zip": "30301", "metro": "524",
            "lat": 33.7, "lon": -84.4, "type": 2, "ignored": true,
        ]))
        XCTAssertEqual(geo, SellwildGeo(country: "USA", state: "GA", city: "Atlanta", zip: "30301", metro: "524",
                                        lat: 33.7, lon: -84.4, type: 2))
        let dict = geo.ortbGeoDict
        XCTAssertEqual(dict["city"] as? String, "Atlanta")
        XCTAssertEqual(dict["zip"] as? String, "30301")
        XCTAssertEqual(dict["metro"] as? String, "524")
        XCTAssertEqual(dict["lat"] as? Double, 33.7)
        XCTAssertEqual(dict["lon"] as? Double, -84.4)
        XCTAssertEqual(dict["type"] as? Int, 2)
        XCTAssertNil(SellwildGeo(bridged: [:]), "{} clears geo")
        XCTAssertNil(SellwildGeo(bridged: ["state": "", "lat": "not a number"]), "no usable field")
        XCTAssertTrue(SellwildGeo(country: "", state: "").ortbGeoDict.isEmpty)
    }

    func testEveryNorthAmericanCountry() {
        let map = ["US": "USA", "CA": "CAN", "MX": "MEX", "GT": "GTM", "BZ": "BLZ", "SV": "SLV", "HN": "HND",
                   "NI": "NIC", "CR": "CRI", "PA": "PAN", "GL": "GRL", "BM": "BMU", "PM": "SPM"]
        for (alpha2, alpha3) in map {
            XCTAssertEqual(SellwildGeo.northAmericaAlpha3(alpha2: alpha2.lowercased()), alpha3, alpha2)
        }
        XCTAssertNil(SellwildGeo.northAmericaAlpha3(alpha2: "FR"))
    }

    func testGeoStoreIsProcessWide() {
        let saved = SellwildGeoStore.current
        defer { SellwildGeoStore.current = saved }
        SellwildGeoStore.current = SellwildGeo(state: "TX")
        XCTAssertEqual(SellwildGeoStore.current?.state, "TX")
        SellwildGeoStore.current = nil
        XCTAssertNil(SellwildGeoStore.current)
    }

    // MARK: SellwildNative

    func testNativeEnableFlags() throws {
        XCTAssertFalse(SellwildNative.isEnabled(remoteValues: nil, zoneId: "43"))
        XCTAssertTrue(SellwildNative.isEnabled(remoteValues: try AppConfigFactory.remote(["NATIVE_ENABLED": "TRUE"]), zoneId: nil))
        XCTAssertTrue(SellwildNative.isEnabled(remoteValues: try AppConfigFactory.remote(["NATIVE_ENABLED": 2]), zoneId: nil))
        let byZone = try AppConfigFactory.remote(["NATIVE_ENABLED": false, "NATIVE_ENABLED_BY_ZONE": ["43": "on", "280": 0]])
        XCTAssertTrue(SellwildNative.isEnabled(remoteValues: byZone, zoneId: "43"))
        XCTAssertFalse(SellwildNative.isEnabled(remoteValues: byZone, zoneId: "280"))
        XCTAssertFalse(SellwildNative.isEnabled(remoteValues: byZone, zoneId: "999"))
        let listFlag = try Factory.offSchema(because: "a NATIVE_ENABLED_BY_ZONE value must be a flag, not a list") {
            try AppConfigFactory.remote(["NATIVE_ENABLED_BY_ZONE": ["43": ["x"]]])
        }
        XCTAssertFalse(SellwildNative.isEnabled(remoteValues: listFlag, zoneId: "43"), "ignored, as before")
    }

    func testNativeMaxHeight() throws {
        XCTAssertEqual(SellwildNative.maxHeight(remoteValues: nil, zoneId: "43", fallback: 250), 250)
        XCTAssertEqual(SellwildNative.maxHeight(remoteValues: try AppConfigFactory.remote(["NATIVE_MAX_HEIGHT": 300]), zoneId: "43", fallback: 250), 300)
        XCTAssertEqual(SellwildNative.maxHeight(remoteValues: try AppConfigFactory.remote(["NATIVE_MAX_HEIGHT": "320.5"]), zoneId: nil, fallback: 250), 320.5)
        let byZone = try AppConfigFactory.remote(["NATIVE_MAX_HEIGHT": 300, "NATIVE_MAX_HEIGHT_BY_ZONE": ["43": 200, "280": -5, "999": "tall"]])
        XCTAssertEqual(SellwildNative.maxHeight(remoteValues: byZone, zoneId: "43", fallback: 250), 200)
        XCTAssertEqual(SellwildNative.maxHeight(remoteValues: byZone, zoneId: "280", fallback: 250), 300, "not positive: global")
        XCTAssertEqual(SellwildNative.maxHeight(remoteValues: byZone, zoneId: "999", fallback: 250), 300, "not a number: global")
        let boolean = try Factory.offSchema(because: "NATIVE_MAX_HEIGHT must be a number or numeric text") {
            try AppConfigFactory.remote(["NATIVE_MAX_HEIGHT": true])
        }
        XCTAssertEqual(SellwildNative.maxHeight(remoteValues: boolean, zoneId: nil, fallback: 250), 1, "a JSON boolean is a number, as before")
    }

    /// JSON numbers reach the height parser as NSNumber: most read as a
    /// Double, an integer a Double cannot hold exactly reads as an Int, and
    /// one too large for an Int reads through NSNumber.
    func testNativeMaxHeightNumbersOfEveryWidth() throws {
        let table: [(Any, CGFloat)] = [(300, 300), (9_007_199_254_740_993, 9_007_199_254_740_992), (UInt64.max, CGFloat(UInt64.max))]
        for (height, expected) in table {
            XCTAssertEqual(SellwildNative.maxHeight(remoteValues: try AppConfigFactory.remote(["NATIVE_MAX_HEIGHT": height]), zoneId: nil, fallback: 250),
                           expected, "\(height)")
        }
    }

    func testNativeRequestAssetsAndContext() {
        let request = SellwildNative.makeRequest(configId: "native-43")
        XCTAssertEqual(request.configId, "native-43")
        XCTAssertEqual(request.assets?.count, 6)
        XCTAssertEqual(request.eventtrackers?.count, 1)
        XCTAssertEqual(request.context, ContextType.Content)
        XCTAssertEqual(request.placementType, PlacementType.FeedContent)
        XCTAssertEqual(request.contextSubType, ContextSubType.General)
    }

    // MARK: SellwildVideo

    func testOutstreamParameters() {
        let params = SellwildVideo.outstreamParameters()
        XCTAssertEqual(params.mimes, ["video/mp4"])
        XCTAssertEqual(params.protocols?.count, 3)
        XCTAssertEqual(params.playbackMethod?.map(\.value), [Signals.PlaybackMethod.ClickToPlay.value])
        XCTAssertEqual(params.placement?.value, Signals.Placement.InBanner.value)
        XCTAssertEqual(params.minDuration?.value, 5)
        XCTAssertEqual(params.maxDuration?.value, 30)
    }

    func testEnableOutstreamRequestsVideoMutedUnlessSoundIsOn() throws {
        let size = CGSize(width: 300, height: 250)
        let view = PrebidBannerView(frame: CGRect(origin: .zero, size: size), configID: "43", adSize: size)
        SellwildVideo.enableOutstream(on: view, remoteValues: nil, zoneId: "43")
        XCTAssertEqual(view.adUnitConfig.adFormats, [.banner, .video])
        XCTAssertEqual(view.adUnitConfig.adConfiguration.videoParameters.maxDuration?.value, 30)
        XCTAssertTrue(view.adUnitConfig.adConfiguration.videoControlsConfig.isMuted)

        let loud = try AppConfigFactory.remote(["VIDEO_SOUND_ENABLED_BY_ZONE": ["43": true]])
        SellwildVideo.enableOutstream(on: view, remoteValues: loud, zoneId: "43")
        XCTAssertFalse(view.adUnitConfig.adConfiguration.videoControlsConfig.isMuted)

        SellwildVideo.forceDefaultMute(on: view)
        XCTAssertTrue(view.adUnitConfig.adConfiguration.videoControlsConfig.isMuted)
    }

    func testVideoFlagsAcceptNumbersAndIgnoreOtherTypes() throws {
        XCTAssertTrue(SellwildVideo.isEnabled(remoteValues: try AppConfigFactory.remote(["VIDEO_ENABLED": 1]), zoneId: nil))
        let listFlag = try Factory.offSchema(because: "a VIDEO_ENABLED_BY_ZONE value must be a flag, not a list") {
            try AppConfigFactory.remote(["VIDEO_ENABLED_BY_ZONE": ["43": ["on"]]])
        }
        XCTAssertFalse(SellwildVideo.isEnabled(remoteValues: listFlag, zoneId: "43"))
        XCTAssertTrue(SellwildVideo.soundEnabled(remoteValues: try AppConfigFactory.remote(["VIDEO_SOUND_ENABLED": "yes"]), zoneId: nil))
        XCTAssertTrue(SellwildVideo.isEnabled(remoteValues: try AppConfigFactory.remote(["VIDEO_ENABLED": 2]), zoneId: nil),
                      "a number other than 0 or 1 is read as a number")
    }
}
