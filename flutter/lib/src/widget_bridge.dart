// Pure decoders for the messages the deprecated WebView surfaces receive
// (contracts/schemas/bridge-message.schema.json for SellwildWidgetBridge;
// SellwildAdBridge has no schema yet), and pure checks on their WebView load
// errors. A message that cannot be used decodes to a [BridgeFailure]
// carrying its failure code; the widget states in sellwild_widget.dart
// report it once through logFailure.

import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart' show WebResourceError;

import 'failures/sellwild_failure_code.dart';
import 'listing_json.dart';
import 'remote_config.dart' show jsonKind;
import 'sellwild_models.dart';
import 'widget_html.dart' show widgetScriptUrl;

/// A SellwildWidgetBridge message, decoded.
sealed class WidgetBridgeMessage {}

/// A SellwildAdBridge (banner) message, decoded.
sealed class AdBridgeMessage {}

/// `WIDGET_LOADED`: the page is up; hide the spinner.
final class WidgetLoaded implements WidgetBridgeMessage {
  const WidgetLoaded();
}

/// `LISTING_CLICK`: the listing, or a stub holding only the URL.
final class ListingClick implements WidgetBridgeMessage {
  const ListingClick(this.listing, {this.droppedPhotos = 0});

  final SellwildListing listing;

  /// `photos` entries of the sent listing that are not objects: fromJson
  /// skips them and the widget reports them (listings.item.invalid).
  final int droppedPhotos;
}

/// `AD_IMPRESSION`: the zone id ('' when the page sent none).
final class AdImpression implements WidgetBridgeMessage {
  const AdImpression(this.zoneId);

  final String zoneId;
}

/// A contract-valid message Flutter does not act on: known drift
/// (contracts/expectations/drift/flutter.json), not a failure. The widget
/// traces [reason] to the debug logger.
final class UnreadMessage implements WidgetBridgeMessage {
  const UnreadMessage(this.reason);

  final String reason;
}

/// `ERROR`: a script error inside the widget page (raw text; logFailure
/// sanitizes it).
final class PageError implements WidgetBridgeMessage {
  const PageError(this.message);

  final String message;
}

/// Banner `impression`.
final class BannerImpression implements AdBridgeMessage {
  const BannerImpression();
}

/// Banner `click`. The banner page never posts it today.
final class BannerClick implements AdBridgeMessage {
  const BannerClick();
}

/// Banner `scriptError`: gpt.js or the zone script failed to load
/// (ad.banner_script.network).
final class BannerScriptError implements AdBridgeMessage {
  const BannerScriptError(this.src);

  /// The script URL. Only its host is reported.
  final String src;
}

/// Banner `slotError`: GPT could not define the slot
/// (ad.gpt_slot.invalid).
final class BannerSlotError implements AdBridgeMessage {
  const BannerSlotError(this.message);

  /// What defineSlot threw (raw page text; logFailure sanitizes it), or
  /// null when it returned null.
  final String? message;
}

/// A message that could not be used.
final class BridgeFailure implements WidgetBridgeMessage, AdBridgeMessage {
  const BridgeFailure(this.code, {this.error, this.message});

  /// Not JSON (bridge.message.parse).
  const BridgeFailure.parse(FormatException error)
      : this(SellwildFailureCode.bridgeMessageParse, error: error);

  /// A missing or wrong-typed field (bridge.message.invalid).
  const BridgeFailure.invalid(String message, {Object? error})
      : this(SellwildFailureCode.bridgeMessageInvalid,
            error: error, message: message);

  /// An unknown type (bridge.message.unsupported).
  const BridgeFailure.unsupported(String message)
      : this(SellwildFailureCode.bridgeMessageUnsupported, message: message);

  /// A SellwildFailureCode constant.
  final String code;

  /// The caught error, if any.
  final Object? error;

  /// What is wrong: field names and JSON kinds, never a field's value.
  final String? message;
}

/// [text] as a JSON object, or why it is not one.
({Map<String, dynamic>? json, BridgeFailure? failure}) decodeBridgeObject(
    String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    return (json: null, failure: BridgeFailure.parse(e));
  }
  if (decoded is Map<String, dynamic>) return (json: decoded, failure: null);
  return (
    json: null,
    failure: BridgeFailure.invalid('message is ${jsonKind(decoded)}'),
  );
}

