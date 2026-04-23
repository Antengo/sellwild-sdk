import UIKit
import WebKit

// MARK: - SellwildAdView

/// A UIView subclass that renders a Sellwild ad unit via WKWebView.
/// Supports banner ads (320x50, 300x250, 728x90) using GPT or zone-based delivery.
@objc
public final class SellwildAdView: UIView {

    // MARK: Public

    public var config: SellwildConfig
    public var adSize: AdSize
    public var zoneId: String?
    public weak var delegate: SellwildAdViewDelegate?

    // MARK: Private

    private lazy var webView: WKWebView = {
        let wvConfig = WKWebViewConfiguration()
        // JavaScript is required for GPT / Prebid ad delivery.
        if #available(iOS 14.0, *) {
            wvConfig.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            wvConfig.preferences.javaScriptEnabled = true
        }
        wvConfig.allowsInlineMediaPlayback = true
        wvConfig.mediaTypesRequiringUserActionForPlayback = []

        // Message handler for JS -> native bridge
        let contentController = WKUserContentController()
        contentController.add(self, name: "sellwildBridge")
        wvConfig.userContentController = contentController

        let wv = WKWebView(frame: .zero, configuration: wvConfig)
        wv.scrollView.isScrollEnabled = false
        wv.backgroundColor = .clear
        wv.isOpaque = false
        wv.navigationDelegate = self
        return wv
    }()

    private var refreshTimer: Timer?
    private var refreshCount = 0

    // MARK: Init

    public init(config: SellwildConfig, adSize: AdSize, zoneId: String? = nil) {
        self.config = config
        self.adSize = adSize
        self.zoneId = zoneId
        super.init(frame: CGRect(origin: .zero, size: adSize.cgSize))
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(config:adSize:zoneId:)")
    }

    deinit {
        refreshTimer?.invalidate()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "sellwildBridge")
    }

    // MARK: Public Methods

    /// Load the ad. Call after adding to the view hierarchy.
    public func load() {
        let html = buildAdHTML()
        let baseURL = URL(string: "https://widget.sellwild.com")
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Stop ad refresh.
    public func pause() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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

    private func scheduleRefresh() {
        guard config.adRefreshMaxMobile > 0 else { return }
        guard refreshCount < config.adRefreshMaxMobile else { return }
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: config.adRefreshInterval,
            repeats: false
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        refreshCount += 1
        load()
    }

    private func buildAdHTML() -> String {
        let size = adSize.cgSize
        let w = Int(size.width)
        let h = Int(size.height)
        let gptSrc = config.gptProxyUrl.flatMap { URL(string: $0 + "/tag/js/gpt.js") }
            ?? URL(string: "https://securepubads.g.doubleclick.net/tag/js/gpt.js")!

        let adScript: String
        if let gamTag = config.gamTag, !gamTag.isEmpty, !config.disableGpt {
            adScript = buildGptScript(gamTag: gamTag, gptSrc: gptSrc.absoluteString, width: w, height: h)
        } else if let zid = zoneId, !zid.isEmpty {
            adScript = buildZoneScript(zoneId: zid, width: w, height: h)
        } else {
            adScript = "// No ad configuration"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            html, body { width: \(w)px; height: \(h)px; overflow: hidden; background: transparent; }
            #ad { width: \(w)px; height: \(h)px; }
          </style>
        </head>
        <body>
          <div id="ad"></div>
          <script>
            function notify(type, data) {
              window.webkit.messageHandlers.sellwildBridge.postMessage(
                JSON.stringify(Object.assign({ type: type }, data || {}))
              );
            }
            \(adScript)
          </script>
        </body>
        </html>
        """
    }

    private func buildGptScript(gamTag: String, gptSrc: String, width: Int, height: Int) -> String {
        return """
        window.googletag = window.googletag || { cmd: [] };
        var s = document.createElement('script');
        s.src = '\(gptSrc)';
        s.async = true;
        document.head.appendChild(s);
        googletag.cmd.push(function() {
          var slot = googletag.defineSlot('\(gamTag)', [\(width), \(height)], 'ad');
          if (slot) {
            slot.addService(googletag.pubads());
            googletag.pubads().enableSingleRequest();
            googletag.pubads().addEventListener('slotRenderEnded', function(e) {
              if (!e.isEmpty) notify('impression');
            });
            googletag.enableServices();
            googletag.display('ad');
          }
        });
        """
    }

    private func buildZoneScript(zoneId: String, width: Int, height: Int) -> String {
        return """
        var s = document.createElement('script');
        s.src = 'https://bidstream.sellwild.com/ads?zone=\(zoneId)&w=\(width)&h=\(height)';
        s.async = true;
        s.onload = function() { notify('impression'); };
        document.getElementById('ad').appendChild(s);
        """
    }
}

// MARK: - WKScriptMessageHandler

extension SellwildAdView: WKScriptMessageHandler {
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
        case "impression":
            delegate?.sellwildAdView?(self, didReceiveImpressionForZoneId: zoneId ?? "")
            scheduleRefresh()
        case "click":
            delegate?.sellwildAdViewDidRecordClick?(self)
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension SellwildAdView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        delegate?.sellwildAdViewDidLoad?(self)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        delegate?.sellwildAdView?(self, didFailWithError: error)
    }
}

// MARK: - Delegate Protocol

@objc
public protocol SellwildAdViewDelegate: AnyObject {
    @objc optional func sellwildAdViewDidLoad(_ adView: SellwildAdView)
    @objc optional func sellwildAdView(_ adView: SellwildAdView, didReceiveImpressionForZoneId zoneId: String)
    @objc optional func sellwildAdViewDidRecordClick(_ adView: SellwildAdView)
    @objc optional func sellwildAdView(_ adView: SellwildAdView, didFailWithError error: Error)
}
