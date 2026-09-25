// The pure HTML builders behind the deprecated WebView surfaces
// (lib/src/widget_html.dart): attribute order and rules, the Prebid
// pre-config, the widget page and the banner page.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/widget_html.dart';

import 'factories/shape_factories.dart';
import 'support/failure_capture.dart';

/// The attributes of an attribute block, in order, decoded as a browser
/// would. Fails on markup that is not `name="value"`.
List<(String, String)> parseAttributes(String block) {
  final out = <(String, String)>[];
  final rest = block.replaceAllMapped(RegExp(r'([^\s=]+)="([^"]*)"'), (m) {
    out.add((m[1]!, m[2]!.replaceAll('&quot;', '"')));
    return '';
  });
  expect(rest.trim(), isEmpty, reason: 'stray markup: $rest');
  return out;
}

Map<String, String> attributeMap(SellwildConfig config) =>
    Map.fromEntries(parseAttributes(buildWidgetAttributes(config))
        .map((a) => MapEntry(a.$1, a.$2)));

/// The object passed to pbjs.setConfig in a pre-config script.
Map<String, dynamic> setConfigOf(String script) {
  final start = script.indexOf('setConfig(') + 'setConfig('.length;
  final end = script.indexOf(');', start);
  return jsonDecode(script.substring(start, end)) as Map<String, dynamic>;
}

