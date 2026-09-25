// SellwildSDK.apply on app configs from AppConfigFactory, SellwildAdStack
// parsing and resolution, and the listings URL fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'factories/shape_factories.dart';

void main() {
  final configs = AppConfigFactory();

  group('SellwildSDK.apply', () {
    const base = SellwildConfig(partnerCode: 'x');

    test('populates identity fields from CDN keys', () {
      final raw = configs.build();

      final merged = SellwildSDK.apply(raw, base, isAndroid: false);

      expect(merged.partnerCode, raw['CODE']);
      expect(merged.slug, raw['SLUG']);
      expect(merged.name, raw['NAME']);
      expect(merged.listingsUrl, raw['LISTINGS']);
    });

    // AD_REFRESH_INTERVAL is milliseconds (code and docs-site agree).
    test('converts AD_REFRESH_INTERVAL milliseconds to Duration', () {
      final merged = SellwildSDK.apply(
          configs.refreshInterval(45000), base,
          isAndroid: false);
      expect(merged.adRefreshInterval, const Duration(seconds: 45));
    });

    test('populates app identity from the shared keys on both OSes', () {
      final raw = configs.appIdentityShared();

      for (final isAndroid in [false, true]) {
        final merged = SellwildSDK.apply(raw, base, isAndroid: isAndroid);
        expect(merged.appBundleId, raw['APP_BUNDLE_ID']);
        expect(merged.appStoreUrl, raw['APP_STORE_URL']);
      }
    });

    test('ignores unknown keys', () {
      final known = SellwildSDK.apply(configs.build(), base, isAndroid: false);

      final merged =
          SellwildSDK.apply(configs.unknownKey(), base, isAndroid: false);

      expect(merged.toJson(), known.toJson());
    });

    test('maps AD_STACK and AD_STACK_BY_ZONE', () {
      final merged =
          SellwildSDK.apply(configs.adStackAliases(), base, isAndroid: false);
      expect(merged.adStack, SellwildAdStack.prebidOnly);
      expect(merged.adStackByZone['43'], SellwildAdStack.gamOnly);
      expect(merged.adStackByZone['44'], SellwildAdStack.both);
    });

    test('leaves adStack null when AD_STACK absent', () {
      final merged =
          SellwildSDK.apply(configs.adStackAbsent(), base, isAndroid: false);
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
