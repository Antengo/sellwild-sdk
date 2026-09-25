// SellwildSDK.apply: what it keeps from the remote config, and every value
// it cannot use reported once through logFailure (config.field.invalid,
// config.color.invalid, config.adstack.invalid,
// config.refresh_interval.invalid).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/remote_config.dart';
import 'package:sellwild_sdk/src/widget_html.dart' show buildWidgetHtml;

import 'factories/shape_factories.dart';
import 'support/failure_capture.dart';
import 'support/fixtures.dart';
import 'support/http_mocks.dart';

void main() {
  final configs = AppConfigFactory();
  const base = SellwildConfig(partnerCode: 'x');

  group('A9 fixes', () {
    test('an infinite AD_REFRESH_INTERVAL no longer loses the whole config',
        () async {
      final failures = captureFailures();
      final text = configs.refreshIntervalOverflowText();
      final raw = jsonDecode(text) as Map<String, dynamic>;

      final config = SellwildSDK.apply(raw, base, isAndroid: false);

      expect(config.partnerCode, raw['CODE']);
      expect(config.slug, raw['SLUG']);
      expect(config.adRefreshInterval, base.adRefreshInterval);
      expect(actionsOf(failures), ['config.field.invalid']);
      expect(failures.single.label, 'remoteConfig');
      expect(
          failures.single.attributes['msg'], contains('AD_REFRESH_INTERVAL'));
    });

    test('a huge AD_REFRESH_INTERVAL does not wrap into a negative Duration',
        () {
      final failures = captureFailures();
      final raw = configs.refreshInterval(1e300);

      final config = SellwildSDK.apply(raw, base, isAndroid: false);

      // Before: 1e300.round() * 1000 wrapped to a -1 ms interval.
      expect(config.adRefreshInterval, base.adRefreshInterval);
      expect(config.slug, raw['SLUG']);
      expect(actionsOf(failures), ['config.field.invalid']);
      expect(failures.single.attributes['msg'],
          'AD_REFRESH_INTERVAL is out of range');
    });

    test('a huge negative AD_REFRESH_INTERVAL is out of range too', () {
      final failures = captureFailures();
      final raw = configs.refreshInterval(-1e300);

      final config = SellwildSDK.apply(raw, base, isAndroid: false);

      // -1e300 wraps the same way; only its size matters.
      expect(config.adRefreshInterval, base.adRefreshInterval);
      expect(config.slug, raw['SLUG']);
      expect(actionsOf(failures), ['config.field.invalid']);
      expect(failures.single.attributes['msg'],
          'AD_REFRESH_INTERVAL is out of range');
    });

    test("CODE '' keeps the partner code configure was given", () {
      final failures = captureFailures();
      const partner = SellwildConfig(partnerCode: 'weatherbug');
      final raw = configs.codeEmpty();

      final config = SellwildSDK.apply(raw, partner, isAndroid: false);

      // Before: partnerCode became '', so events and failures lost the
      // partner. Core also keeps the base for ''.
      expect(config.partnerCode, 'weatherbug');
      expect(config.slug, raw['SLUG']);
      expect(actionsOf(failures), ['config.field.invalid']);
      expect(failures.single.attributes['msg'], 'CODE is empty');
    });

    test("GAM '' is no ad unit: the base tag is kept, nothing reported", () {
      final failures = captureFailures();
      const tagged = SellwildConfig(partnerCode: 'x', gamTag: '/1/base');

      final config =
          SellwildSDK.apply(configs.gamEmpty(), tagged, isAndroid: false);
      final noBase =
          SellwildSDK.apply(configs.gamEmpty(), base, isAndroid: false);

      // Before: gamTag became '', and the banner built defineSlot('').
      expect(config.gamTag, '/1/base');
      expect(noBase.gamTag, isNull);
      expect(failures, isEmpty);
    });

    test('configure keeps the remote values when AD_REFRESH_INTERVAL is 1e400',
        () async {
      final failures = captureFailures();

      final config = await SellwildSDK.configure(
        partnerCode: 'weatherbug',
        slug: 'weatherbug-weatherbug',
        client: HttpRecorder.text(configs.refreshIntervalOverflowText()).client,
      );

      expect(config.slug, configs.build()['SLUG']);
      expect(config.remoteJson, isNotNull);
      expect(actionsOf(failures), ['config.field.invalid']);
    });

    test("LISTINGS '' means the default: the base listings URL is kept", () {
      final failures = captureFailures();
      const custom = SellwildConfig(
          partnerCode: 'x', listingsUrl: 'https://cache.sellwild.com/custom');

      final config =
          SellwildSDK.apply(configs.listingsEmpty(), custom, isAndroid: false);
      final noBase =
          SellwildSDK.apply(configs.listingsEmpty(), base, isAndroid: false);

      expect(config.listingsUrl, 'https://cache.sellwild.com/custom');
      expect(noBase.listingsUrl, isNull);
      expect(noBase.effectiveListingsUrl, SellwildConfig.defaultListingsUrl);
      expect(failures, isEmpty);
    });
  });

  group('each value apply cannot use is reported once, base kept', () {
    test('mistyped fields: one config.field.invalid naming each key', () {
      final failures = captureFailures();
      final raw = configs.mistypedFields();

      final config = SellwildSDK.apply(raw, base, isAndroid: false);

      expect(actionsOf(failures), ['config.field.invalid']);
      final event = failures.single;
      expect(event.label, 'remoteConfig');
      expect(event.attributes['severity'], 'warn');
      expect(event.attributes.containsKey('host'), isFalse);
      const full = 'TITLE is an integer; COLORS has 1 items that are not text; '
          'BANNER_ZID is a boolean; MOBILE_ZID is text; '
          'AD_REFRESH_MAX is text; TCF_VERSION is not an integer; '
          'IAB_CATS has 1 items that are not text; DEBUG is text; '
          'EVENTS_ENABLED is an object; FAILURES_SAMPLE_RATE is an array';
      final reports =
          groupIssues(applyRemoteConfig(raw, base, isAndroid: false).issues);
      expect(reports.single.message, full);
      // The wire message is cut to 200 code points (FAILURES.md 7.5).
      expect(event.attributes['msg'], '${full.substring(0, 199)}…');
      expect(config.title, base.title);
      expect(config.colors, ['#111111']);
      expect(config.bannerZid, base.bannerZid);
      expect(config.mobileZids, base.mobileZids);
      expect(config.adRefreshMax, base.adRefreshMax);
      expect(config.tcfVersion, base.tcfVersion);
      expect(config.iabCats, ['IAB15']);
      expect(config.debug, base.debug);
      expect(config.eventsEnabled, isTrue);
      expect(config.failuresSampleRate, 1);
      // Everything else still applies.
      expect(config.slug, raw['SLUG']);
      expect(config.gamTag, raw['GAM']);
    });

    test('colors that are not text: config.color.invalid (error)', () {
      final failures = captureFailures();

      final config =
          SellwildSDK.apply(configs.colorsMistyped(), base, isAndroid: false);

      expect(actionsOf(failures), ['config.color.invalid']);
      expect(failures.single.attributes['severity'], 'error');
      expect(failures.single.attributes['msg'],
          'LINK_COLOR is an integer; PRICE_COLOR is an object');
      expect(config.linkColor, base.linkColor);
      expect(config.priceColor, base.priceColor);
    });

    test('unknown ad stack modes: config.adstack.invalid once', () {
      final failures = captureFailures();

      final config =
          SellwildSDK.apply(configs.adStackUnknown(), base, isAndroid: false);

      expect(actionsOf(failures), ['config.adstack.invalid']);
      expect(
          failures.single.attributes['msg'],
          'AD_STACK is not a known mode; '
          'AD_STACK_BY_ZONE has no known mode for zones 280');
      expect(config.adStack, isNull);
      expect(config.adStackByZone, {'43': SellwildAdStack.gamOnly});
    });

    test('ad stacks of the wrong type keep base', () {
      final failures = captureFailures();
      const withStacks = SellwildConfig(
        partnerCode: 'x',
        adStack: SellwildAdStack.both,
        adStackByZone: {'1': SellwildAdStack.prebidOnly},
      );

      final config = SellwildSDK.apply(configs.adStackMistyped(), withStacks,
          isAndroid: false);

      expect(actionsOf(failures), ['config.adstack.invalid']);
      expect(failures.single.attributes['msg'],
          'AD_STACK is an integer; AD_STACK_BY_ZONE is an array');
      expect(config.adStack, SellwildAdStack.both);
      expect(config.adStackByZone, {'1': SellwildAdStack.prebidOnly});
    });

    test("'' ad stacks are unset, not unknown", () {
      final failures = captureFailures();
      const withStacks = SellwildConfig(
        partnerCode: 'x',
        adStackByZone: {'1': SellwildAdStack.prebidOnly},
      );

      final config = SellwildSDK.apply(configs.adStacksEmpty(), withStacks,
          isAndroid: false);

      expect(failures, isEmpty);
      expect(config.adStack, isNull);
      expect(config.adStackByZone, {'1': SellwildAdStack.prebidOnly});
    });

    test('a seconds-style refresh: config.refresh_interval.invalid, applied',
        () {
      final failures = captureFailures();

      final config = SellwildSDK.apply(configs.refreshSecondsStyle(), base,
          isAndroid: false);

      expect(actionsOf(failures), ['config.refresh_interval.invalid']);
      expect(failures.single.attributes['severity'], 'warn');
      expect(failures.single.attributes['msg'],
          'AD_REFRESH_INTERVAL is 30 ms; written in seconds?');
      // Still read as milliseconds, as on every platform.
      expect(config.adRefreshInterval, const Duration(milliseconds: 30));
    });

    test('the seconds-style boundary: 999 ms is reported, 1000 ms is not', () {
      final failures = captureFailures();

      final at999 = SellwildSDK.apply(configs.refreshInterval(999), base,
          isAndroid: false);
      final at1000 = SellwildSDK.apply(configs.refreshInterval(1000), base,
          isAndroid: false);

      expect(actionsOf(failures), ['config.refresh_interval.invalid']);
      expect(failures.single.attributes['msg'],
          'AD_REFRESH_INTERVAL is 999 ms; written in seconds?');
      expect(at999.adRefreshInterval, const Duration(milliseconds: 999));
      expect(at1000.adRefreshInterval, const Duration(seconds: 1));
    });

    test('0 ms is not a seconds-style value: applied, not reported', () {
      final failures = captureFailures();

      final config =
          SellwildSDK.apply(configs.refreshInterval(0), base, isAndroid: false);

      expect(failures, isEmpty);
      expect(config.adRefreshInterval, Duration.zero);
      // The widget page gets the CMS value as is and decides what 0 means.
      expect(buildWidgetHtml(config), contains('ad-refresh-interval="0"'));
    });

    test('a fractional refresh interval is rounded to the nearest ms', () {
      final failures = captureFailures();

      final config = SellwildSDK.apply(configs.refreshInterval(1500.6), base,
          isAndroid: false);

      expect(failures, isEmpty);
      expect(config.adRefreshInterval, const Duration(milliseconds: 1501));
    });

    test('refresh interval as text: config.field.invalid', () {
      final failures = captureFailures();

      final config = SellwildSDK.apply(configs.refreshIntervalText(), base,
          isAndroid: false);

      expect(actionsOf(failures), ['config.field.invalid']);
      expect(failures.single.attributes['msg'], 'AD_REFRESH_INTERVAL is text');
      expect(config.adRefreshInterval, base.adRefreshInterval);
    });

    test('an infinite integer field: config.field.invalid', () {
      final failures = captureFailures();
      final raw = jsonDecode(configs.overflowText('TCF_VERSION'))
          as Map<String, dynamic>;

      final config = SellwildSDK.apply(raw, base, isAndroid: false);

      expect(actionsOf(failures), ['config.field.invalid']);
      expect(failures.single.attributes['msg'],
          'TCF_VERSION is not a finite number');
      expect(config.tcfVersion, base.tcfVersion);
    });

    test('contract-valid values Flutter does not read are drift, not failures',
        () {
      final failures = captureFailures();

      final config =
          SellwildSDK.apply(configs.unreadDrift(), base, isAndroid: false);

      expect(failures, isEmpty);
      // Recorded in contracts/expectations/drift/flutter.json.
      expect(config.bannerZid, isNull);
      expect(config.bottomBannerZid, isNull);
      expect(config.mobileBannerZid, isNull);
      expect(config.adRefreshMax, base.adRefreshMax);
      expect(config.marginBottom, base.marginBottom);
      expect(config.iabCats, isEmpty);
    });

    test('JSON null is absent: nothing reported, base kept', () {
      final failures = captureFailures();
      final raw = configs.typedKeysNull();

      final config = SellwildSDK.apply(raw, base, isAndroid: false);

      expect(failures, isEmpty);
      expect(config.colors, base.colors);
      expect(config.linkColor, base.linkColor);
      expect(config.adRefreshInterval, base.adRefreshInterval);
      expect(config.adStackByZone, base.adStackByZone);
    });

    test('configure reports the config host with each issue', () async {
      final failures = captureFailures();

      await SellwildSDK.configure(
        partnerCode: 'weatherbug',
        slug: 'weatherbug-weatherbug',
        client: HttpRecorder.json(configs.mistypedFields()).client,
      );

      expect(actionsOf(failures), ['config.field.invalid']);
      expect(failures.single.attributes['host'], 'widget.sellwild.com');
    });
  });

  group('contract cases', () {
    // Only the cases built to break a rule are reported.
    const reported = {
      'fixtures/app-config/valid/refresh-interval-seconds-style.json':
          'config.refresh_interval.invalid',
      'fixtures/app-config/valid/by-zone-maps-objects.json':
          'config.adstack.invalid',
    };

    test('every app-config case in contracts/expectations', () {
      final expectations =
          loadExpectations('app-config') as Map<String, dynamic>;

      for (final c in (expectations['cases'] as List).cast<Map>()) {
        final file = c['file'] as String;
        final failures = captureFailures();
        SellwildSDK.apply(readContractObject(file), base, isAndroid: false);
        expect(
            actionsOf(failures), [if (reported[file] != null) reported[file]],
            reason: file);
        endFailureCase();
      }
    });

    test('every invalid app-config fixture that is an object is reported', () {
      final expected = {
        'code-empty.json': 'config.field.invalid',
        'events-enabled-object.json': 'config.field.invalid',
        'failures-sample-rate-object.json': 'config.field.invalid',
        'mobile-zid-string.json': 'config.field.invalid',
        'refresh-interval-text.json': 'config.field.invalid',
        'zone-map-array.json': 'config.adstack.invalid',
      };

      for (final MapEntry(key: name, value: code) in expected.entries) {
        final failures = captureFailures();
        SellwildSDK.apply(
            readContractObject('fixtures/app-config/invalid/$name'), base,
            isAndroid: false);
        expect(actionsOf(failures), [code], reason: name);
        endFailureCase();
      }
    });
  });

  group('pure helpers', () {
    test('applyRemoteConfig returns the issues without logging', () {
      final failures = captureFailures();

      final result =
          applyRemoteConfig(configs.mistypedFields(), base, isAndroid: true);

      expect(failures, isEmpty);
      expect(result.issues, hasLength(10));
      expect(result.issues.map((i) => i.code).toSet(),
          {SellwildFailureCode.configFieldInvalid});
      expect(
          () => result.issues.add(result.issues.first), throwsUnsupportedError);
    });

    test('groupIssues keeps first-found code order and joins details', () {
      final reports = groupIssues(const [
        RemoteConfigIssue('b.c.invalid', 'warn', 'one'),
        RemoteConfigIssue('a.c.invalid', 'error', 'two'),
        RemoteConfigIssue('b.c.invalid', 'warn', 'three'),
      ]);

      expect(reports.map((r) => (r.code, r.severity, r.message)), [
        ('b.c.invalid', 'warn', 'one; three'),
        ('a.c.invalid', 'error', 'two'),
      ]);
      expect(groupIssues(const []), isEmpty);
    });

    test('jsonKind names every JSON kind', () {
      expect(
        [null, 'a', true, 1, 1.5, <Object?>[], <String, Object?>{}]
            .map(jsonKind),
        [
          'null',
          'text',
          'a boolean',
          'an integer',
          'a number',
          'an array',
          'an object'
        ],
      );
      // Not JSON: only a caller that builds the map by hand gets here.
      expect(jsonKind(const Duration()), 'Duration');
    });

    test('the refresh bounds', () {
      expect(maxRefreshIntervalMs, 9007199254740991);
      expect(
          Duration(milliseconds: maxRefreshIntervalMs.round()).inMilliseconds,
          9007199254740991);
      expect(secondsStyleRefreshBelowMs, 1000);
    });
  });
}
