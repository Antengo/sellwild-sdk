import XCTest
@testable import SellwildSDK

/// Registry parity (FAILURES.md 4.2): the Swift mirror must equal the codes of
/// contracts/failure-codes.json whose `clients` include `ios`, and the
/// component and severity enums must equal the contract's lists.
final class SellwildFailureCodeTests: XCTestCase {

    private func registry() throws -> [[String: Any]] {
        try XCTUnwrap(try Fixtures.json("failure-codes.json") as? [[String: Any]])
    }

    private func iosEntries() throws -> [[String: Any]] {
        try registry().filter { ($0["clients"] as? [String])?.contains("ios") == true }
    }

    func testMirrorEqualsTheIOSCodesInRegistryOrder() throws {
        let expected = try iosEntries().compactMap { $0["code"] as? String }
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(SellwildFailureCode.allCases.map(\.rawValue), expected)
    }

    func testEveryCodeHasTheContractFormat() {
        for code in SellwildFailureCode.allCases {
            XCTAssertEqual(SellwildFailuresCore.normalizeCode(code.rawValue), code.rawValue)
        }
    }

    func testRegistryComponentsAndSeveritiesExistInSwift() throws {
        for entry in try iosEntries() {
            let code = try XCTUnwrap(entry["code"] as? String)
            let component = try XCTUnwrap(entry["component"] as? String, code)
            let severity = try XCTUnwrap(entry["severity"] as? String, code)
            XCTAssertTrue(component == "unknown" || SellwildFailureComponent(rawValue: component) != nil, code)
            XCTAssertNotNil(SellwildFailureSeverity(rawValue: severity), code)
        }
    }

    func testComponentAndSeverityEnumsMatchTheEventSchema() throws {
        let schema = try Fixtures.dict("schemas/client-failure-event.schema.json")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let label = try XCTUnwrap(properties["label"] as? [String: Any])
        XCTAssertEqual(SellwildFailureComponent.allCases.map(\.rawValue) + ["unknown"], label["enum"] as? [String])
        XCTAssertEqual(SellwildFailureComponent.allCases.map(\.rawValue), SellwildFailuresCore.components)

        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let attributes = try XCTUnwrap((defs["attributes"] as? [String: Any])?["properties"] as? [String: Any])
        let severity = try XCTUnwrap(attributes["severity"] as? [String: Any])
        XCTAssertEqual(SellwildFailureSeverity.allCases.map(\.rawValue), severity["enum"] as? [String])
        XCTAssertEqual(SellwildFailureSeverity.allCases.map(\.rawValue), SellwildFailuresCore.severities)
        XCTAssertEqual(Array(attributes.keys).sorted(), SellwildFailuresCore.attributeKeys.sorted())
    }
}
