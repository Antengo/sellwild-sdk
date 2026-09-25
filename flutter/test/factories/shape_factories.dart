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

  /// The three switch keys left out (each means "keep the default").
  Map<String, dynamic> switchesAbsent() => build({
        'EVENTS_ENABLED': remove,
        'FAILURES_ENABLED': remove,
        'FAILURES_SAMPLE_RATE': remove,
      });

  /// Invalid: the three switch keys as JSON null, which the schema rejects
  /// and the SDK reads as absent (FAILURES.md 12.5).
  Map<String, dynamic> switchesNull() => build({
        'EVENTS_ENABLED': null,
        'FAILURES_ENABLED': null,
        'FAILURES_SAMPLE_RATE': null,
      });

  /// Switch values that need coercing: padded text, a number, and a rate
  /// that is text but not a decimal (so it means 1).
  Map<String, dynamic> switchesCoerced() => build({
        'EVENTS_ENABLED': ' OFF ',
        'FAILURES_ENABLED': 0,
        'FAILURES_SAMPLE_RATE': '50%',
      });

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
  /// it decodes to Infinity, which Duration cannot hold, so apply threw
  /// before the A9 fix.
  String refreshIntervalOverflowText() => overflowText('AD_REFRESH_INTERVAL');

  /// The default config as response text with [key] set to 1e400, which
  /// decodes to Infinity. Text, because jsonEncode cannot write Infinity.
  String overflowText(String key) {
    final text = jsonEncode(build({key: 0}));
    return text.replaceFirst('"$key":0', '"$key":1e400');
  }

  /// Web keys the SDK passes through, and a LINK_TEXT that is HTML with
  /// double quotes (fixtures/app-config/valid/web-passthrough-keys.json).
  Map<String, dynamic> webPassthrough() =>
      readContractObject('fixtures/app-config/valid/web-passthrough-keys.json');

  /// The CMS "use the default" value for LISTINGS: ''.
  Map<String, dynamic> listingsEmpty() => build({'LISTINGS': ''});

  /// A LISTINGS text Uri.parse rejects (an IPv6 host without its ']'). The
  /// schema takes any text.
  Map<String, dynamic> listingsMalformed() =>
      build({'LISTINGS': 'https://[::1/listings-weatherbug'});

  /// AD_REFRESH_INTERVAL written in seconds (30), a real CMS mistake
  /// (fixtures/app-config/valid/refresh-interval-seconds-style.json).
  Map<String, dynamic> refreshSecondsStyle() => readContractObject(
      'fixtures/app-config/valid/refresh-interval-seconds-style.json');

  /// Unset ad stacks as the CMS writes them: '' for both keys
  /// (fixtures/app-config/valid/by-zone-maps-empty.json).
  Map<String, dynamic> adStacksEmpty() =>
      readContractObject('fixtures/app-config/valid/by-zone-maps-empty.json');

  /// Contract-valid values Flutter does not read (known drift, recorded in
  /// contracts/expectations/drift/flutter.json): numeric zone ids, an
  /// integral double for an integer key, a fractional MARGIN_BOTTOM and
  /// text IAB_CATS.
  Map<String, dynamic> unreadDrift() => build({
        'BANNER_ZID': 43,
        'BOTTOM_BANNER_ZID': 44,
        'MOBILE_BANNER_ZID': 45,
        'AD_REFRESH_MAX': 5.0,
        'MARGIN_BOTTOM': 14.5,
        'IAB_CATS': 'IAB15, IAB7',
      });

  /// Two unknown keys that kebab-case to the same attribute name.
  Map<String, dynamic> attributeNameCollision() =>
      build({'weatherbug_only': 'first', 'WEATHERBUG-ONLY': 'second'});

  /// Only the shared APP_BUNDLE_ID and APP_STORE_URL: the per-OS keys are
  /// left out, so both OSes read the shared ones.
  Map<String, dynamic> appIdentityShared() => build({
        'APP_BUNDLE_ID_IOS': remove,
        'APP_BUNDLE_ID_ANDROID': remove,
        'APP_STORE_URL_IOS': remove,
        'APP_STORE_URL_ANDROID': remove,
      });

  /// A key no SDK version reads yet (the schema allows extra keys).
  Map<String, dynamic> unknownKey() => build({'FUTURE_FEATURE_FLAG': true});

  /// Ad stack modes written as aliases and in other cases.
  Map<String, dynamic> adStackAliases() => build({
        'AD_STACK': 'PREBID',
        'AD_STACK_BY_ZONE': <String, dynamic>{'43': 'GAM', '44': 'both'},
      });

  /// No AD_STACK and no AD_STACK_BY_ZONE.
  Map<String, dynamic> adStackAbsent() =>
      build({'AD_STACK': remove, 'AD_STACK_BY_ZONE': remove});

  /// Invalid: fields of the wrong JSON type, one of each reader kind.
  Map<String, dynamic> mistypedFields() => build({
        'TITLE': 7,
        'AD_REFRESH_MAX': '5',
        'TCF_VERSION': 2.5,
        'DEBUG': 'true',
        'MOBILE_ZID': 'weatherbug-mobile-300x250',
        'COLORS': ['#111111', 3],
        'IAB_CATS': ['IAB15', false],
        'BANNER_ZID': true,
        'EVENTS_ENABLED': <String, dynamic>{},
        'FAILURES_SAMPLE_RATE': <Object?>[],
      });

  /// Invalid: color keys that are not text.
  Map<String, dynamic> colorsMistyped() => build({
        'LINK_COLOR': 234966,
        'PRICE_COLOR': <String, dynamic>{'r': 1},
      });

  /// Unknown ad stack modes: an unknown AD_STACK text and one unknown mode in
  /// AD_STACK_BY_ZONE (both are text, so the schema accepts them).
  Map<String, dynamic> adStackUnknown() => build({
        'AD_STACK': 'amazon',
        'AD_STACK_BY_ZONE': <String, dynamic>{'43': 'gamOnly', '280': 'nope'},
      });

  /// Invalid: AD_STACK not text and AD_STACK_BY_ZONE a list.
  Map<String, dynamic> adStackMistyped() => build({
        'AD_STACK': 1,
        'AD_STACK_BY_ZONE': <Object?>['gamOnly'],
      });

  /// Invalid: PREBID_SRC is JSON null (the WebView must not get "null").
  Map<String, dynamic> prebidSrcNull() => build({'PREBID_SRC': null});

  /// Invalid: AD_REFRESH_INTERVAL as text.
  Map<String, dynamic> refreshIntervalText() =>
      build({'AD_REFRESH_INTERVAL': '30000'});

  /// AD_REFRESH_INTERVAL set to [ms]. The schema only says number, so any
  /// finite value is valid: 1e300 and -1e300 are beyond what a Duration
  /// holds, 999 and 1000 sit on the seconds-style boundary, 0 is below it
  /// but not seconds-style, and 1500.6 has a fraction.
  Map<String, dynamic> refreshInterval(num ms) =>
      build({'AD_REFRESH_INTERVAL': ms});

  /// Invalid: CODE is '' (schema minLength 1)
  /// (fixtures/app-config/invalid/code-empty.json is the minimal case).
  Map<String, dynamic> codeEmpty() => build({'CODE': ''});

  /// GAM '' (contract-valid: no ad unit path).
  Map<String, dynamic> gamEmpty() => build({'GAM': ''});

  /// Invalid: typed keys set to JSON null, which the schema rejects and the
  /// SDK reads as absent (FAILURES.md 12.5).
  Map<String, dynamic> typedKeysNull() => build({
        for (final key in [
          'TITLE',
          'COLORS',
          'DEBUG',
          'AD_REFRESH_MAX',
          'AD_REFRESH_INTERVAL',
          'AD_STACK',
          'AD_STACK_BY_ZONE',
          'LINK_COLOR',
          'EVENTS_ENABLED',
        ])
          key: null,
      });

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
        Variant('web-passthrough', webPassthrough),
        Variant('listings-empty', listingsEmpty),
        Variant('listings-malformed', listingsMalformed),
        Variant('refresh-seconds-style', refreshSecondsStyle),
        Variant('ad-stacks-empty', adStacksEmpty),
        Variant('unread-drift', unreadDrift),
        Variant('ad-stack-unknown', adStackUnknown),
        Variant('attribute-name-collision', attributeNameCollision),
        Variant('refresh-interval-huge', () => refreshInterval(1e300)),
        Variant(
            'refresh-interval-huge-negative', () => refreshInterval(-1e300)),
        Variant('refresh-interval-999', () => refreshInterval(999)),
        Variant('refresh-interval-1000', () => refreshInterval(1000)),
        Variant('refresh-interval-zero', () => refreshInterval(0)),
        Variant('refresh-interval-fractional', () => refreshInterval(1500.6)),
        Variant('refresh-interval-45000', () => refreshInterval(45000)),
        Variant('app-identity-shared', appIdentityShared),
        Variant('unknown-key', unknownKey),
        Variant('ad-stack-aliases', adStackAliases),
        Variant('ad-stack-absent', adStackAbsent),
        Variant('gam-empty', gamEmpty),
        Variant('switches-absent', switchesAbsent),
        Variant('switches-coerced', switchesCoerced),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('events-enabled-object',
            () => build({'EVENTS_ENABLED': <String, dynamic>{}}),
            instancePath: '/EVENTS_ENABLED', keyword: 'type'),
        InvalidVariant('no-code', () => build({'CODE': remove}),
            instancePath: '', keyword: 'required'),
        InvalidVariant('mistyped-fields', mistypedFields,
            instancePath: '/TITLE', keyword: 'type'),
        InvalidVariant('colors-mistyped', colorsMistyped,
            instancePath: '/LINK_COLOR', keyword: 'type'),
        InvalidVariant('ad-stack-mistyped', adStackMistyped,
            instancePath: '/AD_STACK', keyword: 'type'),
        InvalidVariant('prebid-src-null', prebidSrcNull,
            instancePath: '/PREBID_SRC', keyword: 'type'),
        InvalidVariant('refresh-interval-text', refreshIntervalText,
            instancePath: '/AD_REFRESH_INTERVAL', keyword: 'type'),
        InvalidVariant('code-empty', codeEmpty,
            instancePath: '/CODE', keyword: 'minLength'),
        InvalidVariant('typed-keys-null', typedKeysNull,
            instancePath: '/TITLE', keyword: 'type'),
        InvalidVariant('switches-null', switchesNull,
            instancePath: '/FAILURES_SAMPLE_RATE', keyword: 'type'),
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

  /// The item priced in [currency] (an ISO code, or other text).
  Map<String, dynamic> withCurrency(String currency) =>
      build({'currency': currency});

  /// A title longer than a card shows (60 characters).
  Map<String, dynamic> longTitle() => build({
        'title': '2021 Lexus UX UX 200 F Sport AWD with Premium Package, '
            'Navigation and Low Miles',
      });

  /// A title of exactly [length] characters (the long title's text,
  /// repeated as needed), for the card's 60-character cut. No photos, so
  /// widget tests load no image.
  Map<String, dynamic> titleOfLength(int length) {
    final text = longTitle()['title'] as String;
    return build({
      'title': (text * (length ~/ text.length + 1)).substring(0, length),
      'photos': <Object?>[],
    });
  }

  /// A fractional price: the badge rounds it.
  Map<String, dynamic> fractionalPrice() => build({'price': '49.99'});

  /// No price: the card shows no badge.
  Map<String, dynamic> noPrice() => build({'price': remove});

  /// A price that is text, not a number: no badge, reported by the card.
  Map<String, dynamic> priceText() =>
      build({'price': 'Call for price', 'photos': <Object?>[]});

  /// A zero price: the card shows no badge either.
  Map<String, dynamic> zeroPrice() => build({'price': '0'});

  /// A price that is [blank] text ('' or spaces): no badge, and not a
  /// wrong price, so not reported.
  Map<String, dynamic> blankPrice(String blank) =>
      build({'price': blank, 'photos': <Object?>[]});

  /// A price that is text the schema allows but that is no finite number:
  /// 'NaN', 'Infinity', '-Infinity' or '1e400' (too big for a double).
  /// No photos, so widget tests load no image.
  Map<String, dynamic> nonFinitePrice(String text) =>
      build({'price': text, 'photos': <Object?>[]});

  /// No photos: the card shows the placeholder.
  Map<String, dynamic> noPhotos() => build({'photos': <Object?>[]});

  /// Invalid: no `photos` key (the schema requires it; fromJson reads it as
  /// none).
  Map<String, dynamic> withoutPhotos() => build({'photos': remove});

  /// No photos, priced in [currency] (no image load in widget tests).
  Map<String, dynamic> noPhotosIn(String currency) =>
      build({'photos': <Object?>[], 'currency': currency});

  /// A photo with an empty URL: the card shows the placeholder.
  Map<String, dynamic> photoEmptyUrl() => build({
        'photos': [
          <String, dynamic>{'url': ''}
        ]
      });

  /// Invalid: [field] holds an object where the schema wants a scalar.
  Map<String, dynamic> objectIn(String field) => build({
        field: <String, dynamic>{'a': 1}
      });

  /// Invalid: `photos` is text, not an array.
  Map<String, dynamic> photosNotArray() => build({'photos': 'not a list'});

  /// Invalid: `user` is text, not an object.
  Map<String, dynamic> userNotObject() => build({'user': 'not an object'});

  /// Invalid: a bare URL string before the real photo object.
  Map<String, dynamic> photoNotObject() => photosNotObject(1);

  /// Invalid: [count] bare URL strings before the real photo object.
  Map<String, dynamic> photosNotObject(int count) {
    final out = build();
    out['photos'] = [
      for (var i = 0; i < count; i++) 'https://example.com/$i.jpg',
      ...(out['photos'] as List),
    ];
    return out;
  }

  /// Invalid: photos entries that are neither objects nor text (a number,
  /// null and an array) before the real photo object.
  Map<String, dynamic> photosOfOtherKinds() {
    final out = build();
    out['photos'] = [5, null, <Object?>[], ...(out['photos'] as List)];
    return out;
  }

  /// Invalid: an item fromJson cannot read (an object title) that also has
  /// two photos entries that are not objects.
  Map<String, dynamic> unreadableWithNonObjectPhotos() =>
      photosNotObject(2)..['title'] = <String, dynamic>{'a': 1};

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
        Variant('currency-eur', () => withCurrency('EUR')),
        Variant('currency-unknown', () => withCurrency('JPY')),
        Variant('currency-text', () => withCurrency('dollars')),
        Variant('currency-lower-case', () => withCurrency('jpy')),
        Variant('currency-mixed-case', () => withCurrency('Usd')),
        Variant('currency-mixed-case-eur', () => withCurrency('eUR')),
        Variant('currency-empty', () => withCurrency('')),
        Variant('long-title', longTitle),
        Variant('title-60', () => titleOfLength(60)),
        Variant('title-61', () => titleOfLength(61)),
        Variant('no-price', noPrice),
        Variant('zero-price', zeroPrice),
        Variant('price-fractional', fractionalPrice),
        Variant('price-empty', () => blankPrice('')),
        Variant('price-spaces', () => blankPrice('  ')),
        Variant('price-text', priceText),
        Variant('price-nan', () => nonFinitePrice('NaN')),
        Variant('price-infinity', () => nonFinitePrice('Infinity')),
        Variant('price-minus-infinity', () => nonFinitePrice('-Infinity')),
        Variant('price-overflow', () => nonFinitePrice('1e400')),
        Variant('no-photos', noPhotos),
        Variant('no-photos-gbp', () => noPhotosIn('GBP')),
        Variant('no-photos-jpy', () => noPhotosIn('JPY')),
        Variant('no-photos-currency-empty', () => noPhotosIn('')),
        Variant('photo-empty-url', photoEmptyUrl),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('title-number', () => build({'title': 7}),
            instancePath: '/title', keyword: 'type'),
        InvalidVariant('no-photos', withoutPhotos,
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
        InvalidVariant('photos-not-object-2', () => photosNotObject(2),
            instancePath: '/photos/1', keyword: 'type'),
        InvalidVariant('photos-other-kinds', photosOfOtherKinds,
            instancePath: '/photos/0', keyword: 'type'),
        InvalidVariant(
            'title-object-photos-not-object', unreadableWithNonObjectPhotos,
            instancePath: '/title', keyword: 'type'),
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

  /// Invalid: a valid item, then one entry that is not an object.
  Map<String, dynamic> oneNonObjectEntry() =>
      withItems([_listing.build(), 'x']);

  /// Invalid: a valid item, then two items fromJson cannot read (an object
  /// title, text photos).
  Map<String, dynamic> unreadableItems() => withItems([
        _listing.build(),
        _listing.objectIn('title'),
        _listing.photosNotArray(),
      ]);

  /// Invalid: the two unreadable items of [unreadableItems] in the other
  /// order (text photos first, then an object title).
  Map<String, dynamic> unreadableItemsSwapped() => withItems([
        _listing.build(),
        _listing.photosNotArray(),
        _listing.objectIn('title'),
      ]);

  /// Invalid: an item whose photos hold a number, null and an array before
  /// its real photo, then a clean item.
  Map<String, dynamic> otherKindPhotos() => withItems([
        _listing.photosOfOtherKinds(),
        _listing.build(),
      ]);

  /// Invalid: one item without `photos` (fromJson reads it as none).
  Map<String, dynamic> itemWithoutPhotos() =>
      withItems([_listing.withoutPhotos()]);

  /// Invalid: an item with two photos entries that are not objects, one
  /// with one (fromJson skips them), then a clean item: 3 in all.
  Map<String, dynamic> nonObjectPhotos() => withItems([
        _listing.photosNotObject(2),
        _listing.photoNotObject(),
        _listing.build(),
      ]);

  /// Invalid: an item with one photos entry that is not an object, then a
  /// clean item: 1 in all.
  Map<String, dynamic> oneNonObjectPhoto() => withItems([
        _listing.photoNotObject(),
        _listing.build(),
      ]);

  /// Invalid: a valid item, then an item fromJson cannot read (an object
  /// title) whose photos also hold two entries that are not objects.
  Map<String, dynamic> unreadableItemWithNonObjectPhotos() => withItems([
        _listing.build(),
        _listing.unreadableWithNonObjectPhotos(),
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
        InvalidVariant('one-non-object-entry', oneNonObjectEntry,
            instancePath: '/result/rs/1', keyword: 'type'),
        InvalidVariant('unreadable-items', unreadableItems,
            instancePath: '/result/rs/1/title', keyword: 'type'),
        InvalidVariant('unreadable-items-swapped', unreadableItemsSwapped,
            instancePath: '/result/rs/1/photos', keyword: 'type'),
        InvalidVariant('other-kind-photos', otherKindPhotos,
            instancePath: '/result/rs/0/photos/0', keyword: 'type'),
        InvalidVariant('item-without-photos', itemWithoutPhotos,
            instancePath: '/result/rs/0', keyword: 'required'),
        InvalidVariant('non-object-photos', nonObjectPhotos,
            instancePath: '/result/rs/0/photos/0', keyword: 'type'),
        InvalidVariant('one-non-object-photo', oneNonObjectPhoto,
            instancePath: '/result/rs/0/photos/0', keyword: 'type'),
        InvalidVariant('unreadable-item-non-object-photos',
            unreadableItemWithNonObjectPhotos,
            instancePath: '/result/rs/1/title', keyword: 'type'),
        InvalidVariant('config-number', configNumber,
            instancePath: '/result/config', keyword: 'type'),
        InvalidVariant('body-array', bodyArray,
            instancePath: '', keyword: 'type'),
      ];
}

/// A message on the SellwildWidgetBridge channel. Base:
/// fixtures/bridge-message/valid/listing-click-url.json.
class BridgeMessageFactory extends JsonObjectFactory {
  BridgeMessageFactory()
      : super('bridge-message',
            'fixtures/bridge-message/valid/listing-click-url.json');

  final ListingFactory _listing = ListingFactory();

  /// A contracts bridge-message fixture by name ([valid] or invalid).
  Map<String, dynamic> fixture(String name, {bool valid = true}) =>
      readContractObject(
          'fixtures/bridge-message/${valid ? 'valid' : 'invalid'}/$name.json');

  /// `WIDGET_LOADED`.
  Map<String, dynamic> widgetLoaded() =>
      build({'type': 'WIDGET_LOADED', 'url': remove});

  /// `ERROR` with the page's error text.
  Map<String, dynamic> error() => build({
        'type': 'ERROR',
        'url': remove,
        'message': 'Uncaught TypeError',
      });

  /// `ERROR` without a message.
  Map<String, dynamic> errorNoMessage() =>
      build({'type': 'ERROR', 'url': remove});

  /// `LISTING_CLICK` with a stub listing and its URL.
  Map<String, dynamic> listingStub() => fixture('listing-click-stub');

  /// `LISTING_CLICK` with a real cache item as the listing.
  Map<String, dynamic> listingItem() =>
      build({'url': remove, 'listing': _listing.build()});

  /// `LISTING_CLICK` with a cache item whose photos hold two entries that
  /// are not objects. The schema only says the listing is an object.
  Map<String, dynamic> listingNonObjectPhotos() =>
      build({'url': remove, 'listing': _listing.photosNotObject(2)});

  /// `LISTING_CLICK` with a cache item whose photos hold one entry that is
  /// not an object.
  Map<String, dynamic> listingOneNonObjectPhoto() =>
      build({'url': remove, 'listing': _listing.photoNotObject()});

  /// `LISTING_CLICK` with a cache item whose photos hold a number, null and
  /// an array.
  Map<String, dynamic> listingOtherKindPhotos() =>
      build({'url': remove, 'listing': _listing.photosOfOtherKinds()});

  /// `LISTING_CLICK` with a listing fromJson cannot read (an object title).
  /// The schema only says the listing is an object.
  Map<String, dynamic> listingUnreadable() =>
      build({'url': remove, 'listing': _listing.objectIn('title')});

  /// `LISTING_CLICK` with neither a listing nor a URL.
  Map<String, dynamic> listingClickEmpty() => build({'url': remove});

  /// `AD_IMPRESSION` with a text zone id.
  Map<String, dynamic> adImpression() => fixture('ad-impression-text-zone');

  /// `AD_IMPRESSION` with a numeric zone id (contract-valid; Flutter's
  /// onAdImpression takes text).
  Map<String, dynamic> adImpressionNumberZone() =>
      fixture('ad-impression-number-zone');

  /// `AD_IMPRESSION` without a zone id.
  Map<String, dynamic> adImpressionNoZone() => fixture('ad-impression-no-zone');

  /// Invalid: an unknown type.
  Map<String, dynamic> unknownType() => build({'type': 'NOPE'});

  /// Invalid: no type.
  Map<String, dynamic> missingType() => fixture('missing-type', valid: false);

  /// Invalid: a numeric type.
  Map<String, dynamic> typeNumber() => build({'type': 5});

  /// Invalid: an ERROR whose message is a number.
  Map<String, dynamic> errorMessageNumber() =>
      fixture('error-message-number', valid: false);

  /// Invalid: a LISTING_CLICK whose listing is text.
  Map<String, dynamic> listingNotObject() =>
      build({'url': remove, 'listing': 'not an object'});

  /// Invalid: a LISTING_CLICK whose url is a number.
  Map<String, dynamic> urlNumber() => build({'url': 5});

  /// Invalid: an AD_IMPRESSION whose zoneId is an object.
  Map<String, dynamic> zoneIdObject() => build({
        'type': 'AD_IMPRESSION',
        'url': remove,
        'zoneId': <String, dynamic>{'id': 43},
      });

  /// Invalid: the message is a JSON array, not an object.
  List<Object?> bodyArray() => [widgetLoaded()];

  @override
  List<Variant> get variants => [
        Variant('default', build),
        Variant('widget-loaded', widgetLoaded),
        Variant('error', error),
        Variant('error-no-message', errorNoMessage),
        Variant('listing-stub', listingStub),
        Variant('listing-item', listingItem),
        Variant('listing-unreadable', listingUnreadable),
        Variant('listing-non-object-photos', listingNonObjectPhotos),
        Variant('listing-one-non-object-photo', listingOneNonObjectPhoto),
        Variant('listing-other-kind-photos', listingOtherKindPhotos),
        Variant('listing-click-empty', listingClickEmpty),
        Variant('ad-impression', adImpression),
        Variant('ad-impression-number-zone', adImpressionNumberZone),
        Variant('ad-impression-no-zone', adImpressionNoZone),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('unknown-type', unknownType,
            instancePath: '/type', keyword: 'const'),
        InvalidVariant('extra-field', () => build({'extra': 1}),
            instancePath: '', keyword: 'additionalProperties'),
        InvalidVariant('missing-type', missingType,
            instancePath: '', keyword: 'required'),
        InvalidVariant('type-number', typeNumber,
            instancePath: '/type', keyword: 'const'),
        InvalidVariant('error-message-number', errorMessageNumber,
            instancePath: '/message', keyword: 'type'),
        InvalidVariant('listing-not-object', listingNotObject,
            instancePath: '/listing', keyword: 'type'),
        InvalidVariant('url-number', urlNumber,
            instancePath: '/url', keyword: 'type'),
        InvalidVariant('zone-id-object', zoneIdObject,
            instancePath: '/zoneId', keyword: 'type'),
        InvalidVariant('body-array', bodyArray,
            instancePath: '', keyword: 'type'),
      ];
}

/// A message on the SellwildAdBridge channel (SellwildBanner). There is no
/// contracts schema for it yet (bridge-message.schema.json covers
/// SellwildWidgetBridge only), so it cannot be validated like the others:
/// each message is the one the banner page's own script posts,
/// `notify(type, data)` sending `Object.assign({ type: type }, data || {})`,
/// and sellwild_widget_test.dart and widget_html_test.dart check the page
/// still does that.
class AdBridgeMessageFactory {
  /// What `notify('impression')` posts after an ad renders.
  Map<String, dynamic> impression() => {'type': 'impression'};

  /// `notify('click')`. The handler accepts it; the page never posts it.
  Map<String, dynamic> click() => {'type': 'click'};

  /// What a script's `s.onerror` posts when it fails to load,
  /// `notify('scriptError', { src: s.src })`: here the zone script of a
  /// 300x250 banner for zone 43.
  Map<String, dynamic> scriptError(
          {String src =
              'https://bidstream.sellwild.com/ads?zone=43&w=300&h=250'}) =>
      {'type': 'scriptError', 'src': src};

  /// What `notify('slotError')` posts when defineSlot returns null.
  Map<String, dynamic> slotErrorNull() => {'type': 'slotError'};

  /// What the defineSlot catch posts,
  /// `notify('slotError', { message: String((e && e.message) || e) })`.
  Map<String, dynamic> slotErrorThrown() => {
        'type': 'slotError',
        'message': 'Cannot read properties of undefined (reading "slice")',
      };

  /// A type the handler does not know.
  Map<String, dynamic> unknownType() => {'type': 'viewable'};

  /// No type.
  Map<String, dynamic> missingType() => <String, dynamic>{};

  /// A scriptError without its URL (the page always sends one).
  Map<String, dynamic> scriptErrorNoSrc() => {'type': 'scriptError'};

  /// A slotError whose message is a number (the page sends text).
  Map<String, dynamic> slotErrorMessageNumber() =>
      {'type': 'slotError', 'message': 5};
}
