// Factories for the payloads the Flutter SDK reads: the app config
// (SellwildSDK.configure), the listings cache and its items
// (SellwildAPIClient.fetchListings), and WebView bridge messages
// (sellwild_widget.dart). Each starts from a real captured sample or a
// contracts fixture.

import 'dart:convert';

import '../support/fixtures.dart';
import 'contract_factory.dart';

/// `GET widget.sellwild.com/app/<partner>/<slug>.json`. Base: the real
/// weatherbug config, samples/app-config/weatherbug_weatherbug-weatherbug.json.
class AppConfigFactory extends JsonObjectFactory {
  AppConfigFactory()
      : super('app-config',
            'samples/app-config/weatherbug_weatherbug-weatherbug.json');

  /// Failure reporting turned off remotely, with a partial sample rate.
  Map<String, dynamic> failuresOff() =>
      build({'FAILURES_ENABLED': false, 'FAILURES_SAMPLE_RATE': 0.25});

  /// [failuresOff] with the SDK debug flag on (the logFailure debug echo).
  Map<String, dynamic> failuresOffDebug() => build({
        'FAILURES_ENABLED': false,
        'FAILURES_SAMPLE_RATE': 0.25,
        'DEBUG': true,
      });

  /// The kill switches as CMS text fields send them.
  Map<String, dynamic> switchesAsText() => build({
        'EVENTS_ENABLED': 'off',
        'FAILURES_ENABLED': 'yes',
        'FAILURES_SAMPLE_RATE': '0.5',
      });

  /// The default config as response text, with AD_REFRESH_INTERVAL 1e400:
  /// it decodes to Infinity, which Duration cannot hold, so apply throws.
  /// Text, because jsonEncode cannot write Infinity.
  String refreshIntervalOverflowText() {
    final text = jsonEncode(build({'AD_REFRESH_INTERVAL': 0}));
    return text.replaceFirst(
        '"AD_REFRESH_INTERVAL":0', '"AD_REFRESH_INTERVAL":1e400');
  }

  @override
  List<Variant> get variants => [
        Variant('default', build),
        Variant('failures-off', failuresOff),
        Variant('failures-off-debug', failuresOffDebug),
        Variant('switches-as-text', switchesAsText),
        Variant(
            'sample-antengo',
            () => readContractObject(
                'samples/app-config/antengo_antengo-sellwild-tv.json')),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('events-enabled-object',
            () => build({'EVENTS_ENABLED': <String, dynamic>{}}),
            instancePath: '/EVENTS_ENABLED', keyword: 'type'),
        InvalidVariant('no-code', () => build({'CODE': remove}),
            instancePath: '', keyword: 'required'),
      ];
}

/// One listing (`result.rs[i]`). Base: a real Sellwild cache item,
/// fixtures/listing/valid/sellwild-cache-item.json (bool `shippable`).
class ListingFactory extends JsonObjectFactory {
  ListingFactory()
      : super('listing', 'fixtures/listing/valid/sellwild-cache-item.json');

  /// A bargainhunter item: numeric price and strikePrice, a direct url.
  Map<String, dynamic> bargainhunter() =>
      readContractObject('fixtures/listing/valid/bargainhunter-item.json');

  /// A JSON-RPC item: thumbUrl on photos, username and membershipType.
  Map<String, dynamic> rpcItem() =>
      readContractObject('fixtures/listing/valid/rpc-item.json');

  /// Numbers where the model keeps text (JSON-RPC style), a fractional
  /// price and a text distance.
  Map<String, dynamic> numericFields() => build({
        'id': 1,
        'status': 1,
        'price': 19.5,
        'categoryId': 7,
        'dataSourceId': 31,
        'distance': '2.5',
      });

  /// A numeric distance.
  Map<String, dynamic> numericDistance() => build({'distance': 3});

  /// [has_photo] set to [value], or left out when it is [remove].
  Map<String, dynamic> hasPhoto(Object? value) => build({'has_photo': value});

  /// Invalid: [field] holds an object where the schema wants a scalar.
  Map<String, dynamic> objectIn(String field) => build({
        field: <String, dynamic>{'a': 1}
      });

  /// Invalid: `photos` is text, not an array.
  Map<String, dynamic> photosNotArray() => build({'photos': 'not a list'});

  /// Invalid: `user` is text, not an object.
  Map<String, dynamic> userNotObject() => build({'user': 'not an object'});

  /// Invalid: a bare URL string before the real photo object.
  Map<String, dynamic> photoNotObject() {
    final out = build();
    out['photos'] = ['https://example.com/a.jpg', ...(out['photos'] as List)];
    return out;
  }

  /// Invalid: numeric seller id and membershipType (the schema wants text;
  /// iOS drops the listing).
  Map<String, dynamic> userIdNumber() {
    final out = build();
    out['user'] = {
      ...(out['user'] as Map<String, dynamic>),
      'id': 95090098,
      'membershipType': 5,
    };
    return out;
  }

