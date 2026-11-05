import XCTest
@testable import SellwildSDK

/// Bugs fixed in phase 3 (contract A9.1: each one yields an obviously invalid
/// value, and each test here failed before its fix). The payloads are real
/// samples or contract fixtures with overrides.
final class SellwildBehaviorFixTests: FailureCapturingTestCase {

    /// The real antengo config ships `LISTINGS: ""`. It used to become
    /// `listingsUrl == ""`, a URL nobody can load; core keeps the default.
    func testEmptyListingsKeyIsTreatedAsAbsent() throws {
        let raw = try AppConfigFactory.sample("antengo_antengo-sellwild-tv")
        XCTAssertEqual(raw["LISTINGS"] as? String, "")
        let config = SellwildSDK.apply(raw, to: SellwildConfig(partnerCode: "antengo"))
        XCTAssertNil(config.listingsUrl)
        XCTAssertEqual(config.effectiveListingsUrl, SellwildConfig.defaultListingsCacheURL)

        // A partner-supplied URL is not replaced by the empty remote value.
        let kept = SellwildSDK.apply(raw, to: SellwildConfig(partnerCode: "antengo", listingsUrl: "https://cache.sellwild.com/x"))
        XCTAssertEqual(kept.listingsUrl, "https://cache.sellwild.com/x")
        capture.none()
    }

    /// EVENTS_ENABLED is the master kill switch. Text with a trailing newline
    /// ("off\n") used to leave events on, because the old parser trimmed
    /// Unicode spaces but not line breaks. FAILURES.md 5.3: ASCII trim.
    func testEventsKillSwitchTrimsASCIIWhitespaceLikeTheContract() throws {
        for off in ["off\n", "\tfalse\r\n", " NO\u{0B}", "0\u{0C}"] {
            let raw = try AppConfigFactory.variant("minimal", ["EVENTS_ENABLED": off])
            XCTAssertFalse(SellwildEvents.isEnabled(remoteValues: raw), off.debugDescription)
            XCTAssertEqual(SellwildEvents.isEnabled(remoteValues: raw), SellwildFailuresCore.coerceFlag(off), off.debugDescription)
        }
    }

    /// MOBILE_HOUSE_AD_ENABLED is the house-ad kill switch. " off " used to
    /// read as enabled, because the old parser did not trim at all.
    func testHouseAdKillSwitchTrimsLikeTheContract() throws {
        for off in [" off ", "False\n", " 0"] {
            let raw = try AppConfigFactory.variant("minimal", [
                "MOBILE_HOUSE_AD_ENABLED": off,
                "MOBILE_HOUSE_AD_IMAGE": "https://cache.sellwild.com/house/a.png",
            ])
            XCTAssertFalse(SellwildHouseAd.isEnabled(remoteValues: raw), off.debugDescription)
            XCTAssertNil(SellwildHouseAd.resolve(remoteValues: raw, zoneId: "43", size: CGSize(width: 300, height: 250)))
        }
    }

    /// MOBILE_AD_MUTE_AUTOPLAY turns the ad audio guard off. The schema's
    /// flag type trims text; " off " used to leave the guard on.
    func testAudioGuardSwitchTrimsLikeTheContract() throws {
        for off in [" off ", "FALSE\n", "no "] {
            let raw = try AppConfigFactory.variant("minimal", ["MOBILE_AD_MUTE_AUTOPLAY": off])
            XCTAssertFalse(SellwildAdAudioGuard.isEnabled(remoteValues: raw), off.debugDescription)
        }
    }

    /// A listings URL that answers 4xx/5xx used to go to the parser. A JSON
    /// error body then parsed as an empty feed, was reported as success and
    /// was cached for the rest of the session.
    func testListingsHTTPErrorIsAFailureAndIsNotCached() throws {
        let session = StubURLProtocol.makeSession()
        defer { session.finishTasksAndInvalidate() }
        let client = SellwildAPIClient(session: session)
        let config = SellwildConfig(partnerCode: "weatherbug", listingsUrl: "https://cache.sellwild.com/listings-img-data-sm")
        let errorBody = try Factory.offSchema(because: "an error body, not a listings feed: result.rs is missing") {
            try ListingsResponseFactory.variant("empty-rs", result: ["rs": Factory.remove])
        }
        StubURLProtocol.handler = { _ in try .json(errorBody, status: 503) }

        var result: Result<SellwildListingsResponse, Error>?
        let done = expectation(description: "fetch")
        client.fetchListings(config: config) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertThrowsError(try XCTUnwrap(result).get()) { error in
            XCTAssertEqual(error.localizedDescription, SellwildError.invalidResponse.localizedDescription)
        }
        XCTAssertEqual(capture.only(.listingsFetchHttp, label: .listings)?.attributes["httpStatus"], "503")

        // Not cached: the next fetch asks again and gets the real feed.
        StubURLProtocol.handler = { _ in .init(status: 200, body: try ListingsResponseFactory.data()) }
        let again = expectation(description: "again")
        client.fetchListings(config: config) { result = $0; again.fulfill() }
        wait(for: [again], timeout: 10)
        XCTAssertFalse(try XCTUnwrap(result).get().listings.isEmpty)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(capture.calls, 1, "the good fetch reports nothing")
    }
}
