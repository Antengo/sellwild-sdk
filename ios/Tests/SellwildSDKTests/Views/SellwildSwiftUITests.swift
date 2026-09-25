import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import SellwildSDK

/// The SwiftUI wrappers, hosted in a UIHostingController so SwiftUI makes and
/// updates their views, with the views' environments faked.
@available(iOS 14, *)
final class SellwildSwiftUITests: ViewTestCase {

    private var widgetLoads = 0

    override func setUp() {
        super.setUp()
        widgetLoads = 0
        SellwildWidgetView.environment = SellwildWidgetView.Environment(
            loadPage: { [weak self] _, _, _ in self?.widgetLoads += 1 },
            serializeJSON: SellwildPrebidConfig.serializeJSON
        )
        SellwildFeedView.environment = SellwildFeedView.Environment(
            makeAPIClient: { SellwildAPIClient(session: StubURLProtocol.makeSession()) },
            makeAdView: SellwildAdView.init(config:adSize:zoneId:),
            present: { _, _ in },
            imageSession: StubURLProtocol.makeSession()
        )
    }

    override func tearDown() {
        SellwildWidgetView.environment = .live
        SellwildFeedView.environment = .live
        super.tearDown()
    }

    /// Hosts `view` in a window and lays it out, so SwiftUI makes its UIKit view.
    private func host<V: View>(_ view: V) -> (UIWindow, UIHostingController<V>) {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        drainMain()
        return (window, controller)
    }

    private func find<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for sub in root.subviews {
            if let match = find(type, in: sub) { return match }
        }
        return nil
    }

    private func config() throws -> SellwildConfig {
        var config = try AppConfigFactory.config(partnerCode: "demo")
        config.gamTag = "/1/app/swiftui"
        return config
    }

    func testTheBannerLoadsAndForwardsImpressionsAndErrors() throws {
        var impressions = 0
        var errors: [Error] = []
        let banner = SellwildAdBanner(config: try config(), adSize: .mrec300x250, zoneId: "43",
                                      onImpression: { impressions += 1 }, onError: { errors.append($0) })
        let (window, controller) = host(banner)
        let adView = try XCTUnwrap(find(SellwildAdView.self, in: controller.view))
        XCTAssertEqual(adView.zoneId, "43")
        XCTAssertEqual(network.bootstraps, ["demo"], "makeUIView loads the ad")
        let delegate = try XCTUnwrap(adView.delegate)
        delegate.sellwildAdView?(adView, didReceiveImpressionForZoneId: "43")
        delegate.sellwildAdView?(adView, didFailWithError: SellwildAdError.nativeNoFill)
        XCTAssertEqual(impressions, 1)
        XCTAssertEqual(errors.count, 1)

        controller.rootView = SellwildAdBanner(config: try config(), adSize: .mrec300x250, zoneId: "43")
        controller.view.layoutIfNeeded()
        drainMain()
        XCTAssertTrue(find(SellwildAdView.self, in: controller.view) === adView, "an update keeps the view")
        withExtendedLifetime(window) {}
    }

    func testTheBannerWithoutCallbacksIgnoresThem() throws {
        let (window, controller) = host(SellwildAdBanner(config: try config(), adSize: .banner320x50))
        let adView = try XCTUnwrap(find(SellwildAdView.self, in: controller.view))
        adView.delegate?.sellwildAdView?(adView, didReceiveImpressionForZoneId: "")
        adView.delegate?.sellwildAdView?(adView, didFailWithError: SellwildAdError.nativeNoFill)
        XCTAssertNil(adView.zoneId)
        withExtendedLifetime(window) {}
    }

    func testTheFeedLoadsAndForwardsEveryCallback() throws {
        let data = try ListingsResponseFactory.data(listings: [try ListingFactory.make(["id": "1"])])
        StubURLProtocol.handler = { _ in .init(status: 200, headers: ["Content-Type": "application/json"], body: data) }
        var calls: [String] = []
        let feed = SellwildFeed(
            config: try config(),
            onListingTap: { calls.append("tap \($0.id)"); return true },
            onAdImpression: { calls.append("impression \($0)") },
            onAdClicked: { calls.append("click \($0)") },
            onLoad: { calls.append("load") },
            onError: { calls.append("error \($0)") }
        )
        let (window, controller) = host(feed)
        spin { calls.contains("load") }
        let feedView = try XCTUnwrap(find(SellwildFeedView.self, in: controller.view))
        let delegate = try XCTUnwrap(feedView.delegate)
        let listing = try ListingFactory.decoded(ListingFactory.make(["id": "1"]))
        XCTAssertTrue(delegate.sellwildFeed(feedView, didTapListing: listing))
        delegate.sellwildFeed(feedView, didRecordAdImpressionForZoneId: "43")
        delegate.sellwildFeed(feedView, didRecordAdClickForZoneId: "43")
        delegate.sellwildFeed(feedView, didFailWithError: "offline")
        XCTAssertEqual(calls, ["load", "tap 1", "impression 43", "click 43", "error offline"])

        controller.rootView = SellwildFeed(config: try config())
        controller.view.layoutIfNeeded()
        drainMain()
        XCTAssertFalse(delegate.sellwildFeed(feedView, didTapListing: listing), "the new wrapper has no tap handler")
        delegate.sellwildFeed(feedView, didRecordAdImpressionForZoneId: "43")
        delegate.sellwildFeedDidLoad(feedView)
        XCTAssertEqual(calls.count, 5, "the new wrapper's callbacks are empty")
        withExtendedLifetime(window) {}
    }

    func testTheWidgetLoadsAndForwardsLoadTapsAndErrors() throws {
        var calls: [String] = []
        let widget = SellwildWidget(config: try config(),
                                    onListingTap: { calls.append("tap \($0.url ?? "")") },
                                    onLoad: { calls.append("load") },
                                    onError: { _ in calls.append("error") })
        let (window, controller) = host(widget)
        let widgetView = try XCTUnwrap(find(SellwildWidgetView.self, in: controller.view))
        XCTAssertEqual(widgetLoads, 1, "makeUIView loads the page")
        widgetView.handleMessage(body: try BridgeMessageFactory.text(BridgeMessageFactory.variant("widget-loaded")))
        widgetView.handleMessage(body: try BridgeMessageFactory.text(BridgeMessageFactory.variant("listing-click-url")))
        widgetView.webView(widgetView.webView, didFail: nil, withError: URLError(.cancelled))
        XCTAssertEqual(calls, ["load", "tap https://sellwild.com/listing/105140231", "error"])

        controller.rootView = SellwildWidget(config: try config())
        controller.view.layoutIfNeeded()
        drainMain()
        XCTAssertTrue(find(SellwildWidgetView.self, in: controller.view) === widgetView)
        widgetView.webView.configuration.userContentController
            .removeScriptMessageHandler(forName: SellwildWidgetPage.messageHandlerName)
        withExtendedLifetime(window) {}
    }

    func testTheWidgetWithoutCallbacksIgnoresThem() throws {
        let (window, controller) = host(SellwildWidget(config: try config()))
        let widgetView = try XCTUnwrap(find(SellwildWidgetView.self, in: controller.view))
        widgetView.handleMessage(body: try BridgeMessageFactory.text(BridgeMessageFactory.variant("widget-loaded")))
        widgetView.webView(widgetView.webView, didFail: nil, withError: URLError(.cancelled))
        widgetView.webView.configuration.userContentController
            .removeScriptMessageHandler(forName: SellwildWidgetPage.messageHandlerName)
        withExtendedLifetime(window) {}
    }
}
