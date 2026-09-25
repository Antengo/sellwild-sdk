import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'factories/shape_factories.dart';

void main() {
  group('SellwildConfig', () {
    test('has correct defaults', () {
      const config = SellwildConfig(
        partnerCode: 'test',
        listingsUrl: 'https://cache.sellwild.com/listings-img-data-sm',
      );

      expect(config.partnerCode, 'test');
      expect(config.titleSize, 16);
      expect(config.fontSize, 13);
      expect(config.boltive, false);
      expect(config.lotame, false);
      expect(config.debug, false);
      expect(config.adRefreshInterval, const Duration(seconds: 30));
      expect(config.hideBannerTop, false);
    });

    test('toJson includes partnerCode and listingsUrl', () {
      const config = SellwildConfig(
        partnerCode: 'mypartner',
        listingsUrl: 'https://cache.sellwild.com/listings-img-data-sm',
      );

      final json = config.toJson();
      expect(json['partnerCode'], 'mypartner');
      expect(json['listingsUrl'], 'https://cache.sellwild.com/listings-img-data-sm');
      expect(json.containsKey('title'), isFalse);
      expect(json['linkText'], 'View all');
    });

    test('toJson includes optional values only when set', () {
      const config = SellwildConfig(
        partnerCode: 'mypartner',
        title: 'Deals',
        linkText: null,
        buyNowText: null,
        gamTag: '/1234/sellwild',
        gptProxyUrl: 'https://gpt.example.com/gpt.js',
      );

      final json = config.toJson();
      expect(json['title'], 'Deals');
      expect(json['gamTag'], '/1234/sellwild');
      expect(json['gptProxyUrl'], 'https://gpt.example.com/gpt.js');
      expect(json.containsKey('linkText'), isFalse);
      expect(json.containsKey('buyNowText'), isFalse);
    });

    test('kill switches default on, rate 1', () {
      const config = SellwildConfig(partnerCode: 'test');

      expect(config.eventsEnabled, isTrue);
      expect(config.failuresEnabled, isTrue);
      expect(config.failuresSampleRate, 1.0);
    });
  });

  test('PrebidServerConfig keeps its values and defaults', () {
    // Built from a run-time list (not const) so the constructor is measured.
    final bidders = ['appnexus', 'rubicon'].toList();
    final server = PrebidServerConfig(
      accountId: 'acct',
      endpoint: 'https://pbs.example.com/openrtb2/auction',
      bidders: bidders,
    );

    expect(server.accountId, 'acct');
    expect(server.bidders, bidders);
    expect(server.timeout, 1500);
    expect(server.syncEndpoint, isNull);
  });

  group('SellwildAdSize', () {
    test('banner dimensions', () {
      expect(SellwildAdSize.banner320x50.width, 320);
      expect(SellwildAdSize.banner320x50.height, 50);
      expect(SellwildAdSize.mrec300x250.width, 300);
      expect(SellwildAdSize.mrec300x250.height, 250);
    });

    test('label is WIDTHxHEIGHT', () {
      expect(SellwildAdSize.values.map((s) => s.label),
          ['320x50', '300x250', '728x90', '300x600', '160x600']);
    });
  });

  group('SellwildListing', () {
    final listings = ListingFactory();

    test('parses from JSON', () {
      final json = listings.build();

      final listing = SellwildListing.fromJson(json);

      expect(listing.id, json['id']);
      expect(listing.title, json['title']);
      expect(listing.displayPrice, json['price']);
      expect(listing.primaryPhoto?.url, (json['photos'] as List).first['url']);
    });

    test('displayPrice rounds a fractional price', () {
      final listing = SellwildListing.fromJson(listings.fractionalPrice());
      expect(listing.displayPrice, '50');
    });

    test('displayPrice returns null for zero price', () {
      final listing = SellwildListing.fromJson(listings.zeroPrice());
      expect(listing.displayPrice, null);
    });
  });
}
