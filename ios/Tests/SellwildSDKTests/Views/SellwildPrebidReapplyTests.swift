import XCTest
import SellwildPrebidSDK
@testable import SellwildSDK

/// origin c55efa0 and 1847555: a later bootstrap with another config re-applies
/// the per-config Prebid fields without starting the SDKs again, and swaps the
/// shared Prebid Server host only when its URL changed. SDK start is recorded.
final class SellwildPrebidReapplyTests: FailureCapturingTestCase {

    private var started: [String] = []
    /// Prebid's shared host (the test target has its own `Host` helper).
    private let prebidHost = SellwildPrebidSDK.Host.shared

    override func setUp() {
        super.setUp()
        SellwildPrebidMobile.resetForTesting()
        Targeting.shared.setGlobalORTBConfig(nil)
        started = []
        var calls = SellwildPrebidMobile.Calls.live
        calls.startSDKs = { [weak self] url in self?.started.append(url) }
        SellwildPrebidMobile.calls = calls
    }

    override func tearDown() {
        SellwildPrebidMobile.resetForTesting()
        Targeting.shared.setGlobalORTBConfig(nil)
        SellwildPrebid.shared.prebidServerAccountId = ""
        try? prebidHost.setHostURL(SellwildPrebidConfig.defaultEndpoint, nonTrackingURLString: nil)
        super.tearDown()
    }

    private func config(_ s2s: String, _ more: [String: Any] = [:]) throws -> SellwildConfig {
        try AppConfigFactory.config(more.merging(["S2S_CONFIG": s2s]) { _, new in new }, partnerCode: "demo")
    }

    private func publisherId() throws -> String? {
        let text = try XCTUnwrap(Targeting.shared.getGlobalORTBConfig())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        return ((root["app"] as? [String: Any])?["publisher"] as? [String: Any])?["id"] as? String
    }

    func testALaterBootstrapReappliesItsFieldsAndSwapsTheHostOnlyForANewURL() throws {
        let literal = "[{ accountId: 'acct-1', endpoint: { p1Consent: 'https://pbs.example.com/a' }, timeout: 1300, }]"
        SellwildPrebidMobile.bootstrap(with: try config(literal, ["PUBLISHER_ID": "pub-1"]))
        XCTAssertEqual(started, ["https://pbs.example.com/a"])
        XCTAssertEqual(SellwildPrebid.shared.prebidServerAccountId, "acct-1")
        XCTAssertEqual(SellwildPrebid.shared.timeoutMillis, 1300)
        try prebidHost.setHostURL("https://host.example/before", nonTrackingURLString: nil)

        let sameURL = "{ accountId: 'acct-2', endpoint: 'https://pbs.example.com/a', timeout: 900 }"
        SellwildPrebidMobile.bootstrap(with: try config(sameURL))
        XCTAssertEqual(SellwildPrebid.shared.prebidServerAccountId, "acct-2")
        XCTAssertEqual(SellwildPrebid.shared.timeoutMillis, 900)
        XCTAssertEqual(try prebidHost.getHostURL(), "https://host.example/before", "the same URL leaves the host")
        XCTAssertEqual(try publisherId(), "pub-1", "a key the new config lacks keeps its value")

        SellwildPrebidMobile.bootstrap(with: try config("{ endpoint: 'https://pbs.example.com/b' }"))
        XCTAssertEqual(try prebidHost.getHostURL(), "https://pbs.example.com/b")
        XCTAssertEqual(started, ["https://pbs.example.com/a"], "the SDKs start once")
        capture.none()
    }

    func testAHostThatCannotBeSetIsReportedAndTheOldOneStays() throws {
        SellwildPrebidMobile.bootstrap(with: try config("{ endpoint: 'https://pbs.example.com/a' }"))
        try prebidHost.setHostURL("https://pbs.example.com/a", nonTrackingURLString: nil)
        var typed = try AppConfigFactory.config(partnerCode: "demo")
        typed.prebidServer = PrebidServerConfig(accountId: "acct", endpoint: "", bidders: [])

        SellwildPrebidMobile.bootstrap(with: typed)

        XCTAssertEqual(try prebidHost.getHostURL(), "https://pbs.example.com/a")
        let event = capture.only(.adPrebidInitException, label: .banner)
        XCTAssertEqual(event?.attributes["severity"], "error")
    }
}
