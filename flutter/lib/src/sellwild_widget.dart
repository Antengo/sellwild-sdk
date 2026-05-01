import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'sellwild_config.dart';
import 'sellwild_models.dart';

/// Builds a Prebid.js pre-configuration script block.
/// Must be injected into the HTML <head> before prebid.js loads.
///
/// Addresses two critical WebView issues:
///  1. ortb2.app — declares in-app inventory so DSPs bid on app traffic,
///     not web (ortb2.site) traffic. Required for app-ads.txt compliance.
///  2. userSync — disables iframe cookie syncs which always fail in WebViews
///     (no third-party cookies), avoiding wasted network requests.
String _buildPrebidPreConfigScript(SellwildConfig c) {
  final ortb2App = <String, dynamic>{
    'publisher': {'id': c.partnerCode},
    if (c.appBundleId != null) 'bundle': c.appBundleId,
    if (c.appStoreUrl != null) 'storeurl': c.appStoreUrl,
  };
  final config = <String, dynamic>{
    'ortb2': {'app': ortb2App},
    'userSync': {
      'filterSettings': {
        'iframe': {'bidders': '*', 'filter': 'exclude'},
      },
      'syncDelay': 5000,
    },
    if (c.prebidServer != null)
      's2sConfig': {
        'accountId': c.prebidServer!.accountId,
        'bidders': c.prebidServer!.bidders,
        'timeout': c.prebidServer!.timeout,
        'adapter': 'prebidServer',
        'endpoint': {
          'p1Consent': c.prebidServer!.endpoint,
          'noP1Consent': c.prebidServer!.endpoint,
        },
        if (c.prebidServer!.syncEndpoint != null)
          'syncEndpoint': {
            'p1Consent': c.prebidServer!.syncEndpoint,
            'noP1Consent': c.prebidServer!.syncEndpoint,
          },
      },
    if (c.debug) 'debug': true,
  };
  final configJson = jsonEncode(config);
  return '''
  <script>
    window.pbjs = window.pbjs || {};
    window.pbjs.que = window.pbjs.que || [];
    window.pbjs.que.push(function() {
      window.pbjs.setConfig($configJson);
    });
  </script>''';
}

/// Full Sellwild marketplace widget rendered in a WebView.
///
/// Example:
/// ```dart
/// SellwildWidget(
///   config: SellwildConfig(
///     partnerCode: 'mysite',
///     listingsUrl: 'https://api.sellwild.com/widget/listings?partner=mysite',
///   ),
///   onListingTap: (listing) {
///     // Navigate to listing detail
///   },
/// )
/// ```
class SellwildWidget extends StatefulWidget {
  final SellwildConfig config;
  final void Function(SellwildListing listing)? onListingTap;
  final void Function(String zoneId)? onAdImpression;
  final void Function(Object error)? onError;
  final void Function()? onLoad;

  const SellwildWidget({
    super.key,
    required this.config,
    this.onListingTap,
    this.onAdImpression,
    this.onError,
    this.onLoad,
  });

  @override
  State<SellwildWidget> createState() => _SellwildWidgetState();
}

