import UIKit
import WebKit

// MARK: - SellwildWidgetView

/// Full marketplace + ad widget rendered via WKWebView.
/// Embeds the Sellwild web widget inside a native UIView,
/// bridging listing click events and ad impressions back to native callbacks.
@objc
public final class SellwildWidgetView: UIView {

    // MARK: Public

    public var config: SellwildConfig
    public weak var delegate: SellwildWidgetViewDelegate?
    public var onListingTap: ((SellwildListing) -> Void)?

    // MARK: Private

    private lazy var webView: WKWebView = makeWebView()

    // MARK: Init

    public init(config: SellwildConfig) {
        self.config = config
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(config:)")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "sellwildWidget")
    }

    // MARK: Public Methods

    public func load() {
        let html = buildWidgetHTML()
        let baseURL = URL(string: "https://widget.sellwild.com")
        webView.loadHTMLString(html, baseURL: baseURL)
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
        cc.add(self, name: "sellwildWidget")
        wvConfig.userContentController = cc

        let wv = WKWebView(frame: .zero, configuration: wvConfig)
        wv.navigationDelegate = self
        wv.backgroundColor = .clear
        wv.isOpaque = false
        wv.scrollView.backgroundColor = .clear
        return wv
    }

    // Build HTML element attributes from config.
    // The widget reads config via withCustomizationsFromElement() using attribute names in any case.
    // Complex objects are JSON-encoded strings; parseValue() in the widget JSON.parses them.
    private func configAttributes() -> String {
        var attrs: [String] = []

        func add(_ name: String, _ value: String?) {
            guard let v = value, !v.isEmpty else { return }
            attrs.append("\(name)=\"\(v)\"")
        }
        func addBool(_ name: String, _ value: Bool) {
            if value { attrs.append("\(name)=\"true\"") }
        }
        func addNum(_ name: String, _ value: Int) {
            if value != 0 { attrs.append("\(name)=\"\(value)\"") }
        }
        func addJSON(_ name: String, _ value: Encodable?) {
            guard let v = value,
                  let data = try? JSONEncoder().encode(v),
                  let str = String(data: data, encoding: .utf8)
            else { return }
            let escaped = str.replacingOccurrences(of: "\"", with: "&quot;")
            attrs.append("\(name)=\"\(escaped)\"")
        }

        add("partner-code", config.partnerCode)
        add("listings", config.effectiveListingsUrl)
        // Disable remote customization fetch — see RN htmlBuilder.ts for details.
        attrs.append("customize=\"false\"")
        // Ad system selection — REQUIRED. AdStack silently does nothing if
        // adType is unset, meaning Prebid never loads. See RN htmlBuilder.ts.
        add("ad-type", config.adType ?? "PrebidOnly")
        add("gam-tag", config.gamTag)
        add("gpt-proxy-url", config.gptProxyUrl)
        addBool("disable-gpt", config.disableGpt)
        add("banner-zid", config.bannerZid)
        add("bottom-banner-zid", config.bottomBannerZid)
        add("mobile-banner-zid", config.mobileBannerZid)
        if !config.mobileZids.isEmpty { add("mobile-zid", config.mobileZids.joined(separator: ",")) }
        addBool("hide-banner-top", config.hideBannerTop)
        addBool("hide-banner-bottom", config.hideBannerBottom)
        addNum("ad-refresh-max", config.adRefreshMax)
        addNum("ad-refresh-max-mobile", config.adRefreshMaxMobile)
        addNum("ad-refresh-interval", Int(config.adRefreshInterval * 1000))
        addBool("boltive", config.boltive)
        add("boltive-client-id", config.boltiveClientId.isEmpty ? nil : config.boltiveClientId)
        addBool("lotame", config.lotame)
        add("title", config.title)
        add("link-text", config.linkText)
        addNum("font-size", config.fontSize)
        add("font-color", config.fontColor)
        add("price-color", config.priceColor)
        add("price-font-color", config.priceFontColor)
        if !config.colors.isEmpty { add("colors", config.colors.joined(separator: ",")) }
        addBool("debug", config.debug)

        // Mobile ad controls
        addBool("enable-interstitial", config.enableInterstitial)
        addBool("enable-fullscreen-video", config.enableFullscreenVideo)
        addNum("interstitials-per-session", config.interstitialsPerSession)
        addNum("video-takeovers-per-session", config.videoTakeoversPerSession)

        // ─── Remote passthrough ────────────────────────────────────────────
        // Forward the raw CDN payload verbatim. The widget's attribute parser
        // is case-insensitive (kebab-case / camelCase / CONSTANT_CASE all
        // work) and accepts unknown keys, so every CMS-defined bidder,
        // waterfall partner, or ad-network setting flows through to the
        // WebView without an SDK release.
        let emittedFromTyped: Set<String> = [
            "CODE", "SLUG", "NAME", "LISTINGS",
            "TITLE", "LINK_TEXT", "BUY_NOW_TEXT", "TITLE_COLOR", "LINK_COLOR",
            "FONT_FAMILY", "FONT_URL", "FONT_COLOR", "PRICE_COLOR",
            "PRICE_FONT_COLOR", "MARGIN_BOTTOM", "OVERLAY_TITLE", "COLORS",
            "WATERMARK", "WATERMARK_TITLE",
            "BANNER_ZID", "BOTTOM_BANNER_ZID", "MOBILE_BANNER_ZID",
            "MOBILE_ZID", "HIDE_BANNER_TOP", "HIDE_BANNER_BOTTOM", "GAM",
            "DISABLE_GPT", "AD_DISABLE_DISPLAY",
            "AD_REFRESH_MAX", "AD_REFRESH_MAX_MOBILE", "AD_REFRESH_INTERVAL",
            "MAX_FAILED_AUCTIONS",
            "GPP_ENABLED", "TCF_VERSION", "IAB_CATS",
            "ENABLE_INTERSTITIAL", "ENABLE_FULLSCREEN_VIDEO",
            "INTERSTITIALS_PER_SESSION", "VIDEO_TAKEOVERS_PER_SESSION",
            "APP_BUNDLE_ID", "APP_STORE_URL",
            "BOLTIVE", "BOLTIVE_CLIENT_ID", "LOTAME",
            "DEBUG",
        ]
        if let remote = config.remoteValues {
            for (key, value) in remote where !emittedFromTyped.contains(key) {
                emitRemoteAttr(name: key, value: value, attrs: &attrs)
            }
        }

        return attrs.joined(separator: "\n    ")
    }

