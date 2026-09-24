import XCTest
@testable import SellwildSDK

/// The CDN ships `S2S_CONFIG` as a JS object-literal string; pin that the
/// tolerant parser reads it (and real JSON) and rejects garbage.
final class SellwildS2SConfigTests: XCTestCase {

    /// Verbatim shape of the live weatherbug CDN value.
    private let liveSample = """
    [{
      accountId: 'weatherbug',
      bidders: ['ix', 'medianet'],
      adapter: 'prebidServer',
      enabled: true,
      endpoint: {
        p1Consent: 'https://prebid.sellwild.com/openrtb2/auction',
        noP1Consent: 'https://prebid.sellwild.com/openrtb2/auction'
      },
      syncEndpoint: {
        p1Consent: 'https://prebid.sellwild.com/cookie_sync',
        noP1Consent: 'https://prebid.sellwild.com/cookie_sync'
      },
      timeout: 1300
    }]
    """

    func testParsesLiveJSLiteralSample() {
        XCTAssertEqual(
            SellwildS2SConfig.parse(liveSample),
            SellwildS2SConfig(
                accountId: "weatherbug",
                endpoint: "https://prebid.sellwild.com/openrtb2/auction",
                timeout: 1300
            )
        )
    }

    func testParsesJSLiteralWithTrailingCommasAndEscapedQuotes() {
        let s = "{ accountId: 'it\\'s \"x\"', endpoint: 'https://a.example/auction', timeout: 900, bidders: ['ix',], }"
        XCTAssertEqual(
            SellwildS2SConfig.parse(s),
            SellwildS2SConfig(accountId: "it's \"x\"", endpoint: "https://a.example/auction", timeout: 900)
        )
    }

    func testParsesJSONStringObjectAndArray() {
        let obj = #"{"accountId":"acct","endpoint":"https://b.example/auction","timeout":1500}"#
        let expected = SellwildS2SConfig(accountId: "acct", endpoint: "https://b.example/auction", timeout: 1500)
        XCTAssertEqual(SellwildS2SConfig.parse(obj), expected)
        XCTAssertEqual(SellwildS2SConfig.parse("[\(obj)]"), expected)
    }

    func testParsesDecodedDictionaryAndArray() {
        let dict: [String: Any] = ["account": "acct", "url": "https://c.example/auction"]
        let expected = SellwildS2SConfig(accountId: "acct", endpoint: "https://c.example/auction", timeout: nil)
        XCTAssertEqual(SellwildS2SConfig.parse(dict), expected)
        XCTAssertEqual(SellwildS2SConfig.parse([dict]), expected)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(SellwildS2SConfig.parse(nil))
        XCTAssertNil(SellwildS2SConfig.parse(""))
        XCTAssertNil(SellwildS2SConfig.parse("not a config"))
        XCTAssertNil(SellwildS2SConfig.parse("[{ accountId: 'unterminated"))
        XCTAssertNil(SellwildS2SConfig.parse("[]"))
        XCTAssertNil(SellwildS2SConfig.parse("{ enabled: true }"))
        XCTAssertNil(SellwildS2SConfig.parse(42))
    }
}
