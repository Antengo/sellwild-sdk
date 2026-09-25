import XCTest
@testable import SellwildSDK

/// Which Prebid Server to use, the publisher id and the global ORTB object
/// (`SellwildPrebidConfig`). Remote values come from the app-config factory.
final class SellwildPrebidConfigTests: XCTestCase {

    func testTypedConfigWins() throws {
        let typed = PrebidServerConfig(accountId: "acct", endpoint: "https://pbs.example/openrtb2/auction", bidders: [])
        let remote = try AppConfigFactory.remote(["S2S_CONFIG": ["endpoint": "https://other"]])
        XCTAssertEqual(SellwildPrebidConfig.server(typed: typed, remoteValues: remote, partnerCode: "p"),
                       .init(url: "https://pbs.example/openrtb2/auction", accountId: "acct"))
    }

    func testAnS2SObjectIsReadWithItsAliases() throws {
        let first = try AppConfigFactory.remote(["S2S_CONFIG": ["endpoint": "https://a", "accountId": "A"]])
        XCTAssertEqual(SellwildPrebidConfig.server(typed: nil, remoteValues: first, partnerCode: "p"), .init(url: "https://a", accountId: "A"))
        let second = try AppConfigFactory.remote(["S2S_CONFIG": ["url": "https://b", "account": "B"]])
        XCTAssertEqual(SellwildPrebidConfig.server(typed: nil, remoteValues: second, partnerCode: "p"), .init(url: "https://b", accountId: "B"))
        let empty = try AppConfigFactory.remote(["S2S_CONFIG": [String: Any]()])
        XCTAssertEqual(SellwildPrebidConfig.server(typed: nil, remoteValues: empty, partnerCode: "p"),
                       .init(url: SellwildPrebidConfig.defaultEndpoint, accountId: "p"))
    }

    func testS2STextFallsBackToTheHostedServer() throws {
        let text = try AppConfigFactory.remote(["S2S_CONFIG": "{ accountId: 'x' }"])
        XCTAssertEqual(SellwildPrebidConfig.server(typed: nil, remoteValues: text, partnerCode: "p"),
                       .init(url: "https://prebid.sellwild.com/openrtb2/auction", accountId: "p"), "known drift: text is not read")
        XCTAssertEqual(SellwildPrebidConfig.server(typed: nil, remoteValues: nil, partnerCode: "p").accountId, "p")
    }

    func testPublisherIdIsTextOrANumber() throws {
        XCTAssertEqual(SellwildPrebidConfig.publisherId(remoteValues: try AppConfigFactory.remote(["PUBLISHER_ID": "pub-1"])), "pub-1")
        XCTAssertEqual(SellwildPrebidConfig.publisherId(remoteValues: try AppConfigFactory.remote(["PUBLISHER_ID": 42])), "42")
        XCTAssertEqual(SellwildPrebidConfig.publisherId(remoteValues: try AppConfigFactory.remote(["SELLER_ID": "s-1"])), "s-1")
        XCTAssertNil(SellwildPrebidConfig.publisherId(remoteValues: try AppConfigFactory.remote(["PUBLISHER_ID": "", "SELLER_ID": "s"])),
                     "known drift: an empty PUBLISHER_ID does not fall back")
        XCTAssertNil(SellwildPrebidConfig.publisherId(remoteValues: try AppConfigFactory.remote()))
        XCTAssertNil(SellwildPrebidConfig.publisherId(remoteValues: nil))
    }

    func testGlobalORTBAlwaysCarriesTheDeviceType() {
        let bare = SellwildPrebidConfig.globalORTB(publisherId: nil, cats: nil, geo: nil, deviceType: 4)
        XCTAssertNil(bare["app"])
        XCTAssertEqual((bare["device"] as? [String: Any])?["devicetype"] as? Int, 4)
        let empty = SellwildPrebidConfig.globalORTB(publisherId: "", cats: [], geo: [:], deviceType: 5)
        XCTAssertNil(empty["app"])
        XCTAssertNil((empty["device"] as? [String: Any])?["geo"])

        let full = SellwildPrebidConfig.globalORTB(publisherId: "pub", cats: ["IAB15"], geo: ["region": "GA"], deviceType: 1)
        let app = full["app"] as? [String: Any]
        XCTAssertEqual((app?["publisher"] as? [String: Any])?["id"] as? String, "pub")
        XCTAssertEqual(app?["cat"] as? [String], ["IAB15"])
        XCTAssertEqual(((full["device"] as? [String: Any])?["geo"] as? [String: Any])?["region"] as? String, "GA")
    }

    func testJSONTextOrWhyNot() throws {
        XCTAssertEqual(try SellwildPrebidConfig.json(["a": [1]]).get(), #"{"a":[1]}"#)
        guard case .failure(.notJSON) = SellwildPrebidConfig.json(["lat": Double.nan]) else {
            return XCTFail("NaN is not JSON")
        }
        let result = SellwildPrebidConfig.json(["a": 1]) { _ in throw PlannedError() }
        guard case .failure(.serialization(let error)) = result else { return XCTFail("the serializer threw") }
        XCTAssertEqual(error as? PlannedError, PlannedError())
        XCTAssertNil(SellwildPrebidConfig.JSONProblem.notJSON.error)
        XCTAssertEqual(SellwildPrebidConfig.JSONProblem.serialization(PlannedError()).error as? PlannedError, PlannedError())
    }
}
