// The pure bridge decoders behind the deprecated WebView surfaces
// (lib/src/widget_bridge.dart): each message becomes what the widget acts
// on, or a BridgeFailure with the code the widget reports.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/widget_bridge.dart';
import 'package:sellwild_sdk/src/widget_html.dart' show widgetScriptUrl;
import 'package:webview_flutter/webview_flutter.dart';

import 'factories/shape_factories.dart';

WidgetBridgeMessage decode(Object? message) =>
    decodeWidgetBridgeMessage(jsonEncode(message));

/// The failure [message] decodes to, as (code, message).
(String, String?) failureOf(WidgetBridgeMessage message) {
  expect(message, isA<BridgeFailure>());
  final failure = message as BridgeFailure;
  return (failure.code, failure.message);
}

void main() {
  final messages = BridgeMessageFactory();
  final adMessages = AdBridgeMessageFactory();

  group('decodeWidgetBridgeMessage', () {
    test('WIDGET_LOADED', () {
      expect(decode(messages.widgetLoaded()), isA<WidgetLoaded>());
    });

    test('LISTING_CLICK with only a url gives a stub listing', () {
      final message = messages.build();

      final click = decode(message) as ListingClick;

      expect(click.listing.url, message['url']);
      expect(click.listing.id, '');
      expect(click.listing.status, 'active');
      expect(click.listing.title, '');
      expect(click.listing.photos, isEmpty);
    });

    test('LISTING_CLICK with a listing uses it, even with a url', () {
      final message = messages.listingStub();
      final listing = message['listing'] as Map<String, dynamic>;

      final click = decode(message) as ListingClick;

      expect(click.listing.id, listing['id']);
      expect(click.listing.title, listing['title']);
      expect(click.listing.url, isNull);
    });

    test('LISTING_CLICK with a real cache item', () {
      final message = messages.listingItem();
      final listing = message['listing'] as Map<String, dynamic>;

      final click = decode(message) as ListingClick;

      expect(click.listing.id, '${listing['id']}');
      expect(click.listing.photos, isNotEmpty);
      expect(click.droppedPhotos, 0);
      expect((decode(messages.build()) as ListingClick).droppedPhotos, 0);
    });

    test('LISTING_CLICK counts the photos entries fromJson skips', () {
      final message = messages.listingNonObjectPhotos();
      final photos = (message['listing'] as Map<String, dynamic>)['photos'];

      final click = decode(message) as ListingClick;

      expect(click.droppedPhotos, 2);
      expect(click.listing.photos, hasLength((photos as List).length - 2));
    });

    test('LISTING_CLICK counts a single photos entry that is not an object',
        () {
      final message = messages.listingOneNonObjectPhoto();
      final photos = (message['listing'] as Map<String, dynamic>)['photos'];

      final click = decode(message) as ListingClick;

      expect(click.droppedPhotos, 1);
      expect(click.listing.photos, hasLength((photos as List).length - 1));
    });

    test('LISTING_CLICK counts a number, null and an array in photos', () {
      final message = messages.listingOtherKindPhotos();
      final photos = (message['listing'] as Map<String, dynamic>)['photos'];

      final click = decode(message) as ListingClick;

      // Not only text: every entry that is not an object is skipped.
      expect(click.droppedPhotos, 3);
      expect(click.listing.photos, hasLength((photos as List).length - 3));
      expect(click.listing.photos, isNotEmpty);
    });

    test('AD_IMPRESSION with a text zone id, and without one', () {
      final message = messages.adImpression();

      expect((decode(message) as AdImpression).zoneId, message['zoneId']);
      expect(
          (decode(messages.adImpressionNoZone()) as AdImpression).zoneId, '');
    });

    test('AD_IMPRESSION with a numeric zone id is unread drift, not a failure',
        () {
      final unread = decode(messages.adImpressionNumberZone()) as UnreadMessage;

      expect(unread.reason,
          'AD_IMPRESSION zoneId is an integer; onAdImpression takes text');
    });

    test('ERROR with its text, and without', () {
      expect((decode(messages.error()) as PageError).message,
          messages.error()['message']);
      expect((decode(messages.errorNoMessage()) as PageError).message,
          'Unknown error');
    });

    test('extra fields are ignored', () {
      final message = messages.build({'extra': 1});

      expect((decode(message) as ListingClick).listing.url, message['url']);
    });

    test('text that is not JSON: bridge.message.parse', () {
      final cut = jsonEncode(messages.widgetLoaded()).substring(0, 10);

      final failure = decodeWidgetBridgeMessage(cut) as BridgeFailure;

      expect(failure.code, 'bridge.message.parse');
      expect(failure.error, isA<FormatException>());
      expect(failure.message, isNull);
    });

    test('shapes it cannot use: bridge.message.invalid', () {
      final cases = {
        'message is an array': messages.bodyArray(),
        'type is null': messages.missingType(),
        'type is an integer': messages.typeNumber(),
        'ERROR message is an integer': messages.errorMessageNumber(),
        'LISTING_CLICK listing is text': messages.listingNotObject(),
        'LISTING_CLICK url is an integer': messages.urlNumber(),
        'AD_IMPRESSION zoneId is an object': messages.zoneIdObject(),
        'LISTING_CLICK has no listing and no url': messages.listingClickEmpty(),
      };

      for (final MapEntry(key: text, value: message) in cases.entries) {
        expect(failureOf(decode(message)), ('bridge.message.invalid', text));
      }
    });

    test(
        'a listing fromJson cannot read: bridge.message.invalid with the error',
        () {
      final failure = decode(messages.listingUnreadable()) as BridgeFailure;

      expect(failure.code, 'bridge.message.invalid');
      expect(failure.message, 'LISTING_CLICK listing cannot be read');
      expect(failure.error, isA<TypeError>());
    });

    test('an unknown type: bridge.message.unsupported', () {
      expect(failureOf(decode(messages.unknownType())),
          ('bridge.message.unsupported', 'unknown type NOPE'));
    });
  });

  group('decodeAdBridgeMessage', () {
    AdBridgeMessage decodeAd(Object? message) =>
        decodeAdBridgeMessage(jsonEncode(message));

    test('impression and click', () {
      expect(decodeAd(adMessages.impression()), isA<BannerImpression>());
      expect(decodeAd(adMessages.click()), isA<BannerClick>());
    });

    test('scriptError carries the script URL', () {
      final message = adMessages.scriptError();

      final decoded = decodeAd(message);

      expect(decoded, isA<BannerScriptError>());
      expect((decoded as BannerScriptError).src, message['src']);
    });

    test('slotError carries what defineSlot threw, or null', () {
      final thrown = adMessages.slotErrorThrown();

      expect((decodeAd(thrown) as BannerSlotError).message, thrown['message']);
      expect((decodeAd(adMessages.slotErrorNull()) as BannerSlotError).message,
          isNull);
    });

    test('failures', () {
      (String, String?) of(AdBridgeMessage m) =>
          ((m as BridgeFailure).code, m.message);

      expect(of(decodeAd(adMessages.unknownType())),
          ('bridge.message.unsupported', 'unknown type viewable'));
      expect(of(decodeAd(adMessages.missingType())),
          ('bridge.message.invalid', 'type is null'));
      expect(of(decodeAd([adMessages.impression()])),
          ('bridge.message.invalid', 'message is an array'));
      expect(of(decodeAdBridgeMessage('impression')),
          ('bridge.message.parse', null));
      expect(of(decodeAd(adMessages.scriptErrorNoSrc())),
          ('bridge.message.invalid', 'scriptError src is null'));
      expect(of(decodeAd(adMessages.slotErrorMessageNumber())),
          ('bridge.message.invalid', 'slotError message is an integer'));
    });
  });

  group('WebView load errors', () {
    test('isPageLoadError: the main frame, or unknown', () {
      WebResourceError error(bool? mainFrame) => WebResourceError(
          errorCode: -2, description: 'x', isForMainFrame: mainFrame);

      expect(isPageLoadError(error(true)), isTrue);
      expect(isPageLoadError(error(null)), isTrue);
      expect(isPageLoadError(error(false)), isFalse);
    });

    test('isWidgetScriptLoadError: partner.js as a sub-resource only', () {
      WebResourceError error(String? url, {bool? mainFrame = false}) =>
          WebResourceError(
              errorCode: -2,
              description: 'x',
              isForMainFrame: mainFrame,
              url: url);

      expect(isWidgetScriptLoadError(error(widgetScriptUrl)), isTrue);
      // The page itself failing is widget.webview_load.network instead.
      expect(isWidgetScriptLoadError(error(widgetScriptUrl, mainFrame: true)),
          isFalse);
      expect(isWidgetScriptLoadError(error(widgetScriptUrl, mainFrame: null)),
          isFalse);
      // Any other sub-resource (an ad, a pixel) is not the widget bundle.
      expect(isWidgetScriptLoadError(error('$widgetScriptUrl?v=2')), isFalse);
      expect(isWidgetScriptLoadError(error('https://widget.sellwild.com/x.js')),
          isFalse);
      expect(isWidgetScriptLoadError(error(null)), isFalse);
    });

    test('widgetLoadedDeadline leaves room after the page\'s 600 ms', () {
      expect(widgetLoadedDeadline, const Duration(seconds: 15));
    });

    test('webResourceErrorSummary: type and code', () {
      expect(
        webResourceErrorSummary(const WebResourceError(
          errorCode: -2,
          description: 'net::ERR_NAME_NOT_RESOLVED',
          errorType: WebResourceErrorType.hostLookup,
        )),
        'hostLookup -2',
      );
      expect(
        webResourceErrorSummary(
            const WebResourceError(errorCode: 404, description: 'x')),
        'unknown 404',
      );
    });
  });

  test('SellwildListing stubs keep the fields the old handler set', () {
    // The stub is built with fromJson, as before, so its photos list is a
    // normal growable list.
    final click = decode(messages.build()) as ListingClick;

    expect(
        click.listing.photos..add(const SellwildPhoto(url: 'u', thumbUrl: 't')),
        hasLength(1));
  });
}
