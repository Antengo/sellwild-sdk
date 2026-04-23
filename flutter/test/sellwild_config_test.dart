import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

void main() {
  group('SellwildConfig', () {
    test('has correct defaults', () {
      const config = SellwildConfig(
        partnerCode: 'test',
        listingsUrl: 'https://api.sellwild.com/widget/listings?partner=test',
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
        listingsUrl: 'https://api.sellwild.com/widget/listings?partner=mypartner',
      );

      final json = config.toJson();
      expect(json['partnerCode'], 'mypartner');
      expect(json['listingsUrl'], contains('mypartner'));
    });
  });

  group('SellwildAdSize', () {
    test('banner dimensions', () {
      expect(SellwildAdSize.banner320x50.width, 320);
      expect(SellwildAdSize.banner320x50.height, 50);
      expect(SellwildAdSize.mrec300x250.width, 300);
      expect(SellwildAdSize.mrec300x250.height, 250);
    });
  });

  group('SellwildListing', () {
    test('parses from JSON', () {
      final json = {
        'id': '123',
        'status': '1',
        'title': 'Test Listing',
        'price': '49.99',
        'currency': 'USD',
        'photos': [
          {'url': 'https://example.com/photo.jpg', 'thumbUrl': 'https://example.com/thumb.jpg'}
        ],
      };

      final listing = SellwildListing.fromJson(json);
      expect(listing.id, '123');
      expect(listing.title, 'Test Listing');
      expect(listing.displayPrice, '50');
      expect(listing.primaryPhoto?.url, 'https://example.com/photo.jpg');
    });

    test('displayPrice returns null for zero price', () {
      const listing = SellwildListing(id: '1', status: '1', title: 'Free', price: '0');
      expect(listing.displayPrice, null);
    });
  });
}