void main() {
  const minimal = SellwildConfig(partnerCode: 'weatherbug');
  final configs = AppConfigFactory();

  SellwildConfig applied(Map<String, dynamic> raw) {
    captureFailures();
    return SellwildSDK.apply(raw, const SellwildConfig(partnerCode: 'x'),
        isAndroid: false);
  }

  group('buildPrebidPreConfigScript', () {
    test('declares in-app inventory and turns iframe syncs off', () {
      final script = buildPrebidPreConfigScript(minimal);

      expect(script, contains('window.pbjs.que.push(function() {'));
      expect(setConfigOf(script), {
        'ortb2': {
          'app': {
            'publisher': {'id': 'weatherbug'}
          }
        },
        'userSync': {
          'filterSettings': {
            'iframe': {'bidders': '*', 'filter': 'exclude'}
          },
          'syncDelay': 5000,
        },
      });
    });

    test('adds app identity, Prebid Server and debug when set', () {
      final config = SellwildConfig(
        partnerCode: 'p',
        appBundleId: 'com.example',
        appStoreUrl: 'https://apps.apple.com/app/id1',
        debug: true,
        prebidServer: PrebidServerConfig(
          accountId: 'acct',
          endpoint: 'https://pbs.example.com/openrtb2/auction',
          bidders: ['ix', 'rubicon'].toList(),
          timeout: 900,
          syncEndpoint: 'https://pbs.example.com/cookie_sync',
        ),
      );

      final set = setConfigOf(buildPrebidPreConfigScript(config));

      expect((set['ortb2'] as Map)['app'], {
        'publisher': {'id': 'p'},
        'bundle': 'com.example',
        'storeurl': 'https://apps.apple.com/app/id1',
      });
      expect(set['s2sConfig'], {
        'accountId': 'acct',
        'bidders': ['ix', 'rubicon'],
        'timeout': 900,
        'adapter': 'prebidServer',
        'endpoint': {
          'p1Consent': 'https://pbs.example.com/openrtb2/auction',
          'noP1Consent': 'https://pbs.example.com/openrtb2/auction',
        },
        'syncEndpoint': {
          'p1Consent': 'https://pbs.example.com/cookie_sync',
          'noP1Consent': 'https://pbs.example.com/cookie_sync',
        },
      });
      expect(set['debug'], isTrue);
    });

    test('Prebid Server without a sync endpoint sends none', () {
      final config = SellwildConfig(
        partnerCode: 'p',
        prebidServer: PrebidServerConfig(
            accountId: 'a', endpoint: 'https://pbs', bidders: List.empty()),
      );

      final s2s = setConfigOf(buildPrebidPreConfigScript(config))['s2sConfig']
          as Map<String, dynamic>;

      expect(s2s.containsKey('syncEndpoint'), isFalse);
      expect(s2s['timeout'], 1500);
    });
  });

  group('buildWidgetAttributes', () {
    test('defaults: the required attributes, in order', () {
      final attrs = parseAttributes(buildWidgetAttributes(minimal));

      expect(attrs, [
        ('partner-code', 'weatherbug'),
        ('listings', SellwildConfig.defaultListingsUrl),
        ('customize', 'false'),
        ('ad-type', 'PrebidOnly'),
        ('ad-refresh-interval', '30000'),
        ('link-text', 'View all'),
        ('font-size', '13'),
        ('font-color', '#ffffff'),
        ('price-color', '#333333'),
        ('price-font-color', '#ffffff'),
        ('colors', '#333333'),
        ('interstitials-per-session', '1'),
      ]);
      expect(buildWidgetAttributes(minimal), contains('"\n    '));
    });

    test('every typed field when set', () {
      const config = SellwildConfig(
        partnerCode: 'p',
        listingsUrl: 'https://cache.sellwild.com/x',
        title: 'Deals',
        adType: 'GAM',
        gamTag: '/1/x',
        gptProxyUrl: 'https://gpt.example.com',
        disableGpt: true,
        bannerZid: '1',
        bottomBannerZid: '2',
        mobileBannerZid: '3',
        mobileZids: ['a', '', 'b'],
        hideBannerTop: true,
        hideBannerBottom: true,
        adRefreshMax: 4,
        adRefreshMaxMobile: 2,
        adRefreshInterval: Duration(seconds: 45),
        boltive: true,
        boltiveClientId: 'bc',
        lotame: true,
        colors: ['#1', '#2'],
        debug: true,
        enableInterstitial: true,
        enableFullscreenVideo: true,
        videoTakeoversPerSession: 3,
      );

      final attrs = attributeMap(config);

      expect(attrs, containsPair('listings', 'https://cache.sellwild.com/x'));
      expect(attrs, containsPair('ad-type', 'GAM'));
      expect(attrs, containsPair('gam-tag', '/1/x'));
      expect(attrs, containsPair('gpt-proxy-url', 'https://gpt.example.com'));
      expect(attrs, containsPair('disable-gpt', 'true'));
      expect(attrs, containsPair('banner-zid', '1'));
      expect(attrs, containsPair('bottom-banner-zid', '2'));
      expect(attrs, containsPair('mobile-banner-zid', '3'));
      // Empty zone ids are dropped: the widget parser keeps them.
      expect(attrs, containsPair('mobile-zid', 'a,b'));
      expect(attrs, containsPair('hide-banner-top', 'true'));
      expect(attrs, containsPair('hide-banner-bottom', 'true'));
      expect(attrs, containsPair('ad-refresh-max', '4'));
      expect(attrs, containsPair('ad-refresh-max-mobile', '2'));
      expect(attrs, containsPair('ad-refresh-interval', '45000'));
      expect(attrs, containsPair('boltive', 'true'));
      expect(attrs, containsPair('boltive-client-id', 'bc'));
      expect(attrs, containsPair('lotame', 'true'));
      expect(attrs, containsPair('title', 'Deals'));
      expect(attrs, containsPair('colors', '#1,#2'));
      expect(attrs, containsPair('debug', 'true'));
      expect(attrs, containsPair('enable-interstitial', 'true'));
      expect(attrs, containsPair('enable-fullscreen-video', 'true'));
      expect(attrs, containsPair('video-takeovers-per-session', '3'));
    });

    test('empty, false and zero values are left out', () {
      const config = SellwildConfig(
        partnerCode: 'p',
        adType: '',
        linkText: '',
        mobileZids: ['', ''],
        colors: [],
        fontSize: 0,
        interstitialsPerSession: 0,
        adRefreshInterval: Duration.zero,
      );

      expect(parseAttributes(buildWidgetAttributes(config)).map((a) => a.$1), [
        'partner-code',
        'listings',
        'customize',
        'font-color',
        'price-color',
        'price-font-color',
      ]);
    });

    test('a negative refresh interval is left out', () {
      const config = SellwildConfig(
          partnerCode: 'p', adRefreshInterval: Duration(milliseconds: -1));

      expect(attributeMap(config).containsKey('ad-refresh-interval'), isFalse);
    });

    test('passthrough: every other remote key, kebab-cased, typed first', () {
      final raw = configs.webPassthrough();

      final attrs = parseAttributes(buildWidgetAttributes(applied(raw)));
      final names = attrs.map((a) => a.$1).toList();
      final byName = Map.fromEntries(attrs.map((a) => MapEntry(a.$1, a.$2)));

      // Each name once; the typed attribute wins over its remote key.
      expect(names.toSet(), hasLength(names.length));
      expect(names.indexOf('title'), lessThan(names.indexOf('layout')));
      expect(byName['layout'], raw['LAYOUT']);
      expect(byName['card-width'], raw['CARD_WIDTH']);
      expect(byName['consent-management'], raw['CONSENT_MANAGEMENT']);
      expect(byName['membership-type'], raw['MEMBERSHIP_TYPE']);
      // Objects and arrays are JSON; other scalars are their text.
      expect(jsonDecode(byName['ad-geo-block']!), raw['AD_GEO_BLOCK']);
      expect(jsonDecode(byName['mobile-zid-ios']!), raw['MOBILE_ZID_IOS']);
      expect(byName['overlay-title'], '${raw['OVERLAY_TITLE']}');
      expect(byName['margin-bottom'], '${raw['MARGIN_BOTTOM']}');
      expect(byName['apstag'], '');
    });

    test('passthrough: the first of two keys with the same name wins', () {
      final config = applied(configs.attributeNameCollision());

      expect(attributeMap(config)['weatherbug-only'], 'first');
    });

    test('A9: typed values are escaped like passthrough values', () {
      const config = SellwildConfig(
          partnerCode: 'p', title: 'Say "hi"', linkText: '<a href="x">y</a>');

      final text = buildWidgetAttributes(config);

      expect(text, contains('title="Say &quot;hi&quot;"'));
      expect(attributeMap(config)['link-text'], '<a href="x">y</a>');
    });

    test('A9: JSON null passthrough values are left out', () {
      final attrs = attributeMap(applied(configs.prebidSrcNull()));

      expect(attrs.containsKey('prebid-src'), isFalse);
    });

    test('escapeAttribute only touches double quotes', () {
      expect(escapeAttribute('''a"b'c&d<e>'''), '''a&quot;b'c&d<e>''');
    });
  });

  group('buildWidgetHtml', () {
    test('the page: pre-config, element, bridge script, partner.js', () {
      final config = applied(configs.build());

      final html = buildWidgetHtml(config);

      final head = html.substring(0, html.indexOf('</head>'));
      expect(head, contains(buildPrebidPreConfigScript(config)));
      expect(
          html,
          contains('<sellwild-widget\n    '
              '${buildWidgetAttributes(config)}\n  ></sellwild-widget>'));
      expect(html, contains('<script async src="$widgetScriptUrl"></script>'));
      expect(html.indexOf('SellwildWidgetBridge.postMessage'),
          lessThan(html.indexOf(widgetScriptUrl)));
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, endsWith('</html>'));
    });

    test('the bridge script posts the messages the SDK decodes', () {
      final html = buildWidgetHtml(minimal);

      expect(
          html,
          contains('SellwildWidgetBridge.postMessage(JSON.stringify('
              'Object.assign({ type: type }, payload || {})));'));
      expect(html, contains("send('LISTING_CLICK', { url: url });"));
      expect(html, contains("send('WIDGET_LOADED');"));
      expect(
          html,
          contains(
              "send('ERROR', { message: e.message || 'Widget load error' });"));
      // send() reports whether the post worked; its catch is not empty.
      expect(
          html,
          contains('return true;\n        } catch(e) {\n'
              '          return false;\n        }'));
      expect(html, isNot(contains('catch(e) {}')));
    });
  });

  group('banner', () {
    const gam = SellwildConfig(partnerCode: 'p', gamTag: '/1/x');
    const gamOff =
        SellwildConfig(partnerCode: 'p', gamTag: '/1/x', disableGpt: true);
    const plain = SellwildConfig(partnerCode: 'p');

    test('selectBannerAdScript: GAM wins, then the zone, else none', () {
      expect(selectBannerAdScript(gam, '43'), BannerAdScript.gpt);
      expect(selectBannerAdScript(gam, null), BannerAdScript.gpt);
      expect(selectBannerAdScript(gamOff, '43'), BannerAdScript.zone);
      expect(selectBannerAdScript(plain, '43'), BannerAdScript.zone);
      expect(selectBannerAdScript(gamOff, null), BannerAdScript.none);
      expect(selectBannerAdScript(plain, null), BannerAdScript.none);
    });

    test('missingBannerConfigReason says why a slot is blank', () {
      expect(missingBannerConfigReason(gam, null), isNull);
      expect(missingBannerConfigReason(plain, '43'), isNull);
      expect(
          missingBannerConfigReason(plain, null), 'no GAM tag and no zone id');
      expect(missingBannerConfigReason(gamOff, null),
          'GPT is disabled and there is no zone id');
    });

    test("a GAM tag '' is no tag: zone script or a blank slot (A9 fix)", () {
      const gamEmpty = SellwildConfig(partnerCode: 'p', gamTag: '');

      // Before: GPT with defineSlot(''), which renders nothing and was not
      // reported. iOS, Android and core also treat '' as no tag.
      expect(selectBannerAdScript(gamEmpty, '43'), BannerAdScript.zone);
      expect(selectBannerAdScript(gamEmpty, null), BannerAdScript.none);
      expect(missingBannerConfigReason(gamEmpty, null),
          'no GAM tag and no zone id');
      expect(buildBannerHtml(gamEmpty, SellwildAdSize.mrec300x250, '43'),
          isNot(contains('defineSlot')));
    });

    test('GPT page at the ad size, gpt.js from the default host', () {
      final html = buildBannerHtml(gam, SellwildAdSize.mrec300x250, '43');

      expect(html, contains('html, body { width: 300px; height: 250px;'));
      expect(html, contains('#ad { width: 300px; height: 250px; }'));
      expect(
          html,
          contains(
              gptScript('/1/x', '$defaultGptBase/tag/js/gpt.js', 300, 250)));
      expect(html, isNot(contains('bidstream')));
    });

    test('GPT page through the proxy', () {
      const proxied = SellwildConfig(
          partnerCode: 'p',
          gamTag: '/1/x',
          gptProxyUrl: 'https://gpt.example.com');

      final html = buildBannerHtml(proxied, SellwildAdSize.banner320x50, null);

      expect(
          html, contains("s.src = 'https://gpt.example.com/tag/js/gpt.js';"));
    });

    test('zone page, and the blank page without either', () {
      final zone =
          buildBannerHtml(gamOff, SellwildAdSize.leaderboard728x90, '9');
      final none = buildBannerHtml(plain, SellwildAdSize.banner320x50, null);

      expect(zone, contains(zoneScript('9', 728, 90)));
      expect(zone, isNot(contains('googletag')));
      expect(none, contains('// No ad configuration'));
      expect(none, isNot(contains('document.createElement')));
    });

    test('the page posts impressions through notify', () {
      final html = buildBannerHtml(plain, SellwildAdSize.banner320x50, '43');

      expect(
          html,
          contains('SellwildAdBridge.postMessage(JSON.stringify('
              'Object.assign({ type: type }, data || {})));'));
      expect(zoneScript('43', 1, 2),
          contains("s.onload = function() { notify('impression'); };"));
      expect(gptScript('/t', 'src', 1, 2),
          contains("if (!e.isEmpty) notify('impression');"));
    });

    test('gptScript and zoneScript', () {
      final gpt = gptScript('/21/tag', 'https://g/gpt.js', 320, 50);
      final zone = zoneScript('43', 300, 250);

      expect(gpt, contains("s.src = 'https://g/gpt.js'; s.async = true;"));
      expect(gpt,
          contains("slot = googletag.defineSlot('/21/tag', [320, 50], 'ad');"));
      expect(gpt, contains("googletag.display('ad');"));
      expect(zone,
          contains("'https://bidstream.sellwild.com/ads?zone=43&w=300&h=250'"));
      expect(zone, contains("document.getElementById('ad').appendChild(s);"));
    });

    test('a GAM tag, gpt.js URL or zone id stays one JS string (A9 fix)', () {
      // Before: each was pasted between single quotes as is, so a quote
      // ended the string and the whole banner script failed to parse, with
      // nothing left to report it. A '</script>' ended the script block.
      const texts = [
        "/21/o'brien",
        r'/21/back\slash',
        '/21/x</script><script>alert(1)//',
        'line\nbreak\r',
        'sep\u2028\u2029',
      ];
      for (final text in texts) {
        final gpt = gptScript(text, 'https://g/gpt.js?t=$text', 320, 50);
        final zone = zoneScript(text, 300, 250);

        expect(jsStringAfter(gpt, 'googletag.defineSlot('),
            (text, ", [320, 50], 'ad');"),
            reason: text);
        expect(jsStringAfter(gpt, 's.src = '),
            ('https://g/gpt.js?t=$text', '; s.async = true;'),
            reason: text);
        expect(jsStringAfter(zone, 's.src = '),
            ('https://bidstream.sellwild.com/ads?zone=$text&w=300&h=250', ';'),
            reason: text);
        for (final script in [gpt, zone]) {
          expect(script, isNot(contains('</script')), reason: text);
          expect(script, isNot(contains('\u2028')), reason: text);
        }
      }
    });

    test('escapeJsString leaves plain text unchanged', () {
      for (final text in ['/21/tag', '43', 'https://g/gpt.js', '']) {
        expect(escapeJsString(text), text);
      }
      expect(escapeJsString("a'b"), r"a\'b");
      expect(escapeJsString(r'a\b'), r'a\\b');
      expect(escapeJsString('<'), r'\x3C');
      expect(escapeJsString('\n\r\u2028\u2029'), r'\n\r\u2028\u2029');
    });

    test('a script that fails to load posts scriptError with its URL', () {
      const onError =
          "s.onerror = function() { notify('scriptError', { src: s.src }); };";
      final gpt = gptScript('/21/tag', 'https://g/gpt.js', 320, 50);
      final zone = zoneScript('43', 300, 250);

      // Set before the script is added, so no failure can come first.
      for (final script in [gpt, zone]) {
        expect(script, contains(onError));
        expect(script.indexOf(onError),
            lessThan(script.indexOf('appendChild(s)')));
      }
      // The zone script still posts its impression on load, as before.
      expect(
          zone, contains("s.onload = function() { notify('impression'); };"));
    });

    test('a slot GPT cannot define posts slotError', () {
      final gpt = gptScript('/21/tag', 'https://g/gpt.js', 320, 50);

      // defineSlot throwing: the error text, and nothing else runs.
      expect(
          gpt,
          contains('      } catch (e) {\n'
              "        notify('slotError', { message: String((e && e.message) || e) });\n"
              '        return;\n'
              '      }'));
      // defineSlot returning null: the else of the render branch.
      expect(
          gpt,
          contains("        googletag.display('ad');\n"
              '      } else {\n'
              "        notify('slotError');\n"
              '      }'));
      expect(gpt, isNot(contains('catch (e) {}')));
    });
  });
}

