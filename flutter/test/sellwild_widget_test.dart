// SellwildWidget and SellwildBanner (deprecated WebView surfaces) on the
// fake WebView platform: what they load, and every failure path reported
// once through logFailure.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/failures/sellwild_log.dart';
import 'package:sellwild_sdk/src/widget_bridge.dart' show widgetLoadedDeadline;
import 'package:sellwild_sdk/src/widget_html.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'factories/shape_factories.dart';
import 'support/fake_webview_platform.dart';
import 'support/failure_capture.dart';

/// The attributes of the `<sellwild-widget>` element in [html], decoded as a
/// browser would (only `&quot;` is ever written).
Map<String, String> widgetAttributes(String html) {
  final start = html.indexOf('<sellwild-widget');
  final end = html.indexOf('></sellwild-widget>', start);
  final block = html.substring(start + '<sellwild-widget'.length, end);
  final out = <String, String>{};
  final rest = block.replaceAllMapped(RegExp(r'([^\s=]+)="([^"]*)"'), (m) {
    out[m[1]!] = m[2]!.replaceAll('&quot;', '"');
    return '';
  });
  // Anything left over is markup a broken value spilled out of its quotes.
  expect(rest.trim(), isEmpty, reason: 'stray markup in <sellwild-widget>');
  return out;
}

