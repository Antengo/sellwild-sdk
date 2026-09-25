import XCTest
import UIKit
import WebKit
@testable import SellwildSDK

/// Records every `SellwildWidgetViewDelegate` call.
final class WidgetDelegateRecorder: SellwildWidgetViewDelegate {
    var calls: [String] = []
    var errors: [Error] = []

    func sellwildWidgetViewDidLoad(_ widgetView: SellwildWidgetView) { calls.append("load") }
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didTapListing listing: SellwildListing) {
        calls.append("tap \(listing.url ?? "")")
    }
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didReceiveAdImpressionForZoneId zoneId: String) {
        calls.append("impression \(zoneId)")
    }
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didFailWithError error: Error) {
        calls.append("fail")
        errors.append(error)
    }
}

/// A delegate that takes every default.
final class DefaultWidgetDelegate: SellwildWidgetViewDelegate {}

/// The deprecated WebView widget: the page it loads (through a recorded
/// loader), the bridge messages (from the bridge-message factory, handed
/// over directly and through a real WKWebView with no network), navigation
/// failures and the content process.
final class SellwildWidgetViewTests: FailureCapturingTestCase {

    private var loads: [(webView: WKWebView, html: String, baseURL: URL?)] = []
    private var widgets: [SellwildWidgetView] = []

    override func setUp() {
        super.setUp()
        loads = []
        widgets = []
        SellwildWidgetView.environment = SellwildWidgetView.Environment(
            loadPage: { [weak self] webView, html, baseURL in self?.loads.append((webView, html, baseURL)) },
            serializeJSON: SellwildPrebidConfig.serializeJSON
        )
    }

    override func tearDown() {
        SellwildWidgetView.environment = .live
        // The message handler holds the view; drop it so the views can go.
        for widget in widgets { detach(widget) }
        widgets = []
        super.tearDown()
    }

    private func detach(_ widget: SellwildWidgetView) {
        widget.webView.configuration.userContentController
            .removeScriptMessageHandler(forName: SellwildWidgetPage.messageHandlerName)
    }

