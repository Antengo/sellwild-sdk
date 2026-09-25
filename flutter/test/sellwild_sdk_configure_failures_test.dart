// SellwildSDK.configure and apply with logFailure (FAILURES.md 3.2, 5.3,
// 5.4, 9): the partner is set before the fetch, every fetch failure is
// reported once and falls back to defaults, and the kill switches parsed
// from the remote config reach logFailure and the events client.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/failures/sellwild_log.dart';

import 'factories/shape_factories.dart';
import 'support/failure_capture.dart' as capture;
import 'support/fixtures.dart';
import 'support/http_mocks.dart';
import 'support/network_guard.dart';

const String configUrl =
    'https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json';

/// Failure events logFailure emitted during the test. configure sets the
/// partner itself.
List<ClientFailureEvent> captureFailures({bool allowFolds = false}) =>
    capture.captureFailures(partnerCode: null, allowFolds: allowFolds);

Future<SellwildConfig> configureWith(
  HttpRecorder recorder, {
  Duration timeout = const Duration(seconds: 5),
  SellwildConfig Function(SellwildConfig)? overrides,
}) =>
    SellwildSDK.configure(
      partnerCode: 'weatherbug',
      slug: 'weatherbug-weatherbug',
      timeout: timeout,
      overrides: overrides,
      client: recorder.client,
    );

void expectDefaults(SellwildConfig config) {
  expect(config.partnerCode, 'weatherbug');
  expect(config.slug, '');
  expect(config.remoteJson, isNull);
}