    /// Emits a single remote-passthrough attribute. Strings/numbers/bools are
    /// stringified directly; arrays and dictionaries are JSON-encoded.
    private func emitRemoteAttr(name: String, value: Any, attrs: inout [String]) {
        // Skip empty / falsy values to match the typed-block convention.
        if value is NSNull { return }
        if let b = value as? Bool { if !b { return } ; attrs.append("\(name)=\"true\"") ; return }
        if let s = value as? String {
            if s.isEmpty { return }
            let escaped = s.replacingOccurrences(of: "\"", with: "&quot;")
            attrs.append("\(name)=\"\(escaped)\"")
            return
        }
        if let n = value as? NSNumber {
            attrs.append("\(name)=\"\(n)\"")
            return
        }
        // Array or dictionary → JSON-encode and HTML-escape quotes.
        if let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let str = String(data: data, encoding: .utf8) {
            let escaped = str.replacingOccurrences(of: "\"", with: "&quot;")
            attrs.append("\(name)=\"\(escaped)\"")
        }
    }

    // Build a Prebid.js pre-configuration <script> block.
    // This runs before prebid.js loads (via pbjs.que) and addresses two WebView issues:
    //  1. ortb2.app — declares in-app inventory so DSPs bid on the correct traffic type.
    //  2. userSync — disables iframe syncs (blocked by WKWebView) to avoid wasted requests.
    private func prebidPreConfigScript() -> String {
        var ortb2AppFields: [String] = [
            "\"publisher\": {\"id\": \"\(config.partnerCode)\"}",
        ]
        if let bundle = config.appBundleId, !bundle.isEmpty {
            ortb2AppFields.append("\"bundle\": \"\(bundle)\"")
        }
        if let storeUrl = config.appStoreUrl, !storeUrl.isEmpty {
            ortb2AppFields.append("\"storeurl\": \"\(storeUrl)\"")
        }
        let ortb2App = "{\(ortb2AppFields.joined(separator: ", "))}"

        var s2sConfigBlock = ""
        if let ps = config.prebidServer {
            let bidderList = ps.bidders.map { "\"\($0)\"" }.joined(separator: ", ")
            let syncLine = ps.syncEndpoint.map { url in
                ", \"syncEndpoint\": {\"p1Consent\": \"\(url)\", \"noP1Consent\": \"\(url)\"}"
            } ?? ""
            s2sConfigBlock = """
            ,
                          // Route all bidder calls through Prebid Server (S2S mode).
                          s2sConfig: {
                            "accountId": "\(ps.accountId)",
                            "bidders": [\(bidderList)],
                            "timeout": \(ps.timeout),
                            "adapter": "prebidServer",
                            "endpoint": {"p1Consent": "\(ps.endpoint)", "noP1Consent": "\(ps.endpoint)"}\(syncLine)
                          }
            """
        }

        let debugFlag = config.debug ? ", \"debug\": true" : ""

        return """
        <script>
          // Prebid.js WebView pre-config — runs before prebid.js initialises via pbjs.que.
          window.pbjs = window.pbjs || {};
          window.pbjs.que = window.pbjs.que || [];
          window.pbjs.que.push(function() {
            window.pbjs.setConfig({
              ortb2: { app: \(ortb2App) },
              userSync: {
                filterSettings: { iframe: { bidders: '*', filter: 'exclude' } },
                syncDelay: 5000
              }\(s2sConfigBlock)\(debugFlag)
            });
          });
        </script>
        """
    }