class _SellwildWidgetState extends State<SellwildWidget> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'SellwildWidgetBridge',
        onMessageReceived: _handleMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          // Widget sends WIDGET_LOADED via JS channel
        },
        onWebResourceError: (error) {
          widget.onError?.call(error);
        },
      ))
      ..loadHtmlString(_buildHtml(), baseUrl: 'https://widget.sellwild.com');
  }

  void _handleMessage(JavaScriptMessage message) {
    try {
      final json = jsonDecode(message.message) as Map<String, dynamic>;
      final type = json['type'] as String?;
      switch (type) {
        case 'WIDGET_LOADED':
          setState(() => _loading = false);
          widget.onLoad?.call();
          break;
        case 'LISTING_CLICK':
          // The web widget sends window.open(url) on listing tap.
          // A full listing object is not available at the WebView boundary.
          final listingJson = json['listing'] as Map<String, dynamic>?;
          final url = json['url'] as String?;
          if (listingJson != null) {
            widget.onListingTap?.call(SellwildListing.fromJson(listingJson));
          } else if (url != null) {
            // URL-only path: construct a minimal stub so callers can navigate.
            widget.onListingTap?.call(SellwildListing.fromJson({
              'id': '', 'status': 'active', 'title': '', 'url': url,
            }));
          }
          break;
        case 'AD_IMPRESSION':
          final zoneId = json['zoneId'] as String? ?? '';
          widget.onAdImpression?.call(zoneId);
          break;
        case 'ERROR':
          final msg = json['message'] as String? ?? 'Unknown error';
          widget.onError?.call(Exception(msg));
          break;
      }
    } catch (_) {}
  }

  // Serialize config as HTML element attributes.
  // The widget reads config via withCustomizationsFromElement() — any case accepted.
  // Complex objects (bidder configs) are JSON-encoded in attributes.
  String _configAttributes() {
    final c = widget.config;
    final parts = <String>[];

    void add(String name, String? value) {
      if (value != null && value.isNotEmpty) parts.add('$name="$value"');
    }
    void addBool(String name, bool value) {
      if (value) parts.add('$name="true"');
    }
    void addNum(String name, int value) {
      if (value != 0) parts.add('$name="$value"');
    }
    add('partner-code', c.partnerCode);
    add('listings', c.effectiveListingsUrl);
    // Disable remote customization fetch — see RN htmlBuilder.ts for details.
    parts.add('customize="false"');
    // Ad system selection — REQUIRED. See RN htmlBuilder.ts for details.
    add('ad-type', c.adType ?? 'PrebidOnly');
    add('gam-tag', c.gamTag);
    add('gpt-proxy-url', c.gptProxyUrl);
    addBool('disable-gpt', c.disableGpt);
    add('banner-zid', c.bannerZid);
    add('bottom-banner-zid', c.bottomBannerZid);
    add('mobile-banner-zid', c.mobileBannerZid);
    // Filter empties — widget parser does not strip empty strings post-split.
    final mobileZids = c.mobileZids.where((z) => z.isNotEmpty).toList();
    if (mobileZids.isNotEmpty) add('mobile-zid', mobileZids.join(','));
    addBool('hide-banner-top', c.hideBannerTop);
    addBool('hide-banner-bottom', c.hideBannerBottom);
    addNum('ad-refresh-max', c.adRefreshMax);
    addNum('ad-refresh-max-mobile', c.adRefreshMaxMobile);
    if (c.adRefreshInterval.inMilliseconds > 0) {
      parts.add('ad-refresh-interval="${c.adRefreshInterval.inMilliseconds}"');
    }
    addBool('boltive', c.boltive);
    add('boltive-client-id', c.boltiveClientId.isNotEmpty ? c.boltiveClientId : null);
    addBool('lotame', c.lotame);
    add('title', c.title);
    add('link-text', c.linkText);
    addNum('font-size', c.fontSize);
    add('font-color', c.fontColor);
    add('price-color', c.priceColor);
    add('price-font-color', c.priceFontColor);
    if (c.colors.isNotEmpty) add('colors', c.colors.join(','));
    addBool('debug', c.debug);

    // Mobile ad controls
    addBool('enable-interstitial', c.enableInterstitial);
    addBool('enable-fullscreen-video', c.enableFullscreenVideo);
    addNum('interstitials-per-session', c.interstitialsPerSession);
    addNum('video-takeovers-per-session', c.videoTakeoversPerSession);

    return parts.join('\n    ');
  }

  String _buildHtml() {
    // Default: generic bundle that reads all config from element attributes.
    // Set widgetJsUrl in config to use a publisher-specific pre-compiled bundle.
    // partner.js loads its own Prebid build internally — do not inject a
    // separate prebid <script> tag (causes double-load and breaks header bidding).
    const widgetSrc = 'https://widget.sellwild.com/partner.js';
    final attrs = _configAttributes();

    final prebidPreConfig = _buildPrebidPreConfigScript(widget.config);

    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { width: 100%; background: transparent; overflow-x: hidden; }
  </style>
  $prebidPreConfig
</head>
<body>
  <sellwild-widget
    $attrs
  ></sellwild-widget>

  <script>
    (function() {
      function send(type, payload) {
        try {
          SellwildWidgetBridge.postMessage(JSON.stringify(Object.assign({ type: type }, payload || {})));
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

  <script async src="$widgetSrc"></script>
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

/// Sellwild banner ad widget.
///
/// Example:
/// ```dart
/// SellwildBanner(
///   config: config,
///   adSize: SellwildAdSize.banner320x50,
///   zoneId: '12345',
///   onImpression: () => print('Ad shown'),
/// )
/// ```
class SellwildBanner extends StatefulWidget {
  final SellwildConfig config;
  final SellwildAdSize adSize;
  final String? zoneId;
  final void Function()? onImpression;
  final void Function()? onClick;
  final void Function(Object error)? onError;

  const SellwildBanner({
    super.key,
    required this.config,
    required this.adSize,
    this.zoneId,
    this.onImpression,
    this.onClick,
    this.onError,
  });

  @override
  State<SellwildBanner> createState() => _SellwildBannerState();
}

class _SellwildBannerState extends State<SellwildBanner> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'SellwildAdBridge',
        onMessageReceived: (msg) {
          try {
            final json = jsonDecode(msg.message) as Map<String, dynamic>;
            switch (json['type']) {
              case 'impression':
                widget.onImpression?.call();
                break;
              case 'click':
                widget.onClick?.call();
                break;
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (error) => widget.onError?.call(error),
      ))
      ..loadHtmlString(_buildHtml(), baseUrl: 'https://widget.sellwild.com');
  }

  String _buildHtml() {
    final w = widget.adSize.width;
    final h = widget.adSize.height;
    final gptBase = widget.config.gptProxyUrl ?? 'https://securepubads.g.doubleclick.net';
    final gptSrc = '$gptBase/tag/js/gpt.js';

    final adScript = () {
      if (widget.config.gamTag != null && !widget.config.disableGpt) {
        return _gptScript(widget.config.gamTag!, gptSrc, w, h);
      } else if (widget.zoneId != null) {
        return _zoneScript(widget.zoneId!, w, h);
      }
      return '// No ad configuration';
    }();

    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { width: ${w}px; height: ${h}px; overflow: hidden; background: transparent; }
    #ad { width: ${w}px; height: ${h}px; }
  </style>
</head>
<body>
  <div id="ad"></div>
  <script>
    function notify(type, data) {
      SellwildAdBridge.postMessage(JSON.stringify(Object.assign({ type: type }, data || {})));
    }
    $adScript
  </script>
</body>
</html>''';
  }

  String _gptScript(String gamTag, String gptSrc, int w, int h) => '''
    window.googletag = window.googletag || { cmd: [] };
    var s = document.createElement('script');
    s.src = '$gptSrc'; s.async = true;
    document.head.appendChild(s);
    googletag.cmd.push(function() {
      var slot = googletag.defineSlot('$gamTag', [$w, $h], 'ad');
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
  ''';

  String _zoneScript(String zoneId, int w, int h) => '''
    var s = document.createElement('script');
    s.src = 'https://bidstream.sellwild.com/ads?zone=$zoneId&w=$w&h=$h';
    s.async = true;
    s.onload = function() { notify('impression'); };
    document.getElementById('ad').appendChild(s);
  ''';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.adSize.width.toDouble(),
      height: widget.adSize.height.toDouble(),
      child: WebViewWidget(controller: _controller),
    );
  }
}
