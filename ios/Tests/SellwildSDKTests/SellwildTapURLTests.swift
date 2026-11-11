import XCTest
@testable import SellwildSDK

/// `SellwildListing.tapURL`: where a listing tap goes, and the reader id
/// (`sw_wuid`) a sellwild.com link carries (`SellwildReaderLink`), so
/// sellwild.com can match an app reader to their visit.
final class SellwildTapURLTests: XCTestCase {

    /// A v4 UUID, the shape of the `_sw_uid` the SDK stores.
    private let reader = "3F2B8C1E-7D4A-4B6E-9A1C-5E8F0D2C4B7A"
    private let lotlinx = "https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1"

    private func listing(_ overrides: [String: Any] = [:]) throws -> SellwildListing {
        try ListingFactory.decoded(ListingFactory.make(overrides))
    }

    func testTapURL() throws {
        let direct = try listing(["url": "https://shop.invalid/p?tag=old&x=1"])
        XCTAssertEqual(direct.tapURL(partnerCode: "p", bhTag: "bh-1", readerId: reader),
                       "https://shop.invalid/p?x=1&tag=bh-1")
        XCTAssertEqual(direct.tapURL(partnerCode: "p", readerId: reader), "https://shop.invalid/p?tag=old&x=1")
        XCTAssertEqual(direct.tapURL(partnerCode: "p", bhTag: "", readerId: reader),
                       "https://shop.invalid/p?tag=old&x=1")
        let bare = try listing(["url": "https://shop.invalid/p"])
        XCTAssertEqual(bare.tapURL(partnerCode: "p", bhTag: "bh", readerId: reader), "https://shop.invalid/p?tag=bh")
        let unparsable = try listing(["url": "http://exa mple.invalid/[x"])
        XCTAssertEqual(unparsable.tapURL(partnerCode: "p", bhTag: "bh", readerId: reader), "http://exa mple.invalid/[x")

        XCTAssertEqual(try listing().tapURL(partnerCode: "p", readerId: reader), lotlinx)

        let canonical = try listing(["dataSourceId": "7", "url": ""])
        let product = "https://sellwild.com/product/105140231"
        XCTAssertEqual(canonical.tapURL(partnerCode: "weather bug", readerId: reader),
                       "\(product)?p=weather%20bug&utm_source=weather%20bug&sw_wuid=\(reader)")
        XCTAssertEqual(canonical.tapURL(partnerCode: nil, readerId: reader),
                       "\(product)?p=sellwild&utm_source=sellwild&sw_wuid=\(reader)")
        XCTAssertEqual(canonical.tapURL(partnerCode: "", readerId: reader),
                       "\(product)?p=sellwild&utm_source=sellwild&sw_wuid=\(reader)")
        let noRemote = try listing(["remote_url": ""])
        XCTAssertEqual(noRemote.tapURL(partnerCode: "p", readerId: reader),
                       "\(product)?p=p&utm_source=p&sw_wuid=\(reader)")
        XCTAssertNil(try listing(["id": "", "dataSourceId": "7"]).tapURL(partnerCode: "p", readerId: reader))
    }

    func testTapURLCarriesTheReaderIdOnlyToSellwild() throws {
        let canonical = try listing(["dataSourceId": "7", "url": ""])
        XCTAssertEqual(canonical.tapURL(partnerCode: "weatherbug", readerId: reader),
                       "https://sellwild.com/product/105140231?p=weatherbug&utm_source=weatherbug&sw_wuid=\(reader)",
                       "the weatherbug fallback gets the id")

        let www = try listing(["url": "https://www.sellwild.com/product/7?x=1"])
        XCTAssertEqual(www.tapURL(partnerCode: "p", bhTag: "bh", readerId: reader),
                       "https://www.sellwild.com/product/7?x=1&tag=bh&sw_wuid=\(reader)",
                       "a www.sellwild.com direct url gets it, the tag still set")

        let old = try listing(["url": "https://sellwild.com/product/7?a=1&sw_wuid=old&b=2#photos"])
        XCTAssertEqual(old.tapURL(partnerCode: "p", readerId: reader),
                       "https://sellwild.com/product/7?a=1&b=2&sw_wuid=\(reader)#photos",
                       "an old sw_wuid is replaced and the fragment kept")

        let bttn = try listing(["url": "https://o.bttn.io/19BIp9F5cLj?tag=x"])
        XCTAssertEqual(bttn.tapURL(partnerCode: "p", readerId: reader), "https://o.bttn.io/19BIp9F5cLj?tag=x")
        XCTAssertEqual(try listing().tapURL(partnerCode: "p", readerId: reader), lotlinx)

        let plain = "https://sellwild.com/product/105140231?p=p&utm_source=p"
        XCTAssertEqual(canonical.tapURL(partnerCode: "p", readerId: ""), plain)
        XCTAssertEqual(canonical.tapURL(partnerCode: "p", readerId: nil), plain)
    }

    func testTapURLReaderIdDefaultsToTheStoredSessionId() throws {
        let uid = SellwildSession.shared.uid
        XCTAssertNotNil(UUID(uuidString: uid), "the stored id is a UUID")
        XCTAssertEqual(try listing(["dataSourceId": "7", "url": ""]).tapURL(partnerCode: "p"),
                       "https://sellwild.com/product/105140231?p=p&utm_source=p&sw_wuid=\(uid)")
    }

    func testReaderLinkAddsTheIdToSellwildLinksOnly() {
        let changed: [(String, String)] = [
            ("https://sellwild.com/product/1?p=a", "https://sellwild.com/product/1?p=a&sw_wuid=\(reader)"),
            ("https://www.sellwild.com/product/1", "https://www.sellwild.com/product/1?sw_wuid=\(reader)"),
            ("https://SellWild.com", "https://SellWild.com?sw_wuid=\(reader)"),
            ("https://sellwild.com/#top", "https://sellwild.com/?sw_wuid=\(reader)#top"),
            ("https://sellwild.com/p?sw_wuid=old&a=1%202&&b&sw_wuidx=y&sw_wuid#f?x=1",
             "https://sellwild.com/p?a=1%202&b&sw_wuidx=y&sw_wuid=\(reader)#f?x=1")
        ]
        for (url, expected) in changed {
            XCTAssertEqual(SellwildReaderLink.withReaderId(url, readerId: reader), expected, url)
        }
        XCTAssertEqual(SellwildReaderLink.withReaderId("https://sellwild.com/p", readerId: "a/b&c"),
                       "https://sellwild.com/p?sw_wuid=a%2Fb%26c", "the id is url-encoded")

        let unchanged = [
            "https://o.bttn.io/19BIp9F5cLj?tag=sw-bh",
            lotlinx,
            "https://browse.sellwild.com/x",
            "https://sellwild.com.evil.example/x",
            "https://sellwild.community/x",
            "http://sellwild.com/product/1",
            "/product/1",
            "http://exa mple.invalid/[x",
            ""
        ]
        for url in unchanged {
            XCTAssertEqual(SellwildReaderLink.withReaderId(url, readerId: reader), url)
        }
        let plain = "https://sellwild.com/1"
        XCTAssertEqual(SellwildReaderLink.withReaderId(plain, readerId: ""), plain)
        XCTAssertEqual(SellwildReaderLink.withReaderId(plain, readerId: nil), plain)
    }
}