  @override
  List<Variant> get variants => [
        Variant('default', build),
        Variant('remote-url-null', () => build({'remote_url': null})),
        Variant('bargainhunter', bargainhunter),
        Variant('rpc-item', rpcItem),
        Variant('numeric-id', () => build({'id': 105140234})),
        Variant('numeric-fields', numericFields),
        Variant('numeric-distance', numericDistance),
        Variant('text-shippable', () => build({'shippable': '1'})),
        Variant('has-photo-true', () => hasPhoto(true)),
        Variant('has-photo-text', () => hasPhoto(' TRUE ')),
        Variant('has-photo-number', () => hasPhoto(0)),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('title-number', () => build({'title': 7}),
            instancePath: '/title', keyword: 'type'),
        InvalidVariant('no-photos', () => build({'photos': remove}),
            instancePath: '', keyword: 'required'),
        InvalidVariant('title-object', () => objectIn('title'),
            instancePath: '/title', keyword: 'type'),
        InvalidVariant('id-object', () => objectIn('id'),
            instancePath: '/id', keyword: 'type'),
        InvalidVariant('has-photo-object', () => objectIn('has_photo'),
            instancePath: '/has_photo', keyword: 'type'),
        InvalidVariant('distance-bool', () => build({'distance': true}),
            instancePath: '/distance', keyword: 'type'),
        InvalidVariant('photos-not-array', photosNotArray,
            instancePath: '/photos', keyword: 'type'),
        InvalidVariant('user-not-object', userNotObject,
            instancePath: '/user', keyword: 'type'),
        InvalidVariant('photo-not-object', photoNotObject,
            instancePath: '/photos/0', keyword: 'type'),
        InvalidVariant('user-id-number', userIdNumber,
            instancePath: '/user/id', keyword: 'type'),
      ];
}

/// The listings cache (`GET cache.sellwild.com/listings-*`). Base:
/// fixtures/listings-response/valid/empty-rs.json.
class ListingsResponseFactory extends JsonObjectFactory {
  ListingsResponseFactory()
      : super('listings-response',
            'fixtures/listings-response/valid/empty-rs.json');

  final ListingFactory _listing = ListingFactory();

  /// The base with `result.rs` set to [items] (any JSON values).
  Map<String, dynamic> withItems(List<Object?> items) {
    final out = build();
    (out['result'] as Map<String, dynamic>)['rs'] = items;
    return out;
  }

  /// Invalid: a valid item, then two entries that are not objects.
  Map<String, dynamic> nonObjectEntries() =>
      withItems([_listing.build(), 'x', 7]);

  /// Invalid: a valid item, then two items fromJson cannot read (an object
  /// title, text photos).
  Map<String, dynamic> unreadableItems() => withItems([
        _listing.build(),
        _listing.objectIn('title'),
        _listing.photosNotArray(),
      ]);

  /// Invalid: no `rs`, and a `config` that is not an object.
  Map<String, dynamic> configNumber() => build({
        'result': <String, dynamic>{'config': 5}
      });

  /// Invalid: the body is a JSON array.
  List<Object?> bodyArray() => [build()];

  @override
  List<Variant> get variants => [
        Variant('default', () => withItems([_listing.build()])),
        Variant(
            'mixed-item-types',
            () => withItems([
                  _listing.build(),
                  _listing.build({'remote_url': null}),
                  _listing.bargainhunter(),
                ])),
        Variant('empty', build),
        Variant(
            'sample-weatherbug',
            () => readContractObject('samples/listings-response/'
                'listings-img-data-sm-avif-weatherbug.json')),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('result-null', () => build({'result': null}),
            instancePath: '/result', keyword: 'type'),
        InvalidVariant(
            'item-missing-title',
            () => withItems([
                  _listing.build({'title': remove})
                ]),
            instancePath: '/result/rs/0',
            keyword: 'required'),
        InvalidVariant('non-object-entries', nonObjectEntries,
            instancePath: '/result/rs/1', keyword: 'type'),
        InvalidVariant('unreadable-items', unreadableItems,
            instancePath: '/result/rs/1/title', keyword: 'type'),
        InvalidVariant('config-number', configNumber,
            instancePath: '/result/config', keyword: 'type'),
        InvalidVariant('body-array', bodyArray,
            instancePath: '', keyword: 'type'),
      ];
}

/// A message on the SellwildWidgetBridge / SellwildAdBridge channel. Base:
/// fixtures/bridge-message/valid/listing-click-url.json.
class BridgeMessageFactory extends JsonObjectFactory {
  BridgeMessageFactory()
      : super('bridge-message',
            'fixtures/bridge-message/valid/listing-click-url.json');

  @override
  List<Variant> get variants => [
        Variant('default', build),
        Variant('widget-loaded',
            () => build({'type': 'WIDGET_LOADED', 'url': remove})),
        Variant(
            'error',
            () => build({
                  'type': 'ERROR',
                  'url': remove,
                  'message': 'Uncaught TypeError',
                })),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('unknown-type', () => build({'type': 'NOPE'}),
            instancePath: '/type', keyword: 'const'),
        InvalidVariant('extra-field', () => build({'extra': 1}),
            instancePath: '', keyword: 'additionalProperties'),
      ];
}
