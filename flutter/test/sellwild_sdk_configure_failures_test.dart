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
import 'support/fixtures.dart';
import 'support/http_mocks.dart';
import 'support/network_guard.dart';

const String configUrl =
    'https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json';

/// Failure events logFailure emitted during the test.
List<ClientFailureEvent> captureFailures() {
  final events = <ClientFailureEvent>[];
  SellwildFailures.setContext(
    clock: () => 1790000000000,
    uid: () => 'u-test',
    sink: (event, flushNow) async => events.add(event),
  );
  return events;
}

/// The host OS check configure starts with.
final bool Function() hostIsAndroid = SellwildSDK.isAndroidHost;

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

      // JSON 1e400 decodes to Infinity, which Duration cannot hold.
      final config = await configureWith(
          HttpRecorder.text(configs.refreshIntervalOverflowText()));

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
      addTearDown(() => SellwildSDK.isAndroidHost = hostIsAndroid);

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
    test('kill switches match contracts/expectations for every case', () {
      final expectations =
          loadExpectations('app-config') as Map<String, dynamic>;
      const base = SellwildConfig(partnerCode: 'x');

      for (final c in (expectations['cases'] as List).cast<Map>()) {
        final raw =
            readContractJson(c['file'] as String) as Map<String, dynamic>;
        final expected = c['expected'] as Map<String, dynamic>;

        final config = SellwildSDK.apply(raw, base, isAndroid: false);

        expect(config.eventsEnabled, expected['eventsEnabled'],
            reason: '${c['file']} eventsEnabled');
        expect(config.failuresEnabled, expected['failuresEnabled'],
            reason: '${c['file']} failuresEnabled');
        expect(config.failuresSampleRate, expected['failuresSampleRate'],
            reason: '${c['file']} failuresSampleRate');
      }
    });

    test('absent or null switches keep the base values', () {
      const base = SellwildConfig(
        partnerCode: 'x',
        eventsEnabled: false,
        failuresEnabled: false,
        failuresSampleRate: 0.5,
      );

      for (final raw in [
        <String, dynamic>{},
        <String, dynamic>{
          'EVENTS_ENABLED': null,
          'FAILURES_ENABLED': null,
          'FAILURES_SAMPLE_RATE': null,
        },
      ]) {
        final config = SellwildSDK.apply(raw, base, isAndroid: false);
        expect(config.eventsEnabled, isFalse);
        expect(config.failuresEnabled, isFalse);
        expect(config.failuresSampleRate, 0.5);
      }
    });

    test('coerces text, numbers and garbage per the contract', () {
      const base = SellwildConfig(partnerCode: 'x');

      final config = SellwildSDK.apply({
        'EVENTS_ENABLED': ' OFF ',
        'FAILURES_ENABLED': 0,
        'FAILURES_SAMPLE_RATE': '50%',
      }, base, isAndroid: false);

      expect(config.eventsEnabled, isFalse);
      expect(config.failuresEnabled, isFalse);
      expect(config.failuresSampleRate, 1);
    });

    test('isAndroid picks the per-OS app identity keys', () {
      const base = SellwildConfig(partnerCode: 'x');
      const raw = <String, dynamic>{
        'APP_BUNDLE_ID_IOS': 'com.example.ios',
        'APP_BUNDLE_ID_ANDROID': 'com.example.android',
        'APP_STORE_URL_IOS': 'https://apps.apple.com/app/id1',
        'APP_STORE_URL_ANDROID':
            'https://play.google.com/store/apps/details?id=com.example',
      };

      final android = SellwildSDK.apply(raw, base, isAndroid: true);
      final ios = SellwildSDK.apply(raw, base, isAndroid: false);
      // Without isAndroid, apply reads the host OS (not Android here).
      final host = SellwildSDK.apply(raw, base);

      expect(android.appBundleId, 'com.example.android');
      expect(android.appStoreUrl,
          'https://play.google.com/store/apps/details?id=com.example');
      expect(ios.appBundleId, 'com.example.ios');
      expect(ios.appStoreUrl, 'https://apps.apple.com/app/id1');
      expect(host.appBundleId,
          Platform.isAndroid ? android.appBundleId : ios.appBundleId);
    });
  });
}
