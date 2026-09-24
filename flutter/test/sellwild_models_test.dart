// SellwildListing.fromJson against real captured listings caches
// (contracts/samples), the listing fixtures and ListingFactory. Before the
// fix, fromJson hard-cast every field to its model type and threw TypeError
// on bool `shippable` and numeric `price`/`strikePrice`, so every real cache
// failed. It now reads text, numbers and bools as text, and still throws on
// an object or array where a scalar belongs.

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'factories/contract_factory.dart' show remove;
import 'factories/shape_factories.dart';
import 'support/fixtures.dart';

List<Map<String, dynamic>> itemsOf(Object? body) {
  final result = (body as Map<String, dynamic>)['result'] as Map;
  return (result['rs'] as List).cast<Map<String, dynamic>>();
}

void main() {
  group('SellwildListing.fromJson on real listings caches', () {
    final expectations =
        loadExpectations('listings-response') as Map<String, dynamic>;
    final cases = (expectations['cases'] as List).cast<Map<String, dynamic>>();

    for (final c in cases) {
      final file = c['file'] as String;
      test('$file parses every item', () {
        final items = itemsOf(readContractJson(file));
        final expected = c['expected'] as Map<String, dynamic>;

        final listings = items.map(SellwildListing.fromJson).toList();

        expect(listings, hasLength(expected['items']));
        expect(listings.map((l) => l.id).toList(), expected['ids']);
      });
    }
  });

  final factory = ListingFactory();

  group('SellwildListing.fromJson reads real field types as text', () {
    test('bool shippable (primary Sellwild caches)', () {
      final item =
          itemsOf(loadSample('listings-response', 'listings-img-data-sm'))
              .first;
      expect(item['shippable'], isA<bool>());

      final listing = SellwildListing.fromJson(item);

      expect(listing.shippable, '${item['shippable']}');
      expect(listing.price, item['price']);
      expect(listing.displayPrice, isNotNull);
      expect(listing.user?.id, (item['user'] as Map)['id']);
    });

    test('numeric price and strikePrice (bargainhunter)', () {
      final item =
          itemsOf(loadSample('listings-response', 'bargainhunter')).first;
      expect(item['price'], isA<int>());

      final listing = SellwildListing.fromJson(item);

      expect(listing.price, '${item['price']}');
      expect(listing.strikePrice, '${item['strikePrice']}');
      expect(listing.displayPrice, '${item['price']}');
      expect(listing.url, item['url']);
      expect(listing.user, isNull);
    });

    test('numeric id (JSON-RPC fixture)', () {
      final item = loadFixture('listing', 'numeric-id') as Map<String, dynamic>;

      expect(SellwildListing.fromJson(item).id, '${item['id']}');
    });

    test("text shippable '1' (localized cache)", () {
      final item = loadFixture('listing', 'localized-item-text-shippable')
          as Map<String, dynamic>;

      final listing = SellwildListing.fromJson(item);

      expect(listing.shippable, '1');
      expect(listing.currency, 'USD');
    });

    test('numbers read as text; decimals keep their fraction', () {
      final listing = SellwildListing.fromJson(factory.numericFields());
      final numeric = SellwildListing.fromJson(factory.numericDistance());

      expect(listing.id, '1');
      expect(listing.status, '1');
      expect(listing.price, '19.5');
      expect(listing.displayPrice, '20');
      expect(listing.categoryId, '7');
      expect(listing.dataSourceId, '31');
      expect(listing.distance, 2.5);
      expect(numeric.distance, 3.0);
    });

    test('has_photo: true, non-zero numbers and "true"/"1" text are true', () {
      bool hasPhoto(Object? v) =>
          SellwildListing.fromJson(factory.hasPhoto(v)).hasPhoto;

      expect(hasPhoto(true), isTrue);
      expect(hasPhoto(1), isTrue);
      expect(hasPhoto(2), isTrue);
      expect(hasPhoto('1'), isTrue);
      expect(hasPhoto(' TRUE '), isTrue);
      expect(hasPhoto(false), isFalse);
      expect(hasPhoto(0), isFalse);
      expect(hasPhoto('0'), isFalse);
      expect(hasPhoto('yes'), isFalse);
      expect(hasPhoto(remove), isFalse);
    });

    test('a numeric seller id and membershipType read as text', () {
      final json = factory.userIdNumber();

      final user = SellwildListing.fromJson(json).user!;

      expect(user.id, '95090098');
      expect(user.membershipType, '5');
      expect(user.trustLevel, (json['user'] as Map)['trustLevel']);
    });

    test('JSON-RPC item: photo thumbUrl and every user field', () {
      final json = factory.rpcItem();
      final rpcUser = json['user'] as Map;
      final rpcPhoto = (json['photos'] as List).first as Map;

      final listing = SellwildListing.fromJson(json);
      final user = listing.user!;

      expect(listing.primaryPhoto!.url, rpcPhoto['url']);
      expect(listing.primaryPhoto!.thumbUrl, rpcPhoto['thumbUrl']);
      expect(listing.primaryPhoto!.background, isNull);
      expect(listing.shippable, '0');
      expect(user.firstName, rpcUser['firstName']);
      expect(user.lastName, rpcUser['lastName']);
      expect(user.username, rpcUser['username']);
      expect(user.membershipType, rpcUser['membershipType']);
    });
  });

  group('SellwildListing.fromJson throws on types it cannot read', () {
    // fetchListings catches these per item, reports listings.item.parse and
    // drops the item (sellwild_api_test.dart).
    final invalid = {
      'title-object': factory.objectIn('title'),
      'id-object': factory.objectIn('id'),
      'has-photo-object': factory.objectIn('has_photo'),
      'distance-bool': factory.build({'distance': true}),
      'photos-not-array': factory.photosNotArray(),
      'user-not-object': factory.userNotObject(),
    };

    for (final MapEntry(key: name, value: json) in invalid.entries) {
      test(name, () {
        expect(() => SellwildListing.fromJson(json), throwsA(isA<TypeError>()));
      });
    }

    test('photos: entries that are not objects are skipped (as before)', () {
      final json = factory.photoNotObject();

      final listing = SellwildListing.fromJson(json);

      expect(listing.photos, hasLength((json['photos'] as List).length - 1));
      expect(listing.primaryPhoto!.url,
          ((json['photos'] as List)[1] as Map)['url']);
    });

    test('an empty object gives the documented defaults', () {
      final listing = SellwildListing.fromJson(const {});

      expect(listing.id, '');
      expect(listing.status, '');
      expect(listing.title, '');
      expect(listing.hasPhoto, isFalse);
      expect(listing.photos, isEmpty);
      expect(listing.primaryPhoto, isNull);
      expect(listing.price, isNull);
      expect(listing.displayPrice, isNull);
      expect(listing.createdDate, isNull);
      expect(listing.user, isNull);
      expect(listing.distance, isNull);
    });
  });

  test('SellwildUser and SellwildListingsResponse build directly', () {
    // Built from run-time values (not const) so the constructors are
    // measured.
    final listing = SellwildListing.fromJson(factory.build({'id': '1'}));
    final user = SellwildUser(
      id: listing.id,
      firstName: 'a',
      lastName: 'b',
      username: 'c',
      membershipType: 'd',
      trustLevel: 'e',
    );
    final response = SellwildListingsResponse(
      listings: [listing],
      config: {'id': listing.id},
    );

    expect(user.id, '1');
    expect(response.listings.single, same(listing));
    expect(response.config, {'id': '1'});
    expect(response.widgetCacheVersionId, isNull);
  });
}
