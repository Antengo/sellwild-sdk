// Pure builders for the HTML the deprecated WebView surfaces load
// (SellwildWidget and SellwildBanner in sellwild_widget.dart). No feature
// work here: the output is what those widgets always loaded, except the
// A9 fixes marked below, the page's send() catch (a deliberate in-page
// swallow, see buildWidgetHtml), and the banner scripts' failure reports
// (scriptError, slotError).

import 'dart:convert';

import 'sellwild_config.dart';

/// The base URL both WebViews load their HTML with.
const String widgetPageBaseUrl = 'https://widget.sellwild.com';

/// The generic widget bundle. It reads all config from element attributes
/// and loads its own Prebid build, so no separate prebid `<script>` is
/// injected (that double-loads and breaks header bidding).
const String widgetScriptUrl = 'https://widget.sellwild.com/partner.js';

/// Default GPT host when [SellwildConfig.gptProxyUrl] is not set.
const String defaultGptBase = 'https://securepubads.g.doubleclick.net';

/// Builds a Prebid.js pre-configuration script block.
/// Must be injected into the HTML <head> before prebid.js loads.
///
/// Addresses two critical WebView issues:
///  1. ortb2.app — declares in-app inventory so DSPs bid on app traffic,
///     not web (ortb2.site) traffic. Required for app-ads.txt compliance.
///  2. userSync — disables iframe cookie syncs which always fail in WebViews
///     (no third-party cookies), avoiding wasted network requests.
String buildPrebidPreConfigScript(SellwildConfig c) {
  final ortb2App = <String, dynamic>{
    'publisher': {'id': c.partnerCode},
    if (c.appBundleId != null) 'bundle': c.appBundleId,
    if (c.appStoreUrl != null) 'storeurl': c.appStoreUrl,
  };
  final server = c.prebidServer;
  final config = <String, dynamic>{
    'ortb2': {'app': ortb2App},
    'userSync': {
      'filterSettings': {
        'iframe': {'bidders': '*', 'filter': 'exclude'},
      },
      'syncDelay': 5000,
    },
    if (server != null)
      's2sConfig': {
        'accountId': server.accountId,
        'bidders': server.bidders,
        'timeout': server.timeout,
        'adapter': 'prebidServer',
        'endpoint': {
          'p1Consent': server.endpoint,
          'noP1Consent': server.endpoint,
        },
        if (server.syncEndpoint != null)
          'syncEndpoint': {
            'p1Consent': server.syncEndpoint,
            'noP1Consent': server.syncEndpoint,
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

/// [value] safe inside a double-quoted HTML attribute. The browser decodes
/// `&quot;` back, so the widget reads the original text.
String escapeAttribute(String value) => value.replaceAll('"', '&quot;');

/// The config as `<sellwild-widget>` element attributes, one per line.
///
/// The widget reads config via withCustomizationsFromElement() — any case
/// accepted. Complex objects (bidder configs) are JSON-encoded in attributes.
String buildWidgetAttributes(SellwildConfig c) {
  final parts = <String>[];

  // A9 fix: typed values are escaped like passthrough values. Before, a '"'
  // (LINK_TEXT is HTML) ended the attribute and spilled into the markup.
  void add(String name, String? value) {
    if (value != null && value.isNotEmpty) {
      parts.add('$name="${escapeAttribute(value)}"');
    }
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
  add('boltive-client-id',
      c.boltiveClientId.isNotEmpty ? c.boltiveClientId : null);
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

  // Passthrough: forward every key from the raw remote-config JSON to the
  // widget. The widget's attribute parser is case-insensitive and accepts
  // arbitrary keys, so unmapped CDN entries (new bidders, forward-compatible
  // settings) flow through without an SDK release.
  final raw = c.remoteJson;
  if (raw != null) {
    final emitted = parts.map((p) => p.split('=').first).toSet();
    raw.forEach((key, value) {
      final attr = key.toLowerCase().replaceAll('_', '-');
      if (emitted.contains(attr)) return;
      // A9 fix: JSON null is absent, as on iOS. Before, it reached the
      // widget as the text "null" (a "null" script URL for PREBID_SRC).
      if (value == null) return;
      final str =
          value is Map || value is List ? jsonEncode(value) : value.toString();
      parts.add('$attr="${escapeAttribute(str)}"');
      emitted.add(attr);
    });
  }

  return parts.join('\n    ');
}

/// The page SellwildWidget loads: the Prebid pre-config, the
/// `<sellwild-widget>` element, the bridge script and partner.js.
///
/// Set widgetJsUrl in config to use a publisher-specific pre-compiled
/// bundle; by default the generic bundle reads all config from element
/// attributes.
String buildWidgetHtml(SellwildConfig config) {
  final attrs = buildWidgetAttributes(config);
  final prebidPreConfig = buildPrebidPreConfigScript(config);

  // send()'s catch is a deliberate in-page swallow. With the bridge gone,
  // nothing on the page can carry a report to the SDK, and no caller reads
  // the false it returns. The phase-1 point is excluded as 'in-page' in
  // contracts/failure-codes.sources.json.
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
          return true;
        } catch(e) {
          return false;
        }
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

  <script async src="$widgetScriptUrl"></script>
</body>
</html>''';
}

/// Which ad script a SellwildBanner page runs.
enum BannerAdScript {
  /// GPT with the GAM tag (a tag is set and GPT is not disabled).
  gpt,

  /// The bidstream zone script (no usable GAM tag, a zone id is set).
  zone,

  /// Neither: the slot stays blank (ad.banner_config.missing).
  none,
}

/// Whether [config] has a GAM ad unit path. A9 fix: '' is no tag, as on
/// iOS, Android and core. Before, it built defineSlot(''), a blank slot.
bool hasGamTag(SellwildConfig config) => config.gamTag?.isNotEmpty ?? false;

/// The ad script for a banner with [config] and [zoneId]. GAM wins.
BannerAdScript selectBannerAdScript(SellwildConfig config, String? zoneId) {
  if (hasGamTag(config) && !config.disableGpt) return BannerAdScript.gpt;
  if (zoneId != null) return BannerAdScript.zone;
  return BannerAdScript.none;
}

/// Why a banner has no ad script, or null when it has one.
String? missingBannerConfigReason(SellwildConfig config, String? zoneId) {
  if (selectBannerAdScript(config, zoneId) != BannerAdScript.none) return null;
  return hasGamTag(config)
      ? 'GPT is disabled and there is no zone id'
      : 'no GAM tag and no zone id';
}

/// The page SellwildBanner loads for [size].
String buildBannerHtml(
    SellwildConfig config, SellwildAdSize size, String? zoneId) {
  final w = size.width;
  final h = size.height;
  final gptSrc = '${config.gptProxyUrl ?? defaultGptBase}/tag/js/gpt.js';

  final adScript = switch (selectBannerAdScript(config, zoneId)) {
    BannerAdScript.gpt => gptScript(config.gamTag!, gptSrc, w, h),
    BannerAdScript.zone => zoneScript(zoneId!, w, h),
    BannerAdScript.none => '// No ad configuration',
  };

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

/// [value] safe inside a single-quoted JavaScript string in an inline
/// `<script>`: backslash, quote and line terminators are escaped, and `<` is
/// written as `\x3C` so the text cannot close the script block. Plain tags,
/// zone ids and URLs come out unchanged.
String escapeJsString(String value) {
  final out = StringBuffer();
  for (final unit in value.codeUnits) {
    switch (unit) {
      case 0x5C: // \
        out.write(r'\\');
      case 0x27: // '
        out.write(r"\'");
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x2028:
        out.write(r'\u2028');
      case 0x2029:
        out.write(r'\u2029');
      case 0x3C: // <
        out.write(r'\x3C');
      default:
        out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// GPT slot script for [gamTag] at [w]x[h], loading gpt.js from [gptSrc].
///
/// Failure reporting only (the slot renders as before): a gpt.js that fails
/// to load posts `scriptError` with its URL (ad.banner_script.network), and
/// a slot GPT cannot define posts `slotError` (ad.gpt_slot.invalid), with
/// the error text when defineSlot threw. GPT runs queued commands inside its
/// own catch, so before, a throw there was silent too.
///
/// A9 fix: [gamTag] and [gptSrc] are escaped with [escapeJsString]. Before,
/// a quote in either ended the string, so the whole script failed to parse
/// and nothing (not even slotError) could report it.
String gptScript(String gamTag, String gptSrc, int w, int h) => '''
    window.googletag = window.googletag || { cmd: [] };
    var s = document.createElement('script');
    s.src = '${escapeJsString(gptSrc)}'; s.async = true;
    s.onerror = function() { notify('scriptError', { src: s.src }); };
    document.head.appendChild(s);
    googletag.cmd.push(function() {
      var slot;
      try {
        slot = googletag.defineSlot('${escapeJsString(gamTag)}', [$w, $h], 'ad');
      } catch (e) {
        notify('slotError', { message: String((e && e.message) || e) });
        return;
      }
      if (slot) {
        slot.addService(googletag.pubads());
        googletag.pubads().enableSingleRequest();
        googletag.pubads().addEventListener('slotRenderEnded', function(e) {
          if (!e.isEmpty) notify('impression');
        });
        googletag.enableServices();
        googletag.display('ad');
      } else {
        notify('slotError');
      }
    });
  ''';

/// Bidstream zone script for [zoneId] at [w]x[h]. A zone script that fails
/// to load posts `scriptError` with its URL (ad.banner_script.network).
/// [zoneId] is escaped with [escapeJsString] (A9 fix, as in [gptScript]).
String zoneScript(String zoneId, int w, int h) => '''
    var s = document.createElement('script');
    s.src = 'https://bidstream.sellwild.com/ads?zone=${escapeJsString(zoneId)}&w=$w&h=$h';
    s.async = true;
    s.onload = function() { notify('impression'); };
    s.onerror = function() { notify('scriptError', { src: s.src }); };
    document.getElementById('ad').appendChild(s);
  ''';