/// Reads the single-quoted JavaScript string literal that follows [prefix]
/// in [script], the way a JS engine would, and returns its value and the 20
/// characters after its closing quote (or fewer at the end).
(String, String) jsStringAfter(String script, String prefix) {
  var i = script.indexOf(prefix);
  expect(i, isNonNegative, reason: 'no $prefix');
  i += prefix.length;
  expect(script[i], "'", reason: 'no string literal after $prefix');
  i++;
  final value = StringBuffer();
  while (true) {
    final c = script[i];
    // A raw line terminator ends a JS string with a syntax error.
    expect(['\n', '\r', '\u2028', '\u2029'], isNot(contains(c)),
        reason: 'raw line break in the literal after $prefix');
    if (c == "'") break;
    if (c != r'\') {
      value.write(c);
      i++;
      continue;
    }
    final e = script[i + 1];
    switch (e) {
      case 'n':
        value.write('\n');
        i += 2;
      case 'r':
        value.write('\r');
        i += 2;
      case 'x':
        value.writeCharCode(int.parse(script.substring(i + 2, i + 4), radix: 16));
        i += 4;
      case 'u':
        value.writeCharCode(int.parse(script.substring(i + 2, i + 6), radix: 16));
        i += 6;
      default:
        value.write(e);
        i += 2;
    }
  }
  final after = script.substring(i + 1);
  final rest = after.split('\n').first;
  return (value.toString(), rest.length > 20 ? rest.substring(0, 20) : rest);
}