/// Decodes one SellwildWidgetBridge message. Never throws.
WidgetBridgeMessage decodeWidgetBridgeMessage(String text) {
  final (:json, :failure) = decodeBridgeObject(text);
  if (json == null) return failure!;
  final type = json['type'];
  if (type is! String) {
    return BridgeFailure.invalid('type is ${jsonKind(type)}');
  }
  switch (type) {
    case 'WIDGET_LOADED':
      return const WidgetLoaded();
    case 'LISTING_CLICK':
      // The web widget sends window.open(url) on listing tap. A full
      // listing object is not available at the WebView boundary.
      return _listingClick(json);
    case 'AD_IMPRESSION':
      return switch (json['zoneId']) {
        null => const AdImpression(''),
        final String zoneId => AdImpression(zoneId),
        // The schema allows a number; onAdImpression takes text, so it is
        // not called, as before (a swallowed TypeError then).
        final num zoneId => UnreadMessage('AD_IMPRESSION zoneId is '
            '${jsonKind(zoneId)}; onAdImpression takes text'),
        final zoneId =>
          BridgeFailure.invalid('AD_IMPRESSION zoneId is ${jsonKind(zoneId)}'),
      };
    case 'ERROR':
      final message = json['message'];
      if (message != null && message is! String) {
        return BridgeFailure.invalid('ERROR message is ${jsonKind(message)}');
      }
      return PageError(message as String? ?? 'Unknown error');
    default:
      return BridgeFailure.unsupported('unknown type $type');
  }
}

WidgetBridgeMessage _listingClick(Map<String, dynamic> json) {
  final listing = json['listing'];
  final url = json['url'];
  if (listing != null && listing is! Map<String, dynamic>) {
    return BridgeFailure.invalid(
        'LISTING_CLICK listing is ${jsonKind(listing)}');
  }
  if (url != null && url is! String) {
    return BridgeFailure.invalid('LISTING_CLICK url is ${jsonKind(url)}');
  }
  if (listing is Map<String, dynamic>) {
    try {
      return ListingClick(SellwildListing.fromJson(listing),
          droppedPhotos: nonObjectPhotoCount(listing));
    } catch (e) {
      return BridgeFailure.invalid('LISTING_CLICK listing cannot be read',
          error: e);
    }
  }
  if (url is String) {
    // URL-only path: a minimal stub so callers can navigate.
    return ListingClick(SellwildListing.fromJson(
        {'id': '', 'status': 'active', 'title': '', 'url': url}));
  }
  return const BridgeFailure.invalid('LISTING_CLICK has no listing and no url');
}

/// Decodes one SellwildAdBridge message. Never throws.
AdBridgeMessage decodeAdBridgeMessage(String text) {
  final (:json, :failure) = decodeBridgeObject(text);
  if (json == null) return failure!;
  return switch (json['type']) {
    'impression' => const BannerImpression(),
    'click' => const BannerClick(),
    'scriptError' => switch (json['src']) {
        final String src => BannerScriptError(src),
        final src =>
          BridgeFailure.invalid('scriptError src is ${jsonKind(src)}'),
      },
    'slotError' => switch (json['message']) {
        null => const BannerSlotError(null),
        final String message => BannerSlotError(message),
        final message =>
          BridgeFailure.invalid('slotError message is ${jsonKind(message)}'),
      },
    final String type => BridgeFailure.unsupported('unknown type $type'),
    final type => BridgeFailure.invalid('type is ${jsonKind(type)}'),
  };
}

/// How long SellwildWidget waits for the page's WIDGET_LOADED before it
/// reports widget.load.timeout. The page sends it 600 ms after
/// DOMContentLoaded (buildWidgetHtml), so this leaves a slow device ample
/// room.
const Duration widgetLoadedDeadline = Duration(seconds: 15);

/// Whether [error] is for the page itself (a sub-resource error is not a
/// page load failure). Unknown counts as the page.
bool isPageLoadError(WebResourceError error) => error.isForMainFrame ?? true;

/// Whether [error] is partner.js (the widget bundle) failing to load, as a
/// sub-resource of the widget page (widget.script_load.network). Only
/// Android reports sub-resource errors; the page itself has no way to
/// report it yet (bridge-message.schema.json has no message for it).
bool isWidgetScriptLoadError(WebResourceError error) =>
    !isPageLoadError(error) && error.url == widgetScriptUrl;

/// `<errorType> <errorCode>` for a WebView load error, e.g. `hostLookup -2`.
String webResourceErrorSummary(WebResourceError error) =>
    '${error.errorType?.name ?? 'unknown'} ${error.errorCode}';