void main() {
  final configs = AppConfigFactory();

  group('configure reports each fetch failure once and keeps defaults', () {
    test('the partner is in the context before the request goes out', () async {
      String? failurePartner;
      String? eventsPartner;
      final recorder = HttpRecorder((request) {
        failurePartner = SellwildFailures.context.partnerCode;
        eventsPartner = SellwildAPIClient.instance.partnerCode;
        return jsonResponse(
            loadSample('app-config', 'weatherbug_weatherbug-weatherbug'));
      });

      await configureWith(recorder);

      expect(failurePartner, 'weatherbug');
      expect(eventsPartner, 'weatherbug');
    });

    test('network error: config.fetch.network', () async {
      final failures = captureFailures();

      final config = await configureWith(HttpRecorder.failing());

      expectDefaults(config);
      final event = failures.single;
      expect(event.action, 'config.fetch.network');
      expect(event.label, 'remoteConfig');
      expect(event.attributes['code'], 'weatherbug');
      expect(event.attributes['errName'], 'ClientException');
      expect(event.attributes['host'], 'widget.sellwild.com');
    });

    test('a redirect is not followed: config.fetch.http', () async {
      final failures = captureFailures();

      final config = await configureWith(HttpRecorder.text('',
          status: 302, headers: const {'location': 'https://example.com/'}));

      expectDefaults(config);
      expect(failures.single.action, 'config.fetch.http');
      expect(failures.single.attributes['httpStatus'], '302');
    });

    test('a status just outside 2xx (199, 300): config.fetch.http', () async {
      for (final status in [199, 300]) {
        final failures = captureFailures();

        final config = await configureWith(HttpRecorder.status(status));

        expectDefaults(config);
        expect(failures.map((e) => e.action), ['config.fetch.http']);
        expect(failures.single.attributes['httpStatus'], '$status');
        expect(failures.single.attributes['msg'], 'HTTP $status');
        capture.endFailureCase();
      }
    });

    test('the last 2xx status (299) is success: applied, nothing reported',
        () async {
      final failures = captureFailures();

      final config = await configureWith(HttpRecorder.json(
          loadSample('app-config', 'weatherbug_weatherbug-weatherbug'),
          status: 299));

      expect(config.slug, 'weatherbug-weatherbug');
      expect(failures, isEmpty);
    });

    test('a missing config (real S3 403 AccessDenied): config.fetch.http',
        () async {
      final failures = captureFailures();
      final body = File(contractsPath('samples/app-config/'
              'realgm_realgm-realgm.403.xml'))
          .readAsStringSync();

      final config = await configureWith(HttpRecorder.text(body,
          status: 403, headers: const {'content-type': 'application/xml'}));

      expectDefaults(config);
      final event = failures.single;
      expect(event.action, 'config.fetch.http');
      expect(event.attributes['httpStatus'], '403');
      expect(event.attributes['msg'], 'HTTP 403');
    });

    test('no answer within the timeout: config.fetch.timeout', () async {
      final failures = captureFailures();

      final config = await configureWith(HttpRecorder.hanging(),
          timeout: const Duration(milliseconds: 1));

      expectDefaults(config);
      expect(failures.single.action, 'config.fetch.timeout');
      expect(failures.single.attributes['errName'], 'TimeoutException');
    });

    test('a body that is not JSON: config.fetch.parse', () async {
      final failures = captureFailures();

      final config = await configureWith(HttpRecorder.text('{"CODE": '));

      expectDefaults(config);
      expect(failures.single.action, 'config.fetch.parse');
      expect(failures.single.attributes['errName'], 'FormatException');
    });

    test('JSON that is not an object: config.parse.invalid', () async {
      final failures = captureFailures();

      expectDefaults(await configureWith(HttpRecorder.json(['CODE'])));
      expectDefaults(await configureWith(HttpRecorder.json(null)));

      expect(failures.map((e) => e.action),
          ['config.parse.invalid', 'config.parse.invalid']);
      expect(failures.map((e) => e.attributes['msg']),
          ['config JSON is List<dynamic>', 'config JSON is null']);
    });

    test('apply throwing: config.apply.exception (configure)', () async {
      final failures = captureFailures();
      final original = SellwildSDK.isAndroidHost;
      addTearDown(() => SellwildSDK.isAndroidHost = original);
      // The mapping itself never throws (1e400 used to: see
      // sellwild_sdk_apply_test.dart), so the host OS seam throws instead.
      SellwildSDK.isAndroidHost = () => throw UnsupportedError('no OS');

      final config = await configureWith(HttpRecorder.json(configs.build()));

      expectDefaults(config);
      expect(failures.single.action, 'config.apply.exception');
      expect(failures.single.label, 'configure');
      expect(failures.single.attributes['errName'], 'UnsupportedError');
      expect(failures.single.attributes['host'], 'widget.sellwild.com');
    });

    test('overrides throwing: config.overrides.exception, then rethrown',
        () async {
      final failures = captureFailures();

      await expectLater(
        configureWith(HttpRecorder.json(configs.build()),
            overrides: (c) => throw StateError('host bug')),
        throwsA(isA<StateError>()),
      );

      expect(failures.single.action, 'config.overrides.exception');
      expect(failures.single.label, 'configure');
      expect(failures.single.attributes['msg'], 'host bug');
    });

    test("without an injected client the SDK's own client is used", () async {
      final failures = captureFailures();
      blockedNetworkAttempts.clear();

      final config = await SellwildSDK.configure(
          partnerCode: 'weatherbug', slug: 'weatherbug-weatherbug');

      expectDefaults(config);
      // The test network guard refused the real request.
      expect(
          blockedNetworkAttempts.single.arguments.last.toString(), configUrl);
      expect(failures.single.action, 'config.fetch.network');
      expect(failures.single.attributes['errName'], 'RealNetworkAccessError');
    });

    test('the client configure makes is closed; an injected one is not',
        () async {
      captureFailures();
      final own = HttpRecorder.json(configs.build());
      final injected = HttpRecorder.json(configs.build());

      // http.Client() inside runWithClient returns own.client.
      await http.runWithClient(
          () => SellwildSDK.configure(
              partnerCode: 'weatherbug', slug: 'weatherbug-weatherbug'),
          () => own.client);
      await configureWith(injected);

      expect(own.single.url.toString(), configUrl);
      expect(own.closeCount, 1);
      expect(injected.single.url.toString(), configUrl);
      expect(injected.closed, isFalse);
    });

    test('a successful fetch reports nothing', () async {
      final failures = captureFailures();
      final recorder = HttpRecorder.json(
          loadSample('app-config', 'weatherbug_weatherbug-weatherbug'));

      final config = await configureWith(recorder);

      expect(config.slug, 'weatherbug-weatherbug');
      expect(recorder.single.url.toString(), configUrl);
      expect(failures, isEmpty);
    });

    test('configure passes the host OS to apply', () async {
      captureFailures();
      final sample = configs.build();
      // Read now: a lazy top-level would first be read after the swap.
      final original = SellwildSDK.isAndroidHost;
      addTearDown(() => SellwildSDK.isAndroidHost = original);

      SellwildSDK.isAndroidHost = () => true;
      final android = await configureWith(HttpRecorder.json(sample));
      SellwildSDK.isAndroidHost = () => false;
      final ios = await configureWith(HttpRecorder.json(sample));

      expect(android.appBundleId, sample['APP_BUNDLE_ID_ANDROID']);
      expect(ios.appBundleId, sample['APP_BUNDLE_ID_IOS']);
      expect(android.appBundleId, isNot(ios.appBundleId));
    });
  });

  group('configure hands the resolved switches on', () {
    test('to logFailure and the events client', () async {
      final failures = captureFailures();
      final printed = <String>[];
      SellwildLog.printer = printed.add;
      final remote = configs.failuresOffDebug();

      final config = await configureWith(HttpRecorder.json(remote));

      expect(config.failuresEnabled, isFalse);
      expect(config.failuresSampleRate, 0.25);
      final context = SellwildFailures.context;
      expect(context.partnerCode, remote['CODE']);
      expect(context.debug, isTrue);
      expect(context.eventsEnabled, isTrue);
      expect(context.failuresEnabled, isFalse);
      expect(context.failuresSampleRate, 0.25);
      expect(SellwildAPIClient.instance.partnerCode, remote['CODE']);
      expect(SellwildAPIClient.instance.eventsEnabled, isTrue);

      // FAILURES_ENABLED off: the next failure is dropped, and DEBUG on
      // echoes why.
      SellwildFailures.log(
          code: SellwildFailureCode.listingsFetchHttp,
          component: SellwildFailureComponent.listings);
      expect(failures, isEmpty);
      expect(printed, [
        '[Sellwild] failure listings.fetch.http listings error '
            'failures_disabled'
      ]);
    });

    test('EVENTS_ENABLED off stops the events client', () async {
      final fixture =
          loadFixture('app-config', 'events-off-text') as Map<String, dynamic>;

      final config = await configureWith(HttpRecorder.json(fixture));

      expect(config.eventsEnabled, isFalse);
      expect(SellwildFailures.context.eventsEnabled, isFalse);
      expect(SellwildAPIClient.instance.eventsEnabled, isFalse);
    });

    test('a host override of failuresEnabled wins over the remote value',
        () async {
      final fixture = loadFixture('app-config', 'failures-off-sampled')
          as Map<String, dynamic>;

      final config = await configureWith(
        HttpRecorder.json(fixture),
        overrides: (c) => SellwildConfig(
            partnerCode: c.partnerCode,
            failuresEnabled: true,
            failuresSampleRate: c.failuresSampleRate),
      );

      expect(config.failuresEnabled, isTrue);
      expect(SellwildFailures.context.failuresEnabled, isTrue);
    });
  });

  group('SellwildSDK.apply', () {
    test(
        'every field flutter is held to matches contracts/expectations on '
        'both OSes, or drift/flutter.json names the case and field', () {
      final expectations =
          loadExpectations('app-config') as Map<String, dynamic>;
      final drift = (readContractObject('expectations/drift/flutter.json')[
          'expectations'] as Map)['app-config'] as Map;
      final zones = (expectations['zones'] as List).cast<String>();
      const base = SellwildConfig(partnerCode: 'x');
      String? name(SellwildAdStack? stack) => stack?.name;

      // What flutter produces for each field, in the expectations' shape.
      // Per-OS fields are compared with the value for the OS apply ran as.
      final actual = <String, Object? Function(SellwildConfig)>{
        'partnerCode': (c) => c.partnerCode,
        'slug': (c) => c.slug,
        'mobileZids': (c) => c.mobileZids,
        'mobileBannerZid': (c) => c.mobileBannerZid,
        // null means unset: flutter keeps its default Duration.
        'adRefreshIntervalMs': (c) => c.adRefreshInterval ==
                base.adRefreshInterval
            ? null
            : c.adRefreshInterval.inMilliseconds,
        'iabCats': (c) => c.iabCats,
        'adStack': (c) => {
              'global': name(c.adStack),
              'byZone': c.adStackByZone.map((k, v) => MapEntry(k, v.name)),
              'resolved': {
                for (final z in zones) z: name(SellwildAdStack.resolve(c, z)),
              },
            },
        'eventsEnabled': (c) => c.eventsEnabled,
        'failuresEnabled': (c) => c.failuresEnabled,
        'failuresSampleRate': (c) => c.failuresSampleRate,
        'appBundleId': (c) => c.appBundleId,
        'appStoreUrl': (c) => c.appStoreUrl,
      };
      const perOs = {
        'mobileZids',
        'mobileBannerZid',
        'appBundleId',
        'appStoreUrl'
      };
      final held = [
        for (final MapEntry(:key, :value)
            in (expectations['fields'] as Map<String, dynamic>).entries)
          if (((value as Map)['platforms'] as List).contains('flutter')) key,
      ];
      // A field added to the contract must be added here too.
      expect(actual.keys.toSet(), held.toSet());

      final allowedUsed = <String>{};
      for (final c
          in (expectations['cases'] as List).cast<Map<String, dynamic>>()) {
        final file = c['file'] as String;
        final expected = c['expected'] as Map<String, dynamic>;
        final driftText = drift[file] as String? ?? '';
        final raw = readContractObject(file);

        for (final os in ['ios', 'android']) {
          // Two cases are built to be reported (sellwild_sdk_apply_test.dart).
          captureFailures();
          final config =
              SellwildSDK.apply(raw, base, isAndroid: os == 'android');
          capture.endFailureCase();

          for (final field in held) {
            final want = perOs.contains(field)
                ? (expected[field] as Map)[os]
                : field == 'adRefreshIntervalMs' &&
                        expected[field] == base.adRefreshInterval.inMilliseconds
                    ? null
                    : expected[field];
            final got = actual[field]!(config);
            if (driftText.contains('$field:')) {
              if (!equals(want).matches(got, {})) {
                allowedUsed.add('$file $field');
              }
              continue;
            }
            expect(got, want, reason: '$file $field ($os)');
          }
        }
      }

      // Every drift entry still differs somewhere: a fixed one is removed.
      final named = <String>{
        for (final MapEntry(:key, :value) in drift.entries)
          for (final field in held)
            if ((value as String).contains('$field:')) '$key $field',
      };
      expect(allowedUsed, named);
    });

    test('absent or null switches keep the base values', () {
      const base = SellwildConfig(
        partnerCode: 'x',
        eventsEnabled: false,
        failuresEnabled: false,
        failuresSampleRate: 0.5,
      );

      for (final raw in [configs.switchesAbsent(), configs.switchesNull()]) {
        final config = SellwildSDK.apply(raw, base, isAndroid: false);
        expect(config.eventsEnabled, isFalse);
        expect(config.failuresEnabled, isFalse);
        expect(config.failuresSampleRate, 0.5);
      }
    });

    test('coerces text, numbers and garbage per the contract', () {
      const base = SellwildConfig(partnerCode: 'x');

      final config =
          SellwildSDK.apply(configs.switchesCoerced(), base, isAndroid: false);

      expect(config.eventsEnabled, isFalse);
      expect(config.failuresEnabled, isFalse);
      expect(config.failuresSampleRate, 1);
    });

    test('isAndroid picks the per-OS app identity keys', () {
      const base = SellwildConfig(partnerCode: 'x');
      // The real weatherbug config sets the shared keys and both per-OS
      // ones, each with its own value.
      final raw = configs.build();

      final android = SellwildSDK.apply(raw, base, isAndroid: true);
      final ios = SellwildSDK.apply(raw, base, isAndroid: false);
      // Without isAndroid, apply reads the host OS (not Android here).
      final host = SellwildSDK.apply(raw, base);

      expect(raw['APP_BUNDLE_ID'], isNot(raw['APP_BUNDLE_ID_IOS']));
      expect(android.appBundleId, raw['APP_BUNDLE_ID_ANDROID']);
      expect(android.appStoreUrl, raw['APP_STORE_URL_ANDROID']);
      expect(ios.appBundleId, raw['APP_BUNDLE_ID_IOS']);
      expect(ios.appStoreUrl, raw['APP_STORE_URL_IOS']);
      expect(host.appBundleId,
          Platform.isAndroid ? android.appBundleId : ios.appBundleId);
    });

    test('without isAndroid, apply asks isAndroidHost', () {
      captureFailures();
      const base = SellwildConfig(partnerCode: 'x');
      final raw = configs.build();
      // Read now: a lazy top-level would first be read after the swap.
      final original = SellwildSDK.isAndroidHost;
      addTearDown(() => SellwildSDK.isAndroidHost = original);

      SellwildSDK.isAndroidHost = () => true;
      final android = SellwildSDK.apply(raw, base);
      SellwildSDK.isAndroidHost = () => false;
      final ios = SellwildSDK.apply(raw, base);

      expect(android.appBundleId, raw['APP_BUNDLE_ID_ANDROID']);
      expect(android.appStoreUrl, raw['APP_STORE_URL_ANDROID']);
      expect(ios.appBundleId, raw['APP_BUNDLE_ID_IOS']);
      expect(ios.appStoreUrl, raw['APP_STORE_URL_IOS']);
    });

    test('an explicit isAndroid wins over isAndroidHost', () {
      captureFailures();
      const base = SellwildConfig(partnerCode: 'x');
      final raw = configs.build();
      final original = SellwildSDK.isAndroidHost;
      addTearDown(() => SellwildSDK.isAndroidHost = original);

      SellwildSDK.isAndroidHost = () => fail('the host OS was read');

      expect(SellwildSDK.apply(raw, base, isAndroid: false).appBundleId,
          raw['APP_BUNDLE_ID_IOS']);
      expect(SellwildSDK.apply(raw, base, isAndroid: true).appBundleId,
          raw['APP_BUNDLE_ID_ANDROID']);
    });
  });
}
