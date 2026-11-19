import XCTest
@testable import SellwildSDK

/// Last-good remote config cache + the fetched-vs-cached decision in
/// `SellwildSDK.resolveConfig` — all network-free, against a temp directory.
final class SellwildConfigCacheTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        // Deliberately not created up front: the cache must create it on demand.
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SellwildConfigCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func payload(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: Cache

    func testStoreThenLoadRoundTripsRawBytes() {
        let data = payload(["CODE": "acme", "AD_STACK": "prebidOnly"])
        XCTAssertNil(SellwildConfigCache.load(partnerCode: "acme", slug: "acme-main", directory: dir))

        SellwildConfigCache.store(data, partnerCode: "acme", slug: "acme-main", directory: dir)

        XCTAssertEqual(SellwildConfigCache.load(partnerCode: "acme", slug: "acme-main", directory: dir), data)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("config-acme-acme-main.json").path
        ))
    }

    func testCacheIsKeyedByPartnerAndSlug() {
        let data = payload(["CODE": "acme"])
        SellwildConfigCache.store(data, partnerCode: "acme", slug: "acme-main", directory: dir)
        XCTAssertNil(SellwildConfigCache.load(partnerCode: "acme", slug: "acme-other", directory: dir))
        XCTAssertNil(SellwildConfigCache.load(partnerCode: "other", slug: "acme-main", directory: dir))
    }

    func testStoreOverwritesPreviousPayload() {
        SellwildConfigCache.store(payload(["TITLE": "old"]), partnerCode: "acme", slug: "acme-main", directory: dir)
        let newer = payload(["TITLE": "new"])
        SellwildConfigCache.store(newer, partnerCode: "acme", slug: "acme-main", directory: dir)
        XCTAssertEqual(SellwildConfigCache.load(partnerCode: "acme", slug: "acme-main", directory: dir), newer)
    }

    func testFileNameSanitisesPartnerAndSlug() {
        XCTAssertEqual(SellwildConfigCache.sanitize("acme-main_2"), "acme-main_2")
        XCTAssertEqual(SellwildConfigCache.sanitize("../a b/c.json"), "___a_b_c_json")
        XCTAssertEqual(SellwildConfigCache.sanitize("caf\u{e9}"), "caf_")
        XCTAssertEqual(
            SellwildConfigCache.fileName(partnerCode: "ac/me", slug: "../main"),
            "config-ac_me-___main.json"
        )
        // A hostile slug can't escape the cache directory.
        let url = SellwildConfigCache.fileURL(partnerCode: "acme", slug: "../../etc/x", directory: dir)
        XCTAssertEqual(url?.deletingLastPathComponent().standardizedFileURL.path, dir.standardizedFileURL.path)
    }

    func testDiskErrorsAreSwallowed() {
        // A regular file where the directory should be: createDirectory fails.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("SellwildConfigCacheTests-blocker-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: blocker.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: blocker) }

        SellwildConfigCache.store(payload(["CODE": "acme"]), partnerCode: "acme", slug: "acme-main", directory: blocker)
        XCTAssertNil(SellwildConfigCache.load(partnerCode: "acme", slug: "acme-main", directory: blocker))
    }

    // MARK: resolveConfig

    func testFetchedPayloadIsAppliedAndPersisted() {
        let data = payload(["MOBILE_ZID": ["101", "102"], "AD_STACK": "prebidOnly"])
        let config = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main", fetched: data, cacheDirectory: dir
        )
        XCTAssertEqual(config.mobileZids, ["101", "102"])
        XCTAssertEqual(config.remoteJSON, data)
        XCTAssertEqual(SellwildConfigCache.load(partnerCode: "acme", slug: "acme-main", directory: dir), data)
    }

    func testFallsBackToCacheWhenFetchFails() {
        let data = payload([
            "MOBILE_ZID": ["101"],
            "MOBILE_BANNER_ZID": "201",
            "AD_STACK": "prebidOnly",
            "FUTURE_KEY": "kept",
        ])
        // A good launch populates the cache…
        _ = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main", fetched: data, cacheDirectory: dir
        )
        // …and a later failed fetch is configured exactly the same way.
        let config = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main", fetched: nil, cacheDirectory: dir
        )
        XCTAssertEqual(config.mobileZids, ["101"])
        XCTAssertEqual(config.mobileBannerZid, "201")
        XCTAssertEqual(config.remoteJSON, data)
        XCTAssertEqual(config.remoteValues?["FUTURE_KEY"] as? String, "kept")
        XCTAssertEqual(
            SellwildAdStack.resolve(remoteValues: config.remoteValues, zoneId: "101"),
            .prebidOnly
        )
    }

    func testNoFetchAndNoCacheKeepsDefaults() {
        let config = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main", fetched: nil, cacheDirectory: dir
        )
        XCTAssertEqual(config.partnerCode, "acme")
        XCTAssertTrue(config.mobileZids.isEmpty)
        XCTAssertNil(config.remoteJSON)
        // Unknown stack never resolves to one that requests GAM.
        XCTAssertEqual(
            SellwildAdStack.resolve(remoteValues: config.remoteValues, zoneId: nil),
            .prebidOnly
        )
    }

    func testNonObjectPayloadIsTreatedAsFailureAndDoesNotClobberCache() {
        let good = payload(["MOBILE_ZID": ["101"]])
        SellwildConfigCache.store(good, partnerCode: "acme", slug: "acme-main", directory: dir)

        let config = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main", fetched: Data("[1,2]".utf8), cacheDirectory: dir
        )
        XCTAssertEqual(config.mobileZids, ["101"])
        XCTAssertEqual(SellwildConfigCache.load(partnerCode: "acme", slug: "acme-main", directory: dir), good)
    }

    func testCorruptCacheFallsBackToDefaults() {
        SellwildConfigCache.store(Data("not json".utf8), partnerCode: "acme", slug: "acme-main", directory: dir)
        let config = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main", fetched: nil, cacheDirectory: dir
        )
        XCTAssertTrue(config.mobileZids.isEmpty)
        XCTAssertNil(config.remoteJSON)
    }

    func testFreshFetchReplacesCachedPayload() {
        _ = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main",
            fetched: payload(["MOBILE_ZID": ["101"]]), cacheDirectory: dir
        )
        _ = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main",
            fetched: payload(["MOBILE_ZID": ["999"]]), cacheDirectory: dir
        )
        let config = SellwildSDK.resolveConfig(
            partnerCode: "acme", slug: "acme-main", fetched: nil, cacheDirectory: dir
        )
        XCTAssertEqual(config.mobileZids, ["999"])
    }
}
