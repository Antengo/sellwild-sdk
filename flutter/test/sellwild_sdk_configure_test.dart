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
        'LISTINGS': 'https://cache.sellwild.com/listings-img-data-sm',
      };

      final merged = SellwildSDK.apply(raw, base);

      expect(merged.partnerCode, 'weatherbug');
      expect(merged.slug, 'weatherbug-main');
      expect(merged.name, 'WeatherBug');
      expect(
        merged.listingsUrl,
        'https://cache.sellwild.com/listings-img-data-sm',
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

    test('maps AD_STACK and AD_STACK_BY_ZONE', () {
      const base = SellwildConfig(partnerCode: 'weatherbug');
      final merged = SellwildSDK.apply({
        'AD_STACK': 'PREBID',
        'AD_STACK_BY_ZONE': {'43': 'GAM', '44': 'both'},
      }, base);
      expect(merged.adStack, SellwildAdStack.prebidOnly);
      expect(merged.adStackByZone['43'], SellwildAdStack.gamOnly);
      expect(merged.adStackByZone['44'], SellwildAdStack.both);
    });

    test('leaves adStack null when AD_STACK absent', () {
      const base = SellwildConfig(partnerCode: 'weatherbug');
      final merged = SellwildSDK.apply({'CODE': 'weatherbug'}, base);
      expect(merged.adStack, isNull);
      expect(merged.adStackByZone, isEmpty);
    });
  });

  group('SellwildAdStack', () {
    test('parse is case and alias tolerant', () {
      expect(SellwildAdStack.parse('BOTH'), SellwildAdStack.both);
      expect(SellwildAdStack.parse('gam-only'), SellwildAdStack.gamOnly);
      expect(SellwildAdStack.parse('google'), SellwildAdStack.gamOnly);
      expect(SellwildAdStack.parse('PREBID_ONLY'), SellwildAdStack.prebidOnly);
      expect(SellwildAdStack.parse('xyz'), isNull);
      expect(SellwildAdStack.parse(42), isNull);
    });

    test('resolve hard-wins on global over per-zone', () {
      const config = SellwildConfig(
        partnerCode: 'weatherbug',
        adStack: SellwildAdStack.prebidOnly,
        adStackByZone: {'43': SellwildAdStack.gamOnly},
      );
      expect(SellwildAdStack.resolve(config, '43'), SellwildAdStack.prebidOnly);
      expect(SellwildAdStack.resolve(config), SellwildAdStack.prebidOnly);
    });

    test('resolve applies per-zone, then defaults to both', () {
      const config = SellwildConfig(
        partnerCode: 'weatherbug',
        adStackByZone: {'43': SellwildAdStack.gamOnly},
      );
      expect(SellwildAdStack.resolve(config, '43'), SellwildAdStack.gamOnly);
      expect(SellwildAdStack.resolve(config, '7'), SellwildAdStack.both);
      expect(SellwildAdStack.resolve(config), SellwildAdStack.both);
    });
  });

  group('SellwildConfig.effectiveListingsUrl', () {
    test('falls back when null', () {
      const config = SellwildConfig(partnerCode: 'weatherbug');
      expect(config.listingsUrl, isNull);
      expect(
        config.effectiveListingsUrl,
        'https://cache.sellwild.com/listings-img-data-sm',
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
