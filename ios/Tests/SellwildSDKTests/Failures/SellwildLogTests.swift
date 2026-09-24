import XCTest
@testable import SellwildSDK

final class SellwildLogTests: XCTestCase {

    private var lines: [String] = []

    override func setUp() {
        super.setUp()
        lines = []
        SellwildLog.setOutput { [unowned self] in self.lines.append($0) }
    }

    override func tearDown() {
        SellwildLog.isEnabled = false
        SellwildLog.setOutput(nil)
        super.tearDown()
    }

    func testOffByDefaultAndTheMessageIsNotBuilt() {
        XCTAssertFalse(SellwildLog.isEnabled)
        var built = false
        func message() -> String {
            built = true
            return "trace"
        }
        SellwildLog.debug(message())
        XCTAssertFalse(built)
        XCTAssertTrue(lines.isEmpty)
    }

    func testPrintsWhenDebugIsOn() {
        SellwildLog.isEnabled = true
        SellwildLog.debug("[SellwildSDK] trace line")
        XCTAssertEqual(lines, ["[SellwildSDK] trace line"])
    }

    func testDefaultOutputPrints() throws {
        SellwildLog.setOutput(nil)
        SellwildLog.isEnabled = true
        let out = try StdoutCapture.run {
            SellwildLog.debug("[SellwildSDK] SellwildLogTests default output")
        }
        XCTAssertTrue(out.contains("[SellwildSDK] SellwildLogTests default output\n"), out)
        XCTAssertTrue(lines.isEmpty, "the captured output was replaced")

        SellwildLog.isEnabled = false
        let quiet = try StdoutCapture.run {
            SellwildLog.debug("[SellwildSDK] SellwildLogTests off")
        }
        XCTAssertFalse(quiet.contains("SellwildLogTests off"), quiet)
    }
}