void main() {
  late FakeWebViewPlatform webviews;
  final configs = AppConfigFactory();

  setUp(() => webviews = FakeWebViewPlatform.install());

  Future<String> loadedWidgetHtml(
      WidgetTester tester, SellwildConfig config) async {
    await tester.pumpWidget(MaterialApp(home: SellwildWidget(config: config)));
    return webviews.lastController.lastHtml.html;
  }

  SellwildConfig applied(Map<String, dynamic> raw) {
    captureFailures();
    return SellwildSDK.apply(raw, const SellwildConfig(partnerCode: 'x'),
        isAndroid: false);
  }

  group('element attributes (A9 fixes)', () {
    testWidgets('a typed value with double quotes stays one attribute',
        (tester) async {
      final raw = configs.webPassthrough();

      final attrs =
          widgetAttributes(await loadedWidgetHtml(tester, applied(raw)));

      expect(attrs['link-text'], raw['LINK_TEXT']);
      expect(attrs['title'], raw['TITLE']);
    });

    testWidgets('a JSON null passthrough value is left out, not "null"',
        (tester) async {
      final attrs = widgetAttributes(
          await loadedWidgetHtml(tester, applied(configs.prebidSrcNull())));

      expect(attrs.containsKey('prebid-src'), isFalse);
      expect(attrs.values, isNot(contains('null')));
    });
  });

  group('SellwildWidget', () {
    final messages = BridgeMessageFactory();
    const config = SellwildConfig(partnerCode: 'weatherbug');

    /// Host callback calls, in order.
    late List<String> calls;
    late List<Object> errors;
    late List<SellwildListing> taps;

    Future<FakeWebViewController> pumpWidget(WidgetTester tester,
        {bool callbacks = true, bool throwing = false}) async {
      calls = [];
      errors = [];
      taps = [];
      void call(String name) {
        calls.add(name);
        if (throwing) throw StateError('host bug in $name');
      }

      await tester.pumpWidget(MaterialApp(
        home: callbacks
            ? SellwildWidget(
                config: config,
                onLoad: () => call('onLoad'),
                onListingTap: (listing) {
                  taps.add(listing);
                  call('onListingTap');
                },
                onAdImpression: (zoneId) => call('onAdImpression $zoneId'),
                onError: (error) {
                  errors.add(error);
                  call('onError');
                },
              )
            : const SellwildWidget(config: config),
      ));
      return webviews.lastController;
    }

    void post(FakeWebViewController controller, Object? message) =>
        controller.postJson('SellwildWidgetBridge', message);

    testWidgets('loads the pure page into a configured WebView',
        (tester) async {
      final failures = captureFailures();

      final controller = await pumpWidget(tester);
      await tester.pump();

      expect(controller.javaScriptMode, JavaScriptMode.unrestricted);
      expect(controller.backgroundColor, Colors.transparent);
      expect(controller.channels.keys, ['SellwildWidgetBridge']);
      expect(controller.lastHtml.html, buildWidgetHtml(config));
      expect(controller.lastHtml.baseUrl, widgetPageBaseUrl);
      expect(find.byKey(FakeWebViewWidget.widgetKey), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Page finished does nothing: the page's WIDGET_LOADED hides the
      // spinner.
      controller.navigationDelegate!.emitPageFinished(widgetPageBaseUrl);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(failures, isEmpty);
    });

    testWidgets('WIDGET_LOADED hides the spinner and calls onLoad',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);

      post(controller, messages.widgetLoaded());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(calls, ['onLoad']);
      expect(failures, isEmpty);
    });

    testWidgets('LISTING_CLICK, AD_IMPRESSION reach the host', (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);
      final click = messages.build();
      final impression = messages.adImpression();

      post(controller, click);
      post(controller, messages.listingStub());
      post(controller, impression);

      expect(calls, [
        'onListingTap',
        'onListingTap',
        'onAdImpression ${impression['zoneId']}',
      ]);
      expect(taps.first.url, click['url']);
      expect(taps.last.id,
          (messages.listingStub()['listing'] as Map<String, dynamic>)['id']);
      expect(failures, isEmpty);
    });

    testWidgets('ERROR: bridge.script.exception once, then onError',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);
      final message = messages.error();

      post(controller, message);

      expect(actionsOf(failures), ['bridge.script.exception']);
      final event = failures.single;
      expect(event.label, 'webview');
      expect(event.attributes['severity'], 'error');
      expect(event.attributes['msg'], message['message']);
      expect(calls, ['onError']);
      expect(errors.single.toString(), 'Exception: ${message['message']}');
    });

    testWidgets('without host callbacks every message is still handled',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester, callbacks: false);

      post(controller, messages.widgetLoaded());
      post(controller, messages.build());
      post(controller, messages.adImpression());
      post(controller, messages.errorNoMessage());
      controller.navigationDelegate!.emitWebResourceError(
          const WebResourceError(errorCode: -2, description: 'x'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(actionsOf(failures),
          ['bridge.script.exception', 'widget.webview_load.network']);
      expect(failures.first.attributes['msg'], 'Unknown error');
    });

    testWidgets('each message it cannot use is reported once, nothing called',
        (tester) async {
      final controller = await pumpWidget(tester);
      final cases = <String, (String, String)>{
        jsonEncode(messages.widgetLoaded()).substring(0, 10): (
          'bridge.message.parse',
          'FormatException'
        ),
        jsonEncode(messages.missingType()): (
          'bridge.message.invalid',
          'type is null'
        ),
        jsonEncode(messages.listingUnreadable()): (
          'bridge.message.invalid',
          'LISTING_CLICK listing cannot be read'
        ),
        jsonEncode(messages.unknownType()): (
          'bridge.message.unsupported',
          'unknown type NOPE'
        ),
      };

      for (final MapEntry(key: text, value: (code, detail)) in cases.entries) {
        final failures = captureFailures();
        controller.postMessage('SellwildWidgetBridge', text);

        expect(actionsOf(failures), [code], reason: text);
        final event = failures.single;
        expect(event.label, 'bridge');
        expect(event.attributes['severity'], 'warn');
        expect('${event.attributes['errName']} ${event.attributes['msg']}',
            contains(detail));
        endFailureCase();
      }
      expect(calls, isEmpty);
    });

    testWidgets('a numeric AD_IMPRESSION zoneId is drift: not reported',
        (tester) async {
      final failures = captureFailures();
      final trace = <String>[];
      SellwildLog.enabled = true;
      SellwildLog.printer = trace.add;
      final controller = await pumpWidget(tester);

      post(controller, messages.adImpressionNumberZone());

      // Contract-valid, but onAdImpression takes text: it is not called, as
      // before (contracts/expectations/drift/flutter.json). A debug trace,
      // not a failure.
      expect(failures, isEmpty);
      expect(calls, isEmpty);
      expect(trace, [
        'SellwildWidget: AD_IMPRESSION zoneId is an integer; '
            'onAdImpression takes text, not called'
      ]);
    });

    testWidgets(
        'a listing with photos entries that are not objects: '
        'listings.item.invalid once, then onListingTap', (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);
      final message = messages.listingNonObjectPhotos();
      final photos = (message['listing'] as Map<String, dynamic>)['photos'];

      post(controller, message);

      expect(actionsOf(failures), ['listings.item.invalid']);
      final event = failures.single;
      expect(event.label, 'bridge');
      expect(event.attributes['severity'], 'warn');
      expect(
          event.attributes['msg'],
          'LISTING_CLICK listing has 2 photos entries that are not objects; '
          'dropped');
      // The listing still reaches the host, without those entries.
      expect(calls, ['onListingTap']);
      expect(taps.single.photos, hasLength((photos as List).length - 2));
    });

    testWidgets(
        'a listing with one photos entry that is not an object: '
        'listings.item.invalid once, then onListingTap', (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);
      final message = messages.listingOneNonObjectPhoto();
      final photos = (message['listing'] as Map<String, dynamic>)['photos'];

      post(controller, message);

      expect(actionsOf(failures), ['listings.item.invalid']);
      expect(
          failures.single.attributes['msg'],
          'LISTING_CLICK listing has 1 photos entries that are not objects; '
          'dropped');
      expect(calls, ['onListingTap']);
      expect(taps.single.photos, hasLength((photos as List).length - 1));
    });

    testWidgets(
        'a listing whose photos hold a number, null and an array: '
        'all 3 reported once', (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);

      post(controller, messages.listingOtherKindPhotos());

      expect(actionsOf(failures), ['listings.item.invalid']);
      expect(
          failures.single.attributes['msg'],
          'LISTING_CLICK listing has 3 photos entries that are not objects; '
          'dropped');
      expect(calls, ['onListingTap']);
    });

    testWidgets('a host callback that throws: widget.host_callback.exception',
        (tester) async {
      final controller = await pumpWidget(tester, throwing: true);

      for (final (message, name) in [
        (messages.widgetLoaded(), 'onLoad'),
        (messages.build(), 'onListingTap'),
        (messages.adImpression(), 'onAdImpression'),
        (messages.error(), 'onError'),
      ]) {
        final failures = captureFailures();
        post(controller, message);

        final hostFailure = failures.last;
        expect(hostFailure.action, 'widget.host_callback.exception');
        expect(
            failures.where((e) => e.action == 'widget.host_callback.exception'),
            hasLength(1));
        expect(hostFailure.label, 'webview');
        expect(hostFailure.attributes['severity'], 'warn');
        expect(hostFailure.attributes['errName'], 'StateError');
        expect(hostFailure.attributes['msg'], startsWith('$name threw: '));
        endFailureCase();
      }
      // The spinner is gone even though onLoad threw.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a page load error: widget.webview_load.network, then onError',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);
      const error = WebResourceError(
        errorCode: -2,
        description: 'net::ERR_NAME_NOT_RESOLVED',
        errorType: WebResourceErrorType.hostLookup,
        isForMainFrame: true,
        url: 'https://widget.sellwild.com/partner.js?x=1',
      );

      controller.navigationDelegate!.emitWebResourceError(error);

      expect(actionsOf(failures), ['widget.webview_load.network']);
      final event = failures.single;
      expect(event.label, 'webview');
      expect(
          event.attributes['msg'], 'hostLookup -2: net::ERR_NAME_NOT_RESOLVED');
      expect(event.attributes['host'], 'widget.sellwild.com');
      expect(errors, [same(error)]);
    });

    testWidgets('a page load error reports the host of the failed URL',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);

      controller.navigationDelegate!.emitWebResourceError(
          const WebResourceError(
              errorCode: -2,
              description: 'net::ERR_NAME_NOT_RESOLVED',
              isForMainFrame: true,
              url: 'https://www.sellwild.com/itemDetail/1'));
      controller.navigationDelegate!.emitWebResourceError(
          const WebResourceError(
              errorCode: -2, description: 'no url', isForMainFrame: true));

      expect(actionsOf(failures),
          ['widget.webview_load.network', 'widget.webview_load.network']);
      // The page that failed, not the base URL the HTML was loaded with.
      expect(failures.first.attributes['host'], 'www.sellwild.com');
      expect(failures.last.attributes.containsKey('host'), isFalse);
    });

    testWidgets('a load error whose onError throws is reported, not rethrown',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester, throwing: true);

      // Before: the host's exception escaped the navigation delegate.
      controller.navigationDelegate!.emitWebResourceError(
          const WebResourceError(
              errorCode: -2, description: 'x', isForMainFrame: true));

      expect(actionsOf(failures),
          ['widget.webview_load.network', 'widget.host_callback.exception']);
      expect(failures.last.label, 'webview');
      expect(failures.last.attributes['msg'], startsWith('onError threw: '));
      expect(calls, ['onError']);
    });

    testWidgets('a sub-resource error goes to onError only, as before',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);
      const error = WebResourceError(
          errorCode: -6, description: 'pixel', isForMainFrame: false);

      controller.navigationDelegate!.emitWebResourceError(error);

      expect(failures, isEmpty);
      expect(errors, [same(error)]);
    });

    testWidgets(
        'a WebView that cannot load: widget.webview_load.exception once',
        (tester) async {
      final failures = captureFailures();
      webviews.loadError = StateError('renderer gone');

      await pumpWidget(tester);
      await tester.pump();
      // The page never loads: reported once, not as a timeout too.
      await tester.pump(widgetLoadedDeadline * 2);

      // A platform exception, not a network failure.
      expect(actionsOf(failures), ['widget.webview_load.exception']);
      expect(failures.single.attributes['severity'], 'error');
      final event = failures.single;
      expect(event.label, 'webview');
      expect(event.attributes['errName'], 'StateError');
      expect(event.attributes['msg'], 'WebView setup failed: renderer gone');
      expect(event.attributes['host'], 'widget.sellwild.com');
    });

    testWidgets('WIDGET_LOADED after dispose is ignored, as before',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);
      await tester.pumpWidget(const SizedBox());

      post(controller, messages.widgetLoaded());
      // Dispose also stopped the load watchdog.
      await tester.pump(widgetLoadedDeadline * 2);

      expect(calls, isEmpty);
      expect(failures, isEmpty);
    });

    testWidgets('no WIDGET_LOADED in time: widget.load.timeout once',
        (tester) async {
      final failures = captureFailures();
      await pumpWidget(tester);

      await tester.pump(widgetLoadedDeadline - const Duration(milliseconds: 1));
      expect(failures, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));

      expect(actionsOf(failures), ['widget.load.timeout']);
      final event = failures.single;
      expect(event.label, 'webview');
      expect(event.attributes['severity'], 'error');
      expect(event.attributes['msg'], 'no WIDGET_LOADED within 15 s');
      expect(event.attributes['host'], 'widget.sellwild.com');
      // Reporting only: the spinner stays and the host is not called.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(calls, isEmpty);

      // Once: a later WIDGET_LOADED still hides the spinner, and nothing
      // more is reported.
      await tester.pump(widgetLoadedDeadline * 2);
      post(webviews.lastController, messages.widgetLoaded());
      await tester.pump();
      expect(actionsOf(failures), ['widget.load.timeout']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(calls, ['onLoad']);
    });

    testWidgets('WIDGET_LOADED in time stops the watchdog', (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);

      await tester.pump(widgetLoadedDeadline - const Duration(seconds: 1));
      post(controller, messages.widgetLoaded());
      await tester.pump(widgetLoadedDeadline * 2);

      expect(failures, isEmpty);
      expect(calls, ['onLoad']);
    });

    testWidgets('a page load error is reported once, not as a timeout too',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);

      controller.navigationDelegate!.emitWebResourceError(
          const WebResourceError(
              errorCode: -2, description: 'x', isForMainFrame: true));
      await tester.pump(widgetLoadedDeadline * 2);

      expect(actionsOf(failures), ['widget.webview_load.network']);
    });

    testWidgets('a sub-resource error leaves the watchdog running',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);

      controller.navigationDelegate!.emitWebResourceError(
          const WebResourceError(
              errorCode: -6, description: 'pixel', isForMainFrame: false));
      await tester.pump(widgetLoadedDeadline);

      expect(actionsOf(failures), ['widget.load.timeout']);
    });

    testWidgets(
        'partner.js fails to load (Android): widget.script_load.network '
        'once, then onError', (tester) async {
      final failures = captureFailures();
      final controller = await pumpWidget(tester);
      const error = WebResourceError(
        errorCode: -2,
        description: 'net::ERR_NAME_NOT_RESOLVED',
        errorType: WebResourceErrorType.hostLookup,
        isForMainFrame: false,
        url: widgetScriptUrl,
      );

      controller.navigationDelegate!.emitWebResourceError(error);

      expect(actionsOf(failures), ['widget.script_load.network']);
      final event = failures.single;
      expect(event.label, 'widget');
      expect(event.attributes['severity'], 'fatal');
      expect(
          event.attributes['msg'], 'hostLookup -2: net::ERR_NAME_NOT_RESOLVED');
      expect(event.attributes['host'], 'widget.sellwild.com');
      // The host still gets every load error, as before.
      expect(errors, [same(error)]);
      expect(calls, ['onError']);

      // The page still sends WIDGET_LOADED on its timer: no timeout too.
      post(controller, messages.widgetLoaded());
      await tester.pump(widgetLoadedDeadline * 2);
      expect(actionsOf(failures), ['widget.script_load.network']);
    });
  });

  group('SellwildBanner', () {
    final adMessages = AdBridgeMessageFactory();
    const zoneConfig = SellwildConfig(partnerCode: 'weatherbug');

    late List<String> calls;
    late List<Object> errors;

    Future<FakeWebViewController> pumpBanner(
      WidgetTester tester, {
      SellwildConfig config = zoneConfig,
      String? zoneId = '43',
      bool callbacks = true,
      bool throwing = false,
    }) async {
      calls = [];
      errors = [];
      void call(String name) {
        calls.add(name);
        if (throwing) throw StateError('host bug in $name');
      }

      // Centered, so the banner's SizedBox gets loose constraints.
      await tester.pumpWidget(MaterialApp(
        home: Center(
            child: callbacks
                ? SellwildBanner(
                    config: config,
                    adSize: SellwildAdSize.mrec300x250,
                    zoneId: zoneId,
                    onImpression: () => call('onImpression'),
                    onClick: () => call('onClick'),
                    onError: (error) {
                      errors.add(error);
                      call('onError');
                    },
                  )
                : SellwildBanner(
                    config: config,
                    adSize: SellwildAdSize.mrec300x250,
                    zoneId: zoneId)),
      ));
      return webviews.lastController;
    }

    void post(FakeWebViewController controller, Object? message) =>
        controller.postJson('SellwildAdBridge', message);

    testWidgets('loads the pure banner page at the ad size', (tester) async {
      final failures = captureFailures();

      final controller = await pumpBanner(tester);
      await tester.pump();

      expect(controller.javaScriptMode, JavaScriptMode.unrestricted);
      expect(controller.channels.keys, ['SellwildAdBridge']);
      final html = controller.lastHtml.html;
      expect(
          html, buildBannerHtml(zoneConfig, SellwildAdSize.mrec300x250, '43'));
      expect(controller.lastHtml.baseUrl, widgetPageBaseUrl);
      expect(tester.getSize(find.byType(SellwildBanner)), const Size(300, 250));
      // The page posts the factory's impression message.
      expect(html, contains("notify('impression')"));
      expect(html, contains('JSON.stringify(Object.assign({ type: type }'));
      expect(failures, isEmpty);
    });

    testWidgets('impression and click reach the host', (tester) async {
      final failures = captureFailures();
      final controller = await pumpBanner(tester);

      post(controller, adMessages.impression());
      post(controller, adMessages.click());

      expect(calls, ['onImpression', 'onClick']);
      expect(failures, isEmpty);
    });

    testWidgets('without callbacks messages are handled quietly',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpBanner(tester, callbacks: false);

      post(controller, adMessages.impression());
      post(controller, adMessages.click());
      controller.navigationDelegate!.emitWebResourceError(
          const WebResourceError(
              errorCode: -6, description: 'x', isForMainFrame: false));

      expect(failures, isEmpty);
    });

    testWidgets('each message it cannot use is reported once (banner)',
        (tester) async {
      final controller = await pumpBanner(tester);
      final cases = <String, String>{
        'impression': 'bridge.message.parse',
        jsonEncode(adMessages.missingType()): 'bridge.message.invalid',
        jsonEncode([adMessages.impression()]): 'bridge.message.invalid',
        jsonEncode(adMessages.unknownType()): 'bridge.message.unsupported',
        jsonEncode(adMessages.scriptErrorNoSrc()): 'bridge.message.invalid',
        jsonEncode(adMessages.slotErrorMessageNumber()):
            'bridge.message.invalid',
      };

      for (final MapEntry(key: text, value: code) in cases.entries) {
        final failures = captureFailures();
        controller.postMessage('SellwildAdBridge', text);

        expect(actionsOf(failures), [code], reason: text);
        expect(failures.single.label, 'banner');
        expect(failures.single.attributes['severity'], 'warn');
        endFailureCase();
      }
      expect(calls, isEmpty);
    });

    testWidgets('a host callback that throws is reported, not rethrown',
        (tester) async {
      final controller = await pumpBanner(tester, throwing: true);

      for (final (message, name) in [
        (adMessages.impression(), 'onImpression'),
        (adMessages.click(), 'onClick'),
      ]) {
        final failures = captureFailures();
        post(controller, message);

        expect(actionsOf(failures), ['widget.host_callback.exception']);
        expect(failures.single.label, 'banner');
        expect(failures.single.attributes['msg'], startsWith('$name threw: '));
        endFailureCase();
      }
    });

    testWidgets('a page load error: widget.webview_load.network (banner)',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpBanner(tester);
      const error = WebResourceError(
          errorCode: -1009,
          description: 'offline',
          errorType: WebResourceErrorType.connect,
          isForMainFrame: true);

      controller.navigationDelegate!.emitWebResourceError(error);

      expect(actionsOf(failures), ['widget.webview_load.network']);
      expect(failures.single.label, 'banner');
      expect(failures.single.attributes['msg'], 'connect -1009: offline');
      expect(errors, [same(error)]);
    });

    testWidgets('a load error whose onError throws is reported (banner)',
        (tester) async {
      final failures = captureFailures();
      final controller = await pumpBanner(tester, throwing: true);

      controller.navigationDelegate!.emitWebResourceError(
          const WebResourceError(
              errorCode: -6, description: 'pixel', isForMainFrame: false));

      expect(actionsOf(failures), ['widget.host_callback.exception']);
      expect(failures.single.label, 'banner');
      expect(failures.single.attributes['msg'], startsWith('onError threw: '));
      expect(calls, ['onError']);
    });

    testWidgets('a WebView that cannot load: reported once (banner)',
        (tester) async {
      final failures = captureFailures();
      webviews.loadError = StateError('renderer gone');

      await pumpBanner(tester);
      await tester.pump();

      expect(actionsOf(failures), ['widget.webview_load.exception']);
      expect(failures.single.label, 'banner');
    });

    testWidgets('no GAM tag and no zone: ad.banner_config.missing once',
        (tester) async {
      final failures = captureFailures();

      final controller = await pumpBanner(tester, zoneId: null);
      await tester.pump();

      expect(actionsOf(failures), ['ad.banner_config.missing']);
      final event = failures.single;
      expect(event.label, 'banner');
      expect(event.attributes['severity'], 'warn');
      expect(event.attributes['msg'], 'no GAM tag and no zone id');
      // The blank page still loads, as before.
      expect(controller.lastHtml.html, contains('// No ad configuration'));
    });

    testWidgets('GPT disabled and no zone: ad.banner_config.missing',
        (tester) async {
      final failures = captureFailures();

      await pumpBanner(tester,
          config: const SellwildConfig(
              partnerCode: 'p', gamTag: '/1/x', disableGpt: true),
          zoneId: null);

      expect(failures.single.attributes['msg'],
          'GPT is disabled and there is no zone id');
    });

    testWidgets("a GAM tag '' and no zone: ad.banner_config.missing",
        (tester) async {
      final failures = captureFailures();

      final controller = await pumpBanner(tester,
          config: const SellwildConfig(partnerCode: 'p', gamTag: ''),
          zoneId: null);

      expect(actionsOf(failures), ['ad.banner_config.missing']);
      expect(failures.single.attributes['msg'], 'no GAM tag and no zone id');
      expect(controller.lastHtml.html, contains('// No ad configuration'));
    });

    testWidgets('a GAM banner reports nothing', (tester) async {
      final failures = captureFailures();
      const gam = SellwildConfig(partnerCode: 'p', gamTag: '/1/x');

      final controller = await pumpBanner(tester, config: gam, zoneId: null);
      await tester.pump();

      final html = controller.lastHtml.html;
      expect(html, contains("googletag.defineSlot('/1/x'"));
      // The page posts the factory's scriptError and slotError messages.
      expect(html, contains("notify('scriptError', { src: s.src });"));
      expect(html, contains("notify('slotError');"));
      expect(
          html,
          contains("notify('slotError', "
              '{ message: String((e && e.message) || e) });'));
      expect(failures, isEmpty);
    });

    testWidgets('a banner script that fails: ad.banner_script.network once',
        (tester) async {
      final controller = await pumpBanner(tester);

      for (final (src, host) in [
        (
          'https://bidstream.sellwild.com/ads?zone=43&w=300&h=250',
          'bidstream.sellwild.com'
        ),
        ('$defaultGptBase/tag/js/gpt.js', 'securepubads.g.doubleclick.net'),
      ]) {
        final failures = captureFailures();
        post(controller, adMessages.scriptError(src: src));

        expect(actionsOf(failures), ['ad.banner_script.network']);
        final event = failures.single;
        expect(event.label, 'banner');
        expect(event.attributes['severity'], 'error');
        expect(event.attributes['msg'], 'banner script failed to load');
        // Only the host: never the zone id in the query.
        expect(event.attributes['host'], host);
        endFailureCase();
      }
      // Reporting only: the host is not called.
      expect(calls, isEmpty);
    });

    testWidgets(
        'a failed script Android also reports as a sub-resource error is '
        'reported once', (tester) async {
      final failures = captureFailures();
      final controller = await pumpBanner(tester);
      final message = adMessages.scriptError();
      final error = WebResourceError(
          errorCode: -2,
          description: 'net::ERR_NAME_NOT_RESOLVED',
          isForMainFrame: false,
          url: message['src'] as String);

      controller.navigationDelegate!.emitWebResourceError(error);
      post(controller, message);

      expect(actionsOf(failures), ['ad.banner_script.network']);
      // The load error still reaches onError, as before.
      expect(errors, [same(error)]);
    });

    testWidgets('a slot GPT cannot define: ad.gpt_slot.invalid once',
        (tester) async {
      const gam = SellwildConfig(partnerCode: 'p', gamTag: '/1/x');
      final controller = await pumpBanner(tester, config: gam, zoneId: null);
      final thrown = adMessages.slotErrorThrown();

      for (final (message, text) in [
        (adMessages.slotErrorNull(), 'defineSlot returned null'),
        (thrown, thrown['message']),
      ]) {
        final failures = captureFailures();
        post(controller, message);

        expect(actionsOf(failures), ['ad.gpt_slot.invalid']);
        final event = failures.single;
        expect(event.label, 'banner');
        expect(event.attributes['severity'], 'error');
        expect(event.attributes['msg'], text);
        endFailureCase();
      }
      expect(calls, isEmpty);
    });
  });
}
