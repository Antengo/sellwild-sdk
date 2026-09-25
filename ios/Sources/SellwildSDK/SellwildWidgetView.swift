import UIKit
import WebKit

// MARK: - SellwildWidgetView

/// Full marketplace + ad widget rendered via WKWebView.
/// Embeds the Sellwild web widget inside a native UIView,
/// bridging listing click events and ad impressions back to native callbacks.
///
/// Deprecated surface: failure reporting only, no new features. The page it
/// loads and the bridge messages it reads are built and parsed in
/// `SellwildWidgetPage`.
@objc
public final class SellwildWidgetView: UIView {

    // MARK: Public

    public var config: SellwildConfig
    public weak var delegate: SellwildWidgetViewDelegate?
    public var onListingTap: ((SellwildListing) -> Void)?

    // MARK: Private

    lazy var webView: WKWebView = makeWebView()

    // MARK: Init

    public init(config: SellwildConfig) {
        self.config = config
        super.init(frame: .zero)
        setup()
    }

    // sellwild-coverage:exclude-begin(crash-guard) init(coder:) traps by design (storyboards are not supported).
    required init?(coder: NSCoder) {
        fatalError("Use init(config:)")
    }
    // sellwild-coverage:exclude-end

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: SellwildWidgetPage.messageHandlerName)
    }

    // MARK: Public Methods

    public func load() {
        let environment = Self.environment
        let (attributes, dropped) = SellwildWidgetPage.attributes(config: config, serialize: environment.serializeJSON)
        for attribute in dropped {
            SellwildFailures.log(code: .widgetAttributesException, component: .webview, severity: .warn,
                                 error: attribute.problem.error,
                                 message: "remote value \(attribute.name) could not be written as a widget attribute; it was left out")
        }
        let html = SellwildWidgetPage.html(config: config, attributes: attributes)
        environment.loadPage(webView, html, SellwildWidgetPage.baseURL)
    }

    // MARK: Private

    private func setup() {
        addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func makeWebView() -> WKWebView {
        let wvConfig = WKWebViewConfiguration()
        // JavaScript is required for the Sellwild widget and Prebid.js.
        if #available(iOS 14.0, *) {
            wvConfig.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            wvConfig.preferences.javaScriptEnabled = true
        }
        wvConfig.allowsInlineMediaPlayback = true
        wvConfig.mediaTypesRequiringUserActionForPlayback = []

        let cc = WKUserContentController()
        cc.add(self, name: SellwildWidgetPage.messageHandlerName)
        wvConfig.userContentController = cc

        let wv = WKWebView(frame: .zero, configuration: wvConfig)
        wv.navigationDelegate = self
        wv.backgroundColor = .clear
        wv.isOpaque = false
        wv.scrollView.backgroundColor = .clear
        return wv
    }

    /// Acts on one bridge message body, and reports what was wrong with it.
    func handleMessage(body: Any) {
        let parsed = SellwildWidgetPage.parse(body: body)
        if let problem = parsed.problem {
            SellwildFailures.log(code: problem.code, component: .bridge, severity: .warn, error: problem.error,
                                 message: problem.message)
        }
        switch parsed.message {
        case .listingClick(let listing)?:
            delegate?.sellwildWidgetView(self, didTapListing: listing)
            onListingTap?(listing)
        case .adImpression(let zoneId)?:
            delegate?.sellwildWidgetView(self, didReceiveAdImpressionForZoneId: zoneId)
        case .loaded?:
            delegate?.sellwildWidgetViewDidLoad(self)
        case .error(let message)?:
            // The page's own error text is reported (sanitized); the delegate
            // still gets the generic error it always got.
            SellwildFailures.log(code: .bridgeScriptException, component: .webview,
                                 message: message ?? "the widget page reported an error with no message")
            delegate?.sellwildWidgetView(self, didFailWithError: SellwildError.invalidResponse)
        case nil:
            break
        }
    }

    /// A main-frame navigation answered with an HTTP error status. Failure
    /// reporting only: the response is still decided as WebKit would.
    func reportHTTPStatus(_ response: URLResponse, isForMainFrame: Bool) {
        guard let status = SellwildWidgetPage.httpFailureStatus(response, isForMainFrame: isForMainFrame) else { return }
        SellwildFailures.log(code: .widgetWebviewLoadHttp, component: .webview, message: "HTTP \(status)",
                             httpStatus: status, url: response.url?.absoluteString)
    }

    /// A navigation failed. A cancelled one (a new load replaced it) is not a
    /// failure.
    func reportNavigationFailure(_ error: Error, provisional: Bool) {
        guard SellwildWidgetPage.isNavigationFailure(error) else { return }
        SellwildFailures.log(code: .widgetWebviewLoadNetwork, component: .webview, error: error,
                             message: provisional ? "the widget page failed to start loading" : "the widget page failed to load")
    }
}

// MARK: - Environment

extension SellwildWidgetView {
    /// What the widget calls outside itself. Partners always get `live`;
    /// tests replace `SellwildWidgetView.environment`.
    struct Environment {
        /// Loads the page HTML with its base URL. The page then loads the
        /// widget bundle (partner.js) from the network.
        var loadPage: (WKWebView, String, URL?) -> Void
        /// Writes a remote list or object as an attribute's JSON text.
        var serializeJSON: (Any) throws -> Data

        static let live = Environment(loadPage: { webView, html, baseURL in
            webView.loadHTMLString(html, baseURL: baseURL)
        }, serializeJSON: SellwildPrebidConfig.serializeJSON)
    }

    static var environment = Environment.live
}

// MARK: - WKScriptMessageHandler

extension SellwildWidgetView: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        handleMessage(body: message.body)
    }
}

// MARK: - WKNavigationDelegate

extension SellwildWidgetView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        reportHTTPStatus(navigationResponse.response, isForMainFrame: navigationResponse.isForMainFrame)
        // WebKit's rule when this method is absent: show the response if it can.
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportNavigationFailure(error, provisional: false)
        delegate?.sellwildWidgetView(self, didFailWithError: error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: Error) {
        reportNavigationFailure(error, provisional: true)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        SellwildFailures.log(code: .widgetWebviewProcessException, component: .webview,
                             message: "the widget WebView content process ended; the widget is blank until it is loaded again")
    }
}

// MARK: - Delegate Protocol

public protocol SellwildWidgetViewDelegate: AnyObject {
    func sellwildWidgetViewDidLoad(_ widgetView: SellwildWidgetView)
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didTapListing listing: SellwildListing)
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didReceiveAdImpressionForZoneId zoneId: String)
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didFailWithError error: Error)
}

public extension SellwildWidgetViewDelegate {
    func sellwildWidgetViewDidLoad(_ widgetView: SellwildWidgetView) {}
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didTapListing listing: SellwildListing) {}
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didReceiveAdImpressionForZoneId zoneId: String) {}
    func sellwildWidgetView(_ widgetView: SellwildWidgetView, didFailWithError error: Error) {}
}
