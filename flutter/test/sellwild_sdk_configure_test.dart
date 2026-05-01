import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

void main() {
  group('SellwildSDK.apply', () {
    test('populates identity fields from CDN keys', () {
      const base = SellwildConfig(partnerCode: 'weatherbug');
      final raw = {
        'CODE': 'weatherbug',
        'SLUG': 'weatherbug-main',
        'NAME': 'WeatherBug',
        'LISTINGS': 'https://api.sellwild.com/widget/listings?partner=weatherbug',
      };

      final merged = SellwildSDK.apply(raw, base);

      expect(merged.partnerCode, 'weatherbug');
      expect(merged.slug, 'weatherbug-main');
      expect(merged.name, 'WeatherBug');
      expect(
        merged.listingsUrl,
        'https://api.sellwild.com/widget/listings?partner=weatherbug',
      );
    });

    test('converts AD_REFRESH_INTERVAL seconds to Duration', () {
      const base = SellwildConfig(partnerCode: 'weatherbug');
      final merged = SellwildSDK.apply({'AD_REFRESH_INTERVAL': 30}, base);
      expect(merged.adRefreshInterval, const Duration(seconds: 30));
    });

    test('populates app identity', () {
      const base = SellwildConfig(partnerCode: 'weatherbug');
      final merged = SellwildSDK.apply({
        'APP_BUNDLE_ID': 'com.aws.android',
        'APP_STORE_URL': 'https://apps.apple.com/app/id123',
      }, base);
      expect(merged.appBundleId, 'com.aws.android');
      expect(merged.appStoreUrl, 'https://apps.apple.com/app/id123');
    });

    test('ignores unknown keys', () {
      const base = SellwildConfig(partnerCode: 'weatherbug');
      final merged = SellwildSDK.apply({'FUTURE_FEATURE_FLAG': true}, base);
      expect(merged.partnerCode, 'weatherbug');
    });
  });

  group('SellwildConfig.effectiveListingsUrl', () {
    test('falls back when null', () {
      const config = SellwildConfig(partnerCode: 'weatherbug');
      expect(config.listingsUrl, isNull);
      expect(
        config.effectiveListingsUrl,
        'https://api.sellwild.com/widget/listings?partner=weatherbug',
      );
    });

    test('prefers explicit value', () {
      const config = SellwildConfig(
        partnerCode: 'weatherbug',
        listingsUrl: 'https://custom.example.com/listings',
      );
      expect(config.effectiveListingsUrl, 'https://custom.example.com/listings');
    });
  });
}
