import Foundation

/// The pure half of the deprecated `SellwildWidgetView`: the page HTML (the
/// `<sellwild-widget>` attributes, the Prebid.js pre-config script and the
/// bridge script) and the parsing of the messages the bridge script posts.
/// No I/O and no logging: the view loads the page and reports problems.
enum SellwildWidgetPage {

    /// The generic widget bundle; it reads its config from the element.
    static let defaultWidgetJsUrl = "https://widget.sellwild.com/partner.js"
    /// The page's base URL.
    static let baseURL = URL(string: "https://widget.sellwild.com")
    /// The `window.webkit.messageHandlers` name the bridge script posts to.
    static let messageHandlerName = "sellwildWidget"

    // MARK: Attributes

    /// Keys the typed attributes already carry, so the remote passthrough
    /// does not emit them twice.
    static let emittedFromTyped: Set<String> = [
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

    /// A remote value that could not become an attribute and was left out
    /// (`widget.attributes.exception`).
    struct DroppedAttribute {
        let name: String
        let problem: SellwildPrebidConfig.JSONProblem
    }

    /// The element attributes, one `name="value"` each, and the remote values
    /// left out. The widget reads attributes in any case; objects are JSON
    /// text it parses. Typed values are not escaped (as before).
    static func attributes(config: SellwildConfig,
                           serialize: (Any) throws -> Data = SellwildPrebidConfig.serializeJSON)
        -> (attributes: [String], dropped: [DroppedAttribute]) {
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
        // sellwild-coverage:exclude-begin(dead) dead: pending delete decision. Nothing calls addJSON (phase-1 survey, SellwildWidgetView.swift:98-105); it moved here unchanged with the attribute builder.
        func addJSON(_ name: String, _ value: Encodable?) {
            guard let v = value,
                  let data = try? JSONEncoder().encode(v),
                  let str = String(data: data, encoding: .utf8)
            else { return }
            let escaped = str.replacingOccurrences(of: "\"", with: "&quot;")
            attrs.append("\(name)=\"\(escaped)\"")
        }
        // sellwild-coverage:exclude-end

        add("partner-code", config.partnerCode)
        add("listings", config.effectiveListingsUrl)
        // Disable the remote customization fetch (see the RN htmlBuilder.ts).
        attrs.append("customize=\"false\"")
        // Required: AdStack does nothing when adType is unset, so Prebid never
        // loads (see the RN htmlBuilder.ts).
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

        // Remote passthrough: the raw CDN payload, so every CMS bidder,
        // waterfall partner or ad-network setting reaches the widget without an
        // SDK release. Dictionary order, so attribute order varies.
        var dropped: [DroppedAttribute] = []
        for (key, value) in config.remoteValues ?? [:] where !emittedFromTyped.contains(key) {
            switch remoteAttribute(name: key, value: value, serialize: serialize) {
            case .success(let attribute?): attrs.append(attribute)
            case .success(nil): break
            case .failure(let problem): dropped.append(DroppedAttribute(name: key, problem: problem))
            }
        }
        return (attrs, dropped)
    }

    /// One remote passthrough attribute. Text, numbers and `true` are written
    /// as they are (quotes in text become `&quot;`); arrays and objects become
    /// JSON text. nil for a value that is left out on purpose: null, false, "".
    static func remoteAttribute(name: String, value: Any,
                                serialize: (Any) throws -> Data = SellwildPrebidConfig.serializeJSON)
        -> Result<String?, SellwildPrebidConfig.JSONProblem> {
        if value is NSNull { return .success(nil) }
        if let b = value as? Bool { return .success(b ? "\(name)=\"true\"" : nil) }
        if let s = value as? String {
            return .success(s.isEmpty ? nil : "\(name)=\"\(escapeQuotes(s))\"")
        }
        if let n = value as? NSNumber { return .success("\(name)=\"\(n)\"") }
        // An array or an object: JSON text.
        return SellwildPrebidConfig.json(value, serialize: serialize).map { "\(name)=\"\(escapeQuotes($0))\"" }
    }

    static func escapeQuotes(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: Scripts and page

    /// The Prebid.js pre-config `<script>`, run before prebid.js through
    /// `pbjs.que`: `ortb2.app` so DSPs see in-app inventory, iframe user syncs
    /// off (WKWebView blocks them), the Prebid Server S2S config when typed
    /// config has one, and debug.
    static func prebidPreConfigScript(config: SellwildConfig) -> String {
        var ortb2AppFields: [String] = [
            "\"publisher\": {\"id\": \"\(config.partnerCode)\"}",
        ]
        // app.bundle must be the numeric App Store id on iOS (buyers key on
        // it), as on the native path; the configured bundle only when no id
        // can be parsed from the store URL.
        if let numericId = SellwildPrebidMobile.appStoreId(from: config.appStoreUrl) {
            ortb2AppFields.append("\"bundle\": \"\(numericId)\"")
        } else if let bundle = config.appBundleId, !bundle.isEmpty {
            ortb2AppFields.append("\"bundle\": \"\(bundle)\"")
        }
        if let storeUrl = config.appStoreUrl, !storeUrl.isEmpty {
            ortb2AppFields.append("\"storeurl\": \"\(storeUrl)\"")
        }
        let ortb2App = "{\(ortb2AppFields.joined(separator: ", "))}"

        var s2sConfigBlock = ""
        if let ps = config.prebidServer {
            let bidderList = ps.bidders.map { "\"\($0)\"" }.joined(separator: ", ")
            var syncLine = ""
            if let url = ps.syncEndpoint {
                syncLine = ", \"syncEndpoint\": {\"p1Consent\": \"\(url)\", \"noP1Consent\": \"\(url)\"}"
            }
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

    /// The whole page: the pre-config script, the `<sellwild-widget>` element,
    /// the bridge script and the widget bundle (`widgetJsUrl`, else
    /// partner.js, which loads its own Prebid build). This is the page the
    /// widget always loaded, except that the bridge script counts the messages
    /// it could not post (`window.__sellwildBridgeFailures`) instead of
    /// dropping them in an empty catch.
    static func html(config: SellwildConfig, attributes: [String]) -> String {
        let widgetSrc = config.widgetJsUrl ?? defaultWidgetJsUrl
        let attrs = attributes.joined(separator: "\n    ")
        let prebidPreConfig = prebidPreConfigScript(config: config)

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
                } catch(e) {
                  // The bridge is the page's only way out, so this cannot be reported.
                  // Count it where a debugger can read it (as the Android and React
                  // Native pages do).
                  window.__sellwildBridgeFailures = (window.__sellwildBridgeFailures || 0) + 1;
                }
              }
              // partner/index.tsx calls window.open() on listing tap — intercept ALL
              // calls. Listings link to external sites (eBay, Amazon, dealer sites, etc.)
              // so we can't filter by domain. The widget only uses window.open for listings.
              var _open = window.open;
              window.open = function(url) {
                if (url) {
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

    // MARK: Navigation

    /// WebKit's error domain (`WKErrorDomain` is another one; this is the
    /// loader's) and its "frame load interrupted" code.
    static let webKitErrorDomain = "WebKitErrorDomain"
    static let frameLoadInterruptedCode = 102

    /// The HTTP error status (4xx or 5xx) of a navigation response that is a
    /// failure (`widget.webview_load.http`), or nil. Only the main frame is
    /// the widget: a sub-frame is an ad iframe. The page's own HTML string has
    /// no HTTP status, so this fires only when the main frame loads over HTTP.
    static func httpFailureStatus(_ response: URLResponse, isForMainFrame: Bool) -> Int? {
        guard isForMainFrame, let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return nil }
        return http.statusCode
    }

    /// Whether a failed navigation is a failure. A load cancelled by a newer
    /// one (`NSURLErrorCancelled`) or interrupted by a policy change is not.
    static func isNavigationFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return false }
        if ns.domain == webKitErrorDomain && ns.code == frameLoadInterruptedCode { return false }
        return true
    }

    // MARK: Bridge messages

    /// A message the bridge script posted.
    enum Message {
        /// A listing tap: the full listing when the page sends one, else a
        /// stub with only the URL (what `window.open` interception gives).
        case listingClick(SellwildListing)
        case adImpression(zoneId: String)
        case loaded
        /// An in-page error, with the page's text (`bridge.script.exception`).
        case error(message: String?)
    }

    /// Something wrong with a message (`bridge.message.*`).
    struct Problem {
        let code: SellwildFailureCode
        let message: String
        var error: Error?
    }

    /// A parsed message and, when something was wrong with it, the problem.
    /// Both can be set: a LISTING_CLICK whose listing could not be decoded
    /// still opens its URL.
    struct Parsed {
        var message: Message?
        var problem: Problem?
    }

    /// Parses one `postMessage` body: JSON text with a `type`
    /// (contracts/schemas/bridge-message.schema.json).
    static func parse(body: Any) -> Parsed {
        guard let text = body as? String else {
            return Parsed(problem: Problem(code: .bridgeMessageInvalid, message: "bridge message is not text"))
        }
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: Data(text.utf8))
        } catch {
            return Parsed(problem: Problem(code: .bridgeMessageParse, message: "bridge message is not valid JSON", error: error))
        }
        guard let object = json as? [String: Any] else {
            return Parsed(problem: Problem(code: .bridgeMessageInvalid, message: "bridge message is not a JSON object"))
        }
        guard let type = object["type"] as? String else {
            return Parsed(problem: Problem(code: .bridgeMessageInvalid, message: "bridge message has no type"))
        }
        switch type {
        case "LISTING_CLICK":
            return listingClick(object)
        case "AD_IMPRESSION":
            // A number zone reads as "" (known drift: Android keeps "43").
            return Parsed(message: .adImpression(zoneId: object["zoneId"] as? String ?? ""))
        case "WIDGET_LOADED":
            return Parsed(message: .loaded)
        case "ERROR":
            return Parsed(message: .error(message: object["message"] as? String))
        default:
            return Parsed(problem: Problem(code: .bridgeMessageUnsupported, message: "bridge message type is unknown"))
        }
    }

    /// The listing of a LISTING_CLICK: its `listing` object when that
    /// decodes, else a stub from its `url`.
    private static func listingClick(_ object: [String: Any]) -> Parsed {
        var candidates: [[String: Any]] = []
        var parsed = Parsed()
        if let listing = object["listing"] {
            if let listing = listing as? [String: Any] {
                candidates.append(listing)
            } else {
                parsed.problem = Problem(code: .bridgeMessageInvalid, message: "LISTING_CLICK listing is not an object")
            }
        }
        if let url = object["url"] as? String {
            candidates.append(["id": "", "status": "active", "title": "", "url": url])
        }
        for candidate in candidates {
            do {
                let data = try JSONSerialization.data(withJSONObject: candidate)
                parsed.message = .listingClick(try JSONDecoder().decode(SellwildListing.self, from: data))
                return parsed
            } catch {
                parsed.problem = Problem(code: .bridgeMessageInvalid, message: "LISTING_CLICK listing could not be decoded", error: error)
            }
        }
        if candidates.isEmpty && parsed.problem == nil {
            parsed.problem = Problem(code: .bridgeMessageInvalid, message: "LISTING_CLICK has no listing or url")
        }
        return parsed
    }
}
