import XCTest
import SellwildPrebidSDK
@testable import SellwildSDK

/// The eid registry: consumer eids win per source over GrowthCode's, and the
/// merge reaches Prebid's global targeting. Eids come from the eid-blob
/// factory through the SDK's own parser.
final class SellwildEidsTests: FailureCapturingTestCase {

    override func tearDown() {
        SellwildEidRegistry.setConsumer([])
        SellwildEidRegistry.setGrowthCode([])
        super.tearDown()
    }

    private func eids(_ blob: [[String: Any]]) throws -> [SellwildEid] {
        SellwildGrowthCode.parseEidBlob(String(decoding: try Factory.data(blob), as: UTF8.self))
    }

    func testMergeKeepsConsumerFirstAndDropsGrowthCodeForTheSameSource() throws {
        let growth = try eids(EidBlobFactory.make())
        XCTAssertEqual(growth.map(\.source), ["uidapi.com", "id5-sync.com"])
        let consumer = try eids(EidBlobFactory.single(source: "id5-sync.com", id: "partner-id5", atype: 1))

        let merged = SellwildEidRegistry.merge(consumer: consumer, growthCode: growth)
        XCTAssertEqual(merged.map(\.source), ["id5-sync.com", "uidapi.com"])
        XCTAssertEqual(merged.first?.uids.map(\.id), ["partner-id5"])
        XCTAssertEqual(SellwildEidRegistry.merge(consumer: [], growthCode: growth).map(\.source), ["uidapi.com", "id5-sync.com"])
        capture.none()
    }

    func testPrebidFormCarriesEveryUid() throws {
        let mapped = SellwildEidRegistry.prebidEids(try eids(EidBlobFactory.make()))
        let json = mapped.map { $0.toJSONDictionary() }
        XCTAssertEqual(json.map { $0["source"] as? String }, ["uidapi.com", "id5-sync.com"])
        let id5 = try XCTUnwrap(json.last?["uids"] as? [[String: Any]])
        XCTAssertEqual(id5.map { $0["id"] as? String }, ["ID5*fixture", "ppid-fixture"])
        XCTAssertEqual(id5.first?["atype"] as? Int, 1)
        XCTAssertEqual((id5.last?["ext"] as? [String: Any])?["stype"] as? String, "ppuid")
    }

    func testRegistryPushesTheMergeToPrebidTargeting() throws {
        SellwildEidRegistry.setGrowthCode(try eids(EidBlobFactory.make()))
        SellwildPrebidMobile.setExternalUserIds(try eids(EidBlobFactory.single(source: "uidapi.com", id: "partner-uid2", atype: 3)))

        let sent = try XCTUnwrap(Targeting.shared.getExternalUserIds())
        XCTAssertEqual(sent.map { $0["source"] as? String }, ["uidapi.com", "id5-sync.com"])
        XCTAssertEqual(((sent.first?["uids"] as? [[String: Any]])?.first)?["id"] as? String, "partner-uid2")
        XCTAssertEqual(SellwildEidRegistry.current.count, 2)

        SellwildPrebidMobile.setExternalUserIds([])
        SellwildEidRegistry.setGrowthCode([])
        XCTAssertNil(Targeting.shared.getExternalUserIds(), "an empty merge clears Prebid's eids")
    }

    func testPublicEidValues() {
        let uid = SellwildEidUID(id: "x", atype: 3, ext: ["rtiPartner": "TDID"])
        XCTAssertEqual(uid.ext?["rtiPartner"] as? String, "TDID")
        XCTAssertNil(SellwildEidUID(id: "y", atype: 1).ext)
        XCTAssertEqual(SellwildEid(source: "liveramp.com", uids: [uid]).uids.count, 1)
    }
}