    private func makeWidget(_ overrides: [String: Any] = [:]) throws -> (SellwildWidgetView, WidgetDelegateRecorder) {
        let widget = SellwildWidgetView(config: try AppConfigFactory.config(overrides, partnerCode: "demo"))
        let delegate = WidgetDelegateRecorder()
        widget.delegate = delegate
        objc_setAssociatedObject(widget, &Self.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        widgets.append(widget)
        return (widget, delegate)
    }

    private static var delegateKey: UInt8 = 0

    private func body(_ variant: String, _ overrides: [String: Any] = [:]) throws -> String {
        try BridgeMessageFactory.text(BridgeMessageFactory.variant(variant, overrides))
    }

    /// Runs the main queue until `condition` holds or `timeout` passes.
    private func spin(timeout: TimeInterval = 10, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: Load

    func testLoadHandsThePageToTheWebView() throws {
        let (widget, _) = try makeWidget()
        widget.load()
        let load = try XCTUnwrap(loads.first)
        XCTAssertTrue(load.webView === widget.webView)
        XCTAssertEqual(load.baseURL?.absoluteString, "https://widget.sellwild.com")
        XCTAssertTrue(load.html.contains(#"partner-code="demo""#))
        XCTAssertTrue(load.html.contains("partner.js"))
        capture.none()
    }

    func testARemoteValueThatCannotBeWrittenIsReported() throws {
        SellwildWidgetView.environment.serializeJSON = { _ in throw PlannedError() }
        let (widget, _) = try makeWidget(["APP_LIST": ["a"]])
        widget.load()
        XCTAssertEqual(loads.count, 1, "the page still loads")
        let events = capture.events
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(Set(events.map(\.action)), ["widget.attributes.exception"])
        XCTAssertEqual(capture.calls, events.count, "one report for each value left out")
        let list = try XCTUnwrap(events.first { $0.attributes["msg"]?.contains("APP_LIST") == true })
        XCTAssertEqual(list.attributes["errName"], "PlannedError")
        XCTAssertEqual(list.label, "webview")
    }

    // MARK: Bridge messages

    func testMessagesReachTheDelegateAndTheHostClosure() throws {
        let (widget, delegate) = try makeWidget()
        var tapped: [String?] = []
        widget.onListingTap = { tapped.append($0.url) }
        widget.handleMessage(body: try body("listing-click-url"))
        widget.handleMessage(body: try body("ad-impression-text-zone"))
        widget.handleMessage(body: try body("widget-loaded"))
        XCTAssertEqual(delegate.calls, ["tap https://sellwild.com/listing/105140231", "impression 43", "load"])
        XCTAssertEqual(tapped, ["https://sellwild.com/listing/105140231"])
        capture.none()
    }

    func testAPageErrorIsReportedAndTheDelegateGetsTheGenericError() throws {
        let (widget, delegate) = try makeWidget()
        widget.handleMessage(body: try body("error"))
        XCTAssertEqual(delegate.calls, ["fail"])
        XCTAssertEqual(delegate.errors.first?.localizedDescription, SellwildError.invalidResponse.localizedDescription)
        let event = capture.only(.bridgeScriptException, label: .webview)
        XCTAssertEqual(event?.attributes["msg"], "Uncaught TypeError: Cannot read properties of undefined")

        resetCapture()
        widget.handleMessage(body: try body("error", ["message": Factory.remove]))
        XCTAssertEqual(capture.only(.bridgeScriptException, label: .webview)?.attributes["msg"],
                       "the widget page reported an error with no message")
    }

    func testABrokenMessageIsReportedAndIgnored() throws {
        let (widget, delegate) = try makeWidget()
        widget.handleMessage(body: "{not json")
        XCTAssertEqual(delegate.calls, [])
        let event = capture.only(.bridgeMessageParse, label: .bridge)
        XCTAssertEqual(event?.attributes["severity"], "warn")
        XCTAssertNotNil(event?.attributes["errName"])
    }

    func testABrokenListingStillOpensItsURLAndIsReportedOnce() throws {
        let (widget, delegate) = try makeWidget()
        var tapped: [String?] = []
        widget.onListingTap = { tapped.append($0.url) }
        widget.handleMessage(body: try body("listing-click-stub", ["listing": ["title": 5]]))
        XCTAssertEqual(delegate.calls, ["tap https://sellwild.com/listing/105140231"], "the URL still opens")
        XCTAssertEqual(tapped, ["https://sellwild.com/listing/105140231"])
        let undecodable = capture.only(.bridgeMessageInvalid, label: .bridge)
        // The decoder's own text follows the message.
        XCTAssertEqual(undecodable?.attributes["msg"]?.hasPrefix("LISTING_CLICK listing could not be decoded"), true)
        XCTAssertEqual(undecodable?.attributes["severity"], "warn")
        XCTAssertNotNil(undecodable?.attributes["errName"])

        resetCapture()
        let listingText = try Factory.offSchema(because: "listing must be an object") {
            try BridgeMessageFactory.variant("listing-click-url", ["listing": "105140231"])
        }
        widget.handleMessage(body: try BridgeMessageFactory.text(listingText))
        XCTAssertEqual(delegate.calls, ["tap https://sellwild.com/listing/105140231",
                                        "tap https://sellwild.com/listing/105140231"], "the URL still opens")
        XCTAssertEqual(capture.only(.bridgeMessageInvalid, label: .bridge)?.attributes["msg"],
                       "LISTING_CLICK listing is not an object")
    }

    func testTheWebViewDeliversBridgeMessages() throws {
        let (widget, delegate) = try makeWidget()
        let host = Host()
        host.add(widget)
        let text = try body("ad-impression-text-zone")
        let literal = String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
        widget.webView.loadHTMLString(
            "<script>window.webkit.messageHandlers.sellwildWidget.postMessage(\(literal))</script>", baseURL: nil)
        spin { !delegate.calls.isEmpty }
        XCTAssertEqual(delegate.calls, ["impression 43"])
        withExtendedLifetime(host) {}
    }

    func testTheGeneratedBridgeScriptPostsLoadTapsAndErrors() throws {
        var config = try AppConfigFactory.config(partnerCode: "demo")
        // No network: the widget bundle is an empty inline script and the page
        // has no base URL.
        config.widgetJsUrl = "data:text/javascript,"
        let (widget, delegate) = try makeWidget()
        widget.config = config
        let host = Host()
        host.add(widget)
        let page = SellwildWidgetPage.html(config: config, attributes: SellwildWidgetPage.attributes(config: config).attributes)
        widget.webView.loadHTMLString(page, baseURL: nil)
        spin { delegate.calls.contains("load") }
        XCTAssertEqual(delegate.calls, ["load"], "WIDGET_LOADED after DOMContentLoaded")

        widget.webView.evaluateJavaScript("window.open('https://sellwild.com/listing/5'); true", completionHandler: nil)
        spin { delegate.calls.count == 2 }
        XCTAssertEqual(delegate.calls.last, "tap https://sellwild.com/listing/5", "window.open becomes LISTING_CLICK")

        widget.webView.evaluateJavaScript("setTimeout(function() { throw new Error('boom') }, 0); true", completionHandler: nil)
        spin { delegate.calls.count == 3 }
        XCTAssertEqual(delegate.calls.last, "fail")
        // WebKit gives an opaque-origin page's error as "Script error.".
        XCTAssertEqual(capture.events.map(\.action), ["bridge.script.exception"])
        XCTAssertNotNil(capture.events.first?.attributes["msg"])
        withExtendedLifetime(host) {}
    }

    func testTheDelegateDefaultsDoNothing() throws {
        let (widget, _) = try makeWidget()
        let delegate = DefaultWidgetDelegate()
        widget.delegate = delegate
        for variant in ["listing-click-url", "ad-impression-text-zone", "widget-loaded", "error"] {
            widget.handleMessage(body: try body(variant))
        }
        widget.webView(widget.webView, didFail: nil, withError: URLError(.cancelled))
        XCTAssertEqual(capture.events.map(\.action), ["bridge.script.exception"])
    }

    // MARK: Navigation

    func testAFailedNavigationIsReportedUnlessItWasCancelled() throws {
        let (widget, delegate) = try makeWidget()
        widget.webView(widget.webView, didFinish: nil)
        widget.webView(widget.webView, didFail: nil, withError: URLError(.cancelled))
        capture.none()
        XCTAssertEqual(delegate.calls, ["fail"], "the delegate hears every failure, as before")

        widget.webView(widget.webView, didFail: nil, withError: URLError(.notConnectedToInternet))
        let failed = capture.only(.widgetWebviewLoadNetwork, label: .webview)
        XCTAssertEqual(failed?.attributes["msg"]?.hasPrefix("the widget page failed to load"), true)
        XCTAssertEqual(delegate.calls, ["fail", "fail"])
    }

    func testAProvisionalNavigationFailureIsReported() throws {
        let (widget, delegate) = try makeWidget()
        widget.webView(widget.webView, didFailProvisionalNavigation: nil, withError: NSError(domain: "WebKitErrorDomain", code: 102))
        capture.none()
        widget.webView(widget.webView, didFailProvisionalNavigation: nil, withError: URLError(.cannotFindHost))
        XCTAssertEqual(capture.only(.widgetWebviewLoadNetwork, label: .webview)?.attributes["msg"]?
            .hasPrefix("the widget page failed to start loading"), true)
        XCTAssertEqual(delegate.calls, [], "the delegate is not told, as before")
    }

    func testAContentProcessThatEndsIsReported() throws {
        let (widget, _) = try makeWidget()
        widget.webViewWebContentProcessDidTerminate(widget.webView)
        XCTAssertEqual(capture.only(.widgetWebviewProcessException, label: .webview)?.attributes["severity"], "error")
    }

    func testAnHTTPErrorOnTheMainFrameIsReported() throws {
        let (widget, delegate) = try makeWidget()
        let page = try XCTUnwrap(URL(string: "https://widget.sellwild.com/page?token=secret"))
        widget.reportHTTPStatus(try http(page, 404, "text/html"), isForMainFrame: true)
        let event = capture.only(.widgetWebviewLoadHttp, label: .webview)
        XCTAssertEqual(event?.attributes["httpStatus"], "404")
        XCTAssertEqual(event?.attributes["msg"], "HTTP 404")
        XCTAssertEqual(event?.attributes["host"], "widget.sellwild.com")
        XCTAssertEqual(event?.attributes["severity"], "error")

        resetCapture()
        widget.reportHTTPStatus(try http(page, 500, "text/html"), isForMainFrame: false)
        widget.reportHTTPStatus(try http(page, 200, "text/html"), isForMainFrame: true)
        capture.none()
        XCTAssertEqual(delegate.calls, [], "the delegate is not told, as before")
    }

    func testWebKitAsksTheWidgetAboutEachResponseAndGetsItsDefaultDecision() throws {
        let (widget, _) = try makeWidget()
        // WebKit's rule when the method was absent: show what it can show,
        // cancel the rest. A local scheme, so nothing reaches the network.
        let shown = try XCTUnwrap(URL(string: "\(StatusSchemeHandler.scheme)://widget.local/page"))
        let shownView = try loadThroughWidget(widget, shown, mimeType: "text/html")
        XCTAssertEqual(shownView.url, shown, "a response WebKit can show is allowed")

        let unknown = try XCTUnwrap(URL(string: "\(StatusSchemeHandler.scheme)://widget.local/bundle.bin"))
        let unknownView = try loadThroughWidget(widget, unknown, mimeType: "application/x-sellwild-unknown")
        XCTAssertNotEqual(unknownView.url, unknown, "a response WebKit cannot show is cancelled")
        // A cancelled response ends the load as "frame load interrupted",
        // which is not a failure; a local scheme answer has no HTTP status.
        capture.none()
    }

    func testAnHTTPErrorWebKitDeliversIsReported() throws {
        let (widget, _) = try makeWidget()
        let page = try XCTUnwrap(URL(string: "\(StatusSchemeHandler.scheme)://widget.local/page"))
        let answeredAs = try XCTUnwrap(URL(string: "https://widget.sellwild.com/page"))
        _ = try loadThroughWidget(widget, page, handler: StatusSchemeHandler(mimeType: "text/html", status: 404,
                                                                            responseURL: answeredAs))
        let event = capture.only(.widgetWebviewLoadHttp, label: .webview)
        XCTAssertEqual(event?.attributes["httpStatus"], "404")
        XCTAssertEqual(event?.attributes["host"], "widget.sellwild.com")
    }

    private func http(_ url: URL, _ status: Int, _ mimeType: String) throws -> URLResponse {
        try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                      headerFields: ["Content-Type": mimeType]))
    }

    /// Loads `url` from a local scheme in a real web view (in a window) whose
    /// navigation delegate is `widget`, and waits until it stops loading.
    private func loadThroughWidget(_ widget: SellwildWidgetView, _ url: URL, mimeType: String) throws -> WKWebView {
        try loadThroughWidget(widget, url, handler: StatusSchemeHandler(mimeType: mimeType))
    }

    private func loadThroughWidget(_ widget: SellwildWidgetView, _ url: URL, handler: StatusSchemeHandler) throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: StatusSchemeHandler.scheme)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), configuration: configuration)
        webView.navigationDelegate = widget
        let host = Host()
        host.add(webView)
        let finished = expectation(description: "loaded \(url)")
        finished.assertForOverFulfill = false
        let observer = webView.observe(\.isLoading, options: [.new]) { webView, _ in
            if !webView.isLoading { finished.fulfill() }
        }
        webView.load(URLRequest(url: url))
        wait(for: [finished], timeout: 15)
        observer.invalidate()
        spin(timeout: 0.3) { false }
        withExtendedLifetime(host) {}
        return webView
    }

    // MARK: Lifetime and the live loader

    func testAWidgetWhoseHandlerIsRemovedGoesAway() throws {
        weak var gone: SellwildWidgetView?
        try autoreleasepool {
            let widget = SellwildWidgetView(config: try AppConfigFactory.config(partnerCode: "demo"))
            detach(widget)
            gone = widget
        }
        XCTAssertNil(gone)
    }

    func testTheLiveSerializerWritesJSON() throws {
        let data = try SellwildWidgetView.Environment.live.serializeJSON(["a"])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["a"]"#)
    }

    func testTheLiveLoaderLoadsTheHTML() throws {
        let (widget, _) = try makeWidget()
        let finished = expectation(description: "loaded")
        finished.assertForOverFulfill = false
        let observer = widget.webView.observe(\.isLoading, options: [.new]) { webView, _ in
            if !webView.isLoading { finished.fulfill() }
        }
        SellwildWidgetView.Environment.live.loadPage(widget.webView, "<p>offline</p>", nil)
        wait(for: [finished], timeout: 10)
        observer.invalidate()
    }
}

/// Answers every request on a local scheme with a chosen status, MIME type
/// and small body, so a real WKWebView asks its navigation delegate about a
/// response without the network. WebKit hands the delegate a plain
/// URLResponse when the answer's URL is the custom scheme (no status), and
/// an HTTPURLResponse with the status when the answer claims an https URL.
final class StatusSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "sellwild-test"
    let mimeType: String
    let status: Int
    /// The URL the answer claims, when it is not the request's.
    let responseURL: URL?

    init(mimeType: String, status: Int = 200, responseURL: URL? = nil) {
        self.mimeType = mimeType
        self.status = status
        self.responseURL = responseURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = responseURL ?? urlSchemeTask.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": mimeType]) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data("<p>local</p>".utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
