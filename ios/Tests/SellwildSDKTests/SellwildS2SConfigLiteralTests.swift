import XCTest
@testable import SellwildSDK

/// More of origin's JS-literal reader (c55efa0): comments, raw line breaks in
/// text, `undefined`, numbers with exponents, timeouts as text, and fields of
/// the wrong type.
final class SellwildS2SConfigLiteralTests: XCTestCase {

    func testCommentsAreDroppedAndUndefinedIsNull() {
        let text = """
        // S2S settings
        { /* the account */ accountId: 'acct', endpoint: undefined, url: 'https://u.example/a', timeout: '1200' }
        """
        XCTAssertEqual(SellwildS2SConfig.parse(text),
                       SellwildS2SConfig(accountId: "acct", endpoint: "https://u.example/a", timeout: 1200))
    }

    func testLineBreaksAndTabsInTextAreEscaped() {
        XCTAssertEqual(SellwildS2SConfig.jsLiteralToJSON("{ a: 'x\ny\r\tz' }"), #"{ "a": "x\ny\r\tz" }"#)
    }

    func testANumberWithAnExponentIsCopiedNotReadAsAKey() {
        XCTAssertEqual(SellwildS2SConfig.parse("{ accountId: 'a', timeout: 1.2e3 }"),
                       SellwildS2SConfig(accountId: "a", endpoint: nil, timeout: 1200))
    }

    func testWrongTypedOrEmptyFieldsAreIgnored() {
        XCTAssertNil(SellwildS2SConfig.parse(["accountId": 5, "endpoint": ["p1Consent": ""], "timeout": -1]))
        XCTAssertEqual(SellwildS2SConfig.parse(["endpoint": ["noP1Consent": "https://n.example/a"], "timeout": "x"]),
                       SellwildS2SConfig(accountId: nil, endpoint: "https://n.example/a", timeout: nil))
    }
}