    private func buildWidgetHTML() -> String {
        // Allow override with a publisher-specific compiled bundle.
        // Default: https://widget.sellwild.com/partner.js (generic, reads attrs from element)
        // partner.js loads its own Prebid build internally — do not inject a
        // separate prebid <script> tag (causes double-load and breaks header bidding).
        let widgetSrc = config.widgetJsUrl ?? "https://widget.sellwild.com/partner.js"
        let attrs = configAttributes()

        let prebidPreConfig = prebidPreConfigScript()

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            html, body { width: 100%; background: transparent; overflow-x: hidden; }
          </style>
          \(prebidPreConfig)
        </head>
        <body>
          <sellwild-widget
            \(attrs)
          ></sellwild-widget>

          <script>
            (function() {
              function send(type, payload) {
                try {
                  var msg = JSON.stringify(Object.assign({ type: type }, payload || {}));
                  window.webkit.messageHandlers.sellwildWidget.postMessage(msg);
                } catch(e) {}
              }
              // partner/index.tsx calls window.open() on listing tap — intercept it
              var _open = window.open;
              window.open = function(url) {
                if (url && (url.indexOf('itemDetail') !== -1 || url.indexOf('sellwild.com') !== -1)) {
                  send('LISTING_CLICK', { url: url });
                  return null;
                }
                return _open.apply(window, arguments);
              };
              document.addEventListener('DOMContentLoaded', function() {
                setTimeout(function() { send('WIDGET_LOADED'); }, 600);
              });
              window.addEventListener('error', function(e) {
                send('ERROR', { message: e.message || 'Widget load error' });
              });
            })();
          </script>

          <script async src="\(widgetSrc)"></script>
        </body>
        </html>
        """
    }
}

// MARK: - WKScriptMessageHandler

extension SellwildWidgetView: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            let body = message.body as? String,
            let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        switch type {
        case "LISTING_CLICK":
            // The web widget sends window.open(url) on listing tap; only the URL
            // is available at the bridge boundary (no full listing object).
            if let listingData = json["listing"] as? [String: Any],
               let itemData = try? JSONSerialization.data(withJSONObject: listingData),
               let listing = try? JSONDecoder().decode(SellwildListing.self, from: itemData) {
                // Future-compatible path: full listing object present.
                delegate?.sellwildWidgetView(self, didTapListing: listing)
                onListingTap?(listing)
            } else if let urlString = json["url"] as? String {
                // Current path: URL-only from window.open() interception.
                // Reconstruct a minimal listing stub from JSON so callers can navigate.
                let stubJson: [String: Any] = ["id": "", "status": "active",
                                               "title": "", "url": urlString]
                if let stubData = try? JSONSerialization.data(withJSONObject: stubJson),
                   let stub = try? JSONDecoder().decode(SellwildListing.self, from: stubData) {
                    delegate?.sellwildWidgetView(self, didTapListing: stub)
                    onListingTap?(stub)
                }
            }
        case "AD_IMPRESSION":
            let zoneId = json["zoneId"] as? String ?? ""
            delegate?.sellwildWidgetView(self, didReceiveAdImpressionForZoneId: zoneId)
        case "WIDGET_LOADED":
            delegate?.sellwildWidgetViewDidLoad(self)
        case "ERROR":
            delegate?.sellwildWidgetView(self, didFailWithError: SellwildError.invalidResponse)
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension SellwildWidgetView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        delegate?.sellwildWidgetView(self, didFailWithError: error)
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
