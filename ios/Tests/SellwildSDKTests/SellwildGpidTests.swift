import XCTest
@testable import SellwildSDK

/// Unit tests for `SellwildGpid` — base resolution, the shared imp-ext JSON
/// builder (gpid + pbadslot), and the feed's `base#n` disambiguation. All pure,
/// independent of UIKit / the Prebid fork.
final class SellwildGpidTests: XCTestCase {

    // MARK: resolveBase

    func testResolveBasePerZoneOverrideWins() {
        let remote: [String: Any] = [
            "GPID_BASE": "/global/base",
            "GPID_BASE_BY_ZONE": ["43": "/zone/43", "99": "/zone/99"],
        ]
        XCTAssertEqual(SellwildGpid.resolveBase(remoteValues: remote, zoneId: "43"), "/zone/43")
        XCTAssertEqual(SellwildGpid.resolveBase(remoteValues: remote, zoneId: "99"), "/zone/99")
    }

    func testResolveBaseFallsBackToGlobal() {
        let remote: [String: Any] = [
            "GPID_BASE": "/global/base",
            "GPID_BASE_BY_ZONE": ["43": "/zone/43"],
        ]
        // Zone with no per-zone entry → global.
        XCTAssertEqual(SellwildGpid.resolveBase(remoteValues: remote, zoneId: "7"), "/global/base")
        // No zone → global.
        XCTAssertEqual(SellwildGpid.resolveBase(remoteValues: remote, zoneId: nil), "/global/base")
    }

    func testResolveBaseAbsentIsNil() {
        XCTAssertNil(SellwildGpid.resolveBase(remoteValues: nil, zoneId: "43"))
        XCTAssertNil(SellwildGpid.resolveBase(remoteValues: ["CODE": "weatherbug"], zoneId: "43"))
        // Present-but-empty base string doesn't count.
        XCTAssertNil(SellwildGpid.resolveBase(remoteValues: ["GPID_BASE": "   "], zoneId: nil))
    }

    func testResolveBaseAcceptsNumber() {
        XCTAssertEqual(SellwildGpid.resolveBase(remoteValues: ["GPID_BASE": 12345], zoneId: nil), "12345")
    }

    // MARK: impExtJSON

    func testImpExtJSONSetsGpidAndPbadslotToSameValue() throws {
        let json = try XCTUnwrap(SellwildGpid.impExtJSON(gpid: "/base#1"))
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let ext = try XCTUnwrap(obj?["ext"] as? [String: Any])
        XCTAssertEqual(ext["gpid"] as? String, "/base#1")
        let data = try XCTUnwrap(ext["data"] as? [String: Any])
        XCTAssertEqual(data["pbadslot"] as? String, "/base#1")
        // gpid-only: no bidder block.
        XCTAssertNil(ext["prebid"])
    }

    func testImpExtJSONCarriesBidderParamsLowercasedAlongsideGpid() throws {
        let json = try XCTUnwrap(SellwildGpid.impExtJSON(gpid: "/base", bidderParams: ["APPNEXUS": ["placementId": 123]]))
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let ext = try XCTUnwrap(obj?["ext"] as? [String: Any])
        XCTAssertEqual(ext["gpid"] as? String, "/base")
        XCTAssertEqual((ext["data"] as? [String: Any])?["pbadslot"] as? String, "/base")
        let bidder = try XCTUnwrap((ext["prebid"] as? [String: Any])?["bidder"] as? [String: Any])
        XCTAssertNotNil(bidder["appnexus"], "bidder names must be lowercased")
        XCTAssertNil(bidder["APPNEXUS"])
    }

    func testImpExtJSONBidderParamsOnlyOmitsGpid() throws {
        let json = try XCTUnwrap(SellwildGpid.impExtJSON(gpid: nil, bidderParams: ["ix": ["siteId": "1"]]))
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let ext = try XCTUnwrap(obj?["ext"] as? [String: Any])
        XCTAssertNil(ext["gpid"])
        XCTAssertNil(ext["data"])
        XCTAssertNotNil(ext["prebid"])
    }

    func testImpExtJSONNilWhenNothingToEmit() {
        XCTAssertNil(SellwildGpid.impExtJSON(gpid: nil))
        XCTAssertNil(SellwildGpid.impExtJSON(gpid: "", bidderParams: [:]))
    }

    // MARK: disambiguate (feed occurrence logic)

    func testDisambiguateSingleUseBaseStaysBare() {
        // Two distinct bases, each used once → no suffix.
        XCTAssertEqual(SellwildGpid.disambiguate(["/a", "/b"]), ["/a", "/b"])
    }

    func testDisambiguateRepeatedBaseGetsOneBasedSuffixInRowOrder() {
        // Same base used 3× → base#1, base#2, base#3 in order.
        XCTAssertEqual(SellwildGpid.disambiguate(["/a", "/a", "/a"]), ["/a#1", "/a#2", "/a#3"])
    }

    func testDisambiguateMixedAndNilPreserved() {
        // /a repeats (suffixed), /b is single (bare), nil slots stay nil.
        XCTAssertEqual(
            SellwildGpid.disambiguate(["/a", "/b", nil, "/a"]),
            ["/a#1", "/b", nil, "/a#2"]
        )
    }
}
