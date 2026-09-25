// Proves the test harness itself: real HTTP is blocked, the recording
// MockClient and fake_async work, the fake WebView platform drives the real
// widgets, the schema matcher rejects what ajv rejects (formats at every
// depth included) and agrees with validate.mjs on every contract file, and
// the fixture loaders and contract emitter use the paths the other platforms
// use.
//
// Expected answers marked "ajv" were produced by ajv 8 + ajv-formats with
// validate.mjs's options on the same schema and value.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'contract_emitter.dart';
import 'contract_schemas.dart';
import 'fake_webview_platform.dart';
import 'failure_capture.dart';
import 'fixtures.dart';
import 'http_mocks.dart';
import 'network_guard.dart';

// .invalid never resolves (RFC 2606), so even a broken block cannot reach a
// real server.
final Uri probe = Uri.parse('https://sellwild-harness.invalid/probe');

const String draft2020 = 'https://json-schema.org/draft/2020-12/schema';

void main() {
  group('real HTTP is blocked', () {
    testWidgets('flutter_test binding answers dart:io HttpClient with 400',
        (tester) async {
      final status = await tester.runAsync(() async {
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(probe)).close();
          return response.statusCode;
        } finally {
          client.close(force: true);
        }
      });
      expect(status, 400);
    });

    group('network guard', () {
      HttpOverrides? previous;

      setUp(() {
        previous = HttpOverrides.current;
        blockedNetworkAttempts.clear();
        installNetworkGuard();
      });

      tearDown(() => HttpOverrides.global = previous);

      test('a dart:io HttpClient throws and the attempt is recorded', () {
        final client = HttpClient();
        expect(
            () => client.getUrl(probe), throwsA(isA<RealNetworkAccessError>()));
        expect(blockedNetworkAttempts.single.member, 'getUrl');
        expect(blockedNetworkAttempts.single.arguments, [probe]);
        // Closing a blocked client is allowed (SDK code closes in finally).
        client.close();
      });

      test("package:http's default client fails loudly", () async {
        await expectLater(
            http.get(probe), throwsA(isA<RealNetworkAccessError>()));
        expect(blockedNetworkAttempts.single.member, 'openUrl');
        expect(blockedNetworkAttempts.single.arguments, ['GET', probe]);
      });
    });
  });

  group('HttpRecorder', () {
    test('records the request and answers UTF-8 JSON', () async {
      final recorder = HttpRecorder.json({'title': 'Café'});
      final response = await recorder.client.post(
        probe,
        headers: {'content-type': 'application/json'},
        body: jsonEncode([
          {'n': 1},
        ]),
      );

      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), {'title': 'Café'});
      expect(recorder.single.method, 'POST');
      expect(recorder.single.url, probe);
      expect(recorder.single.headers['content-type'],
          startsWith('application/json'));
      expect(recorder.jsonBody(), [
        {'n': 1},
      ]);
    });

    test('status, text and failing answers', () async {
      expect(
          (await HttpRecorder.status(404).client.get(probe)).statusCode, 404);

      final denied =
          await HttpRecorder.text('<Error>AccessDenied</Error>', status: 403)
              .client
              .get(probe);
      expect(denied.statusCode, 403);
      expect(denied.body, '<Error>AccessDenied</Error>');

      final failing = HttpRecorder.failing();
      await expectLater(
        failing.client.get(probe),
        throwsA(isA<http.ClientException>().having((e) => e.uri, 'uri', probe)),
      );
      expect(failing.requests, hasLength(1));
    });

    test('sequence answers in order and rejects an extra call', () async {
      final recorder = HttpRecorder.sequence([
        (_) => textResponse('', status: 503),
        (_) => jsonResponse({'ok': true}),
      ]);
      expect((await recorder.client.get(probe)).statusCode, 503);
      expect((await recorder.client.get(probe)).statusCode, 200);
      await expectLater(
        recorder.client.get(probe),
        throwsA(isA<UnexpectedRequestError>()),
      );
      expect(recorder.requests, hasLength(3));
    });

    test('byHost rejects a host with no route', () async {
      final recorder = HttpRecorder.byHost({
        'cache.sellwild.com': (_) => jsonResponse({'ok': true}),
      });
      final ok = await recorder.client
          .get(Uri.parse('https://cache.sellwild.com/listings-sm'));
      expect(ok.statusCode, 200);
      await expectLater(
        recorder.client
            .get(Uri.parse('https://events.sellwild.com/events/queue')),
        throwsA(isA<UnexpectedRequestError>().having(
            (e) => e.reason, 'reason', contains('events.sellwild.com'))),
      );
    });

    test('close is counted and later requests fail like IOClient', () async {
      final recorder = HttpRecorder.status(204);
      expect(recorder.closed, isFalse);
      recorder.client.close();
      expect(recorder.closeCount, 1);
      await expectLater(
        recorder.client.get(probe),
        throwsA(isA<http.ClientException>()
            .having((e) => e.message, 'message', contains('already closed'))),
      );
      expect(recorder.requests, isEmpty);
    });

    test('hanging answer reaches a timeout under fake_async', () {
      fakeAsync((async) {
        final recorder = HttpRecorder.hanging();
        Object? error;
        recorder.client
            .get(probe)
            .timeout(const Duration(seconds: 5))
            .then((_) {}, onError: (Object e) {
          error = e;
        });

        async.elapse(const Duration(seconds: 4));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(error, isA<TimeoutException>());
        expect(recorder.requests, hasLength(1));
      });
    });

    test('drives SellwildSDK.configure without closing an injected client',
        () async {
      // Real app config captured from widget.sellwild.com.
      final sample =
          loadSample('app-config', 'weatherbug_weatherbug-weatherbug')
              as Map<String, dynamic>;
      final recorder = HttpRecorder.json(sample);
      final config = await SellwildSDK.configure(
        partnerCode: 'weatherbug',
        slug: 'weatherbug-weatherbug',
        client: recorder.client,
      );

      expect(config.slug, sample['SLUG']);
      expect(config.adRefreshInterval,
          Duration(milliseconds: sample['AD_REFRESH_INTERVAL'] as int));
      expect(
        recorder.single.url.toString(),
        'https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json',
      );
      expect(recorder.single.headers['User-Agent'],
          'SellwildSDK/$sellwildSdkVersion (flutter)');
      expect(recorder.closed, isFalse);
    });
  });

  group('captureFailures', () {
    void logBridgeParse() => SellwildFailures.log(
        code: SellwildFailureCode.bridgeMessageParse,
        component: SellwildFailureComponent.bridge,
        message: 'not JSON');

    test('the sink sees a repeat once; foldedRepeats names it', () {
      final failures = captureFailures(allowFolds: true);

      logBridgeParse();
      expect(foldedRepeats(), isEmpty);
      expectNoFoldedRepeats();
      logBridgeParse();

      // The fixed clock keeps the repeat inside the dedupe window.
      expect(actionsOf(failures), ['bridge.message.parse']);
      expect(foldedRepeats(),
          ['bridge.message.parse|bridge||not JSON (+1)']);
      expect(expectNoFoldedRepeats, throwsA(isA<TestFailure>()));
    });

    test('distinct failures are not folds', () {
      final failures = captureFailures();

      logBridgeParse();
      SellwildFailures.log(
          code: SellwildFailureCode.bridgeMessageParse,
          component: SellwildFailureComponent.bridge,
          message: 'not JSON either');

      expect(failures, hasLength(2));
      expect(foldedRepeats(), isEmpty);
    });
  });

  group('FakeWebViewPlatform', () {
    late FakeWebViewPlatform webviews;

    setUp(() => webviews = FakeWebViewPlatform.install());

    testWidgets('SellwildWidget builds and its bridge channel is drivable',
        (tester) async {
      // The load error below is reported through logFailure.
      final failures = captureFailures();
      var loads = 0;
      final errors = <Object>[];
      await tester.pumpWidget(MaterialApp(
        home: SellwildWidget(
          config: const SellwildConfig(partnerCode: 'weatherbug'),
          onLoad: () => loads++,
          onError: errors.add,
        ),
      ));

      final controller = webviews.lastController;
      expect(controller.javaScriptMode, JavaScriptMode.unrestricted);
      expect(controller.channels.keys, contains('SellwildWidgetBridge'));
      expect(controller.lastHtml.baseUrl, 'https://widget.sellwild.com');
      expect(controller.lastHtml.html, contains('partner-code="weatherbug"'));
      expect(find.byKey(FakeWebViewWidget.widgetKey), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.postJson('SellwildWidgetBridge',
          loadFixture('bridge-message', 'widget-loaded'));
      await tester.pump();
      expect(loads, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      const error = WebResourceError(
        errorCode: -2,
        description: 'net::ERR_NAME_NOT_RESOLVED',
        isForMainFrame: true,
      );
      controller.navigationDelegate!.emitWebResourceError(error);
      expect(errors, [same(error)]);
      expect(actionsOf(failures), ['widget.webview_load.network']);
    });

    testWidgets('SellwildBanner forwards impressions from SellwildAdBridge',
        (tester) async {
      var impressions = 0;
      await tester.pumpWidget(MaterialApp(
        home: SellwildBanner(
          config: const SellwildConfig(partnerCode: 'weatherbug'),
          adSize: SellwildAdSize.banner320x50,
          zoneId: '43',
          onImpression: () => impressions++,
        ),
      ));

      final controller = webviews.lastController;
      final html = controller.lastHtml.html;
      expect(html, contains('zone=43&w=320&h=50'));
      // SellwildAdBridge has no contract schema yet (bridge-message covers
      // SellwildWidgetBridge only), so the message is the one this page's own
      // script posts: notify('impression') sends {type: 'impression'}.
      expect(html, contains("notify('impression')"));
      expect(html, contains('JSON.stringify(Object.assign({ type: type }'));
      controller.postJson('SellwildAdBridge', {'type': 'impression'});
      expect(impressions, 1);
    });

    test('unknown channels and unset callbacks throw', () {
      final controller = WebViewController()
        ..addJavaScriptChannel('SellwildWidgetBridge',
            onMessageReceived: (_) {})
        ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {}));
      final fake = webviews.lastController;

      expect(() => fake.postMessage('NoSuchBridge', '{}'), throwsStateError);
      expect(() => fake.navigationDelegate!.emitProgress(50), throwsStateError);
      expect(controller.platform, same(fake));
    });

    test('loadError makes loadHtmlString fail without recording a load',
        () async {
      webviews.loadError = StateError('renderer gone');
      final controller = WebViewController();
      await expectLater(controller.loadHtmlString('<p></p>'), throwsStateError);
      expect(webviews.lastController.loadedHtml, isEmpty);
    });
  });

  group('schema matcher', () {
    late Directory root;
    Directory schemas() => Directory('${root.path}/schemas');

    // Covers $defs, a cross-file $ref, and the two formats the contract
    // schemas use (uri, date-time).
    Map<String, Object?> eventSchema() => {
          r'$schema': draft2020,
          r'$id': 'https://contracts.sellwild.com/event.schema.json',
          'type': 'object',
          'additionalProperties': false,
          'required': ['event', 'action', 'createdTime', 'attributes'],
          'properties': {
            'event': {'const': 'clientFailure'},
            'action': {r'$ref': 'code.schema.json'},
            'createdTime': {'type': 'integer'},
            'url': {'type': 'string', 'format': 'uri'},
            'seenAt': {'type': 'string', 'format': 'date-time'},
            'attributes': {r'$ref': r'#/$defs/attributes'},
          },
          r'$defs': {
            'attributes': {
              'type': 'object',
              'additionalProperties': {'type': 'string'},
              'properties': {
                'severity': {
                  'enum': ['fatal', 'error', 'warn'],
                },
              },
            },
          },
        };

    setUp(() {
      root = Directory.systemTemp.createTempSync('sellwild-schemas-');
      schemas().createSync();
      File('${schemas().path}/code.schema.json').writeAsStringSync(jsonEncode({
        r'$schema': draft2020,
        r'$id': 'https://contracts.sellwild.com/code.schema.json',
        'type': 'string',
        'pattern': r'^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$',
      }));
      File('${schemas().path}/event.schema.json')
          .writeAsStringSync(jsonEncode(eventSchema()));
      File('${schemas().path}/link.schema.json').writeAsStringSync(jsonEncode({
        r'$schema': draft2020,
        r'$id': 'https://contracts.sellwild.com/link.schema.json',
        'type': 'object',
        'required': ['href'],
        'additionalProperties': false,
        'properties': {
          'href': {'type': 'string', 'format': 'uri'},
        },
      }));
    });

    tearDown(() {
      contractsDirOverride = null;
      root.deleteSync(recursive: true);
    });

    JsonSchema event() =>
        compileSchema(eventSchema(), name: 'event', schemasDir: schemas());

    Map<String, Object?> valid() => {
          'event': 'clientFailure',
          'action': 'config.fetch.http',
          'createdTime': 1790000000000,
          'url': probe.toString(),
          'seenAt': '2026-09-23T10:00:00Z',
          'attributes': {'severity': 'error', 'httpStatus': '503'},
        };

    test(r'accepts a valid payload through $defs and a cross-file $ref', () {
      expect(valid(), conformsToSchema(event()));
    });

    test('rejects each kind of violation', () {
      final schema = event();
      final violations = <String, Map<String, Object?>>{
        'const': {...valid(), 'event': 'adError'},
        'cross-file pattern': {...valid(), 'action': 'config_fetch_failed'},
        'integer': {...valid(), 'createdTime': 1.5},
        'format uri': {...valid(), 'url': 'cache.sellwild.com/listings'},
        'format date-time': {...valid(), 'seenAt': '2026-09-23'},
        r'$defs enum': {
          ...valid(),
          'attributes': {'severity': 'info'},
        },
        r'$defs additionalProperties': {
          ...valid(),
          'attributes': {'seq': 1},
        },
        'additionalProperties': {...valid(), 'amount': 1},
        'required': {...valid()}..remove('action'),
      };
      for (final entry in violations.entries) {
        expect(entry.value, isNot(conformsToSchema(schema)), reason: entry.key);
      }
    });

    test('a failed expect names the schema and lists every error', () {
      final bad = {...valid(), 'event': 'adError', 'seenAt': '2026-09-23'};
      expect(
        () => expect(bad, conformsToSchema(event(), label: 'the event schema')),
        throwsA(isA<TestFailure>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('a payload valid against the event schema'),
            contains('has 2 schema error(s)'),
            contains('/event: '),
            contains('/seenAt: "date-time" format not accepted 2026-09-23'),
          ),
        )),
      );
    });

    test('format answers match ajv-formats, not json_schema defaults', () {
      // Each expected answer is what ajv 8 + ajv-formats 3 (validate.mjs)
      // gives for the same string. json_schema's built-in checks get every
      // row after the first in each format wrong.
      const cases = <(String, String, bool)>[
        ('date-time', '2026-09-23T10:00:00Z', true),
        ('date-time', '2026-09-23', false),
        ('date-time', '2026-09-23T10:00:00', false),
        ('date-time', '2026-02-29T00:00:00Z', false),
        ('date-time', '2026-09-23T22:59:60Z', false),
        ('date-time', '2026-09-23T10:00:00+05:60', false),
        ('date-time', '2026-09-23t10:00:00z', true),
        ('date', '2024-02-29', true),
        ('date', '1900-02-29', false),
        ('time', '10:00:00Z', true),
        ('time', '10:00:00.5+01:00', true),
        ('uri', 'https://widget.sellwild.com/app/weatherbug/main.json', true),
        ('uri', 'https:', false),
        ('uri', 'https://a.b/%zz', false),
        ('uri', 'https://sellwild.com/p?x=[1]', false),
        ('uri', 'data:image/png;base64,iVBOR==', true),
      ];
      for (final (format, value, ok) in cases) {
        final schema = compileSchema({
          r'$schema': draft2020,
          'format': format,
        }, name: 'format', schemasDir: schemas());
        expect(value,
            ok ? conformsToSchema(schema) : isNot(conformsToSchema(schema)),
            reason: '$format "$value"');
      }
    });

    test('format is checked at every depth, as ajv checks it', () {
      // json_schema alone skipped formats under anyOf, oneOf, allOf, if/then,
      // not and contains (its child validators never check formats).
      final schema = compileSchema({
        r'$schema': draft2020,
        'type': 'object',
        'properties': {
          'root': {'type': 'string', 'format': 'uri'},
          'items': {
            'type': 'array',
            'items': {'format': 'uri'},
          },
          'defs': {r'$ref': r'#/$defs/uri'},
          'crossFile': {r'$ref': 'link.schema.json'},
          'anyOf': {
            'anyOf': [
              {'type': 'string', 'format': 'uri'},
              {'type': 'integer'},
            ],
          },
          'oneOf': {
            'oneOf': [
              {'format': 'uri'},
              {'type': 'integer'},
            ],
          },
          'allOf': {
            'allOf': [
              {'format': 'uri'},
            ],
          },
          'ifThen': {
            'if': {'type': 'string'},
            'then': {'format': 'uri'},
          },
          'not': {
            'not': {'format': 'uri'},
          },
          'contains': {
            'type': 'array',
            'contains': {'type': 'string', 'format': 'uri'},
          },
          // The shape of app-config's LOCALIZED_LISTINGS.
          'anyOfCrossFile': {
            'anyOf': [
              {'const': ''},
              {r'$ref': 'link.schema.json'},
            ],
          },
          'nullable': {
            'type': ['string', 'null'],
            'format': 'uri',
          },
        },
        r'$defs': {
          'uri': {'type': 'string', 'format': 'uri'},
        },
      }, name: 'formats', schemasDir: schemas());

      const good = 'https://widget.sellwild.com/app';
      const bad = 'not a uri';
      // Property -> (a value ajv accepts, a value ajv rejects).
      final cases = <String, (Object?, Object?)>{
        'root': (good, bad),
        'items': ([good], [bad]),
        'defs': (good, bad),
        'crossFile': ({'href': good}, {'href': bad}),
        'anyOf': (good, bad),
        'oneOf': (good, bad),
        'allOf': (good, bad),
        'ifThen': (good, bad),
        'not': (bad, good),
        'contains': ([1, good], [1, bad]),
        'anyOfCrossFile': ({'href': good}, {'href': bad}),
        'nullable': (null, bad),
      };
      for (final MapEntry(key: where, value: (ok, notOk)) in cases.entries) {
        expect({where: ok}, conformsToSchema(schema), reason: '$where: $ok');
        expect({where: notOk}, isNot(conformsToSchema(schema)),
            reason: '$where: $notOk');
      }
      // A null never meets a format (json_schema would throw a TypeError on
      // it). ajv: oneOf and allOf accept null here, anyOf does not.
      expect({'oneOf': null}, conformsToSchema(schema));
      expect({'allOf': null}, conformsToSchema(schema));
      expect({'anyOf': null}, isNot(conformsToSchema(schema)));
      expect({
        'items': [null],
      }, conformsToSchema(schema));
    });

    test('a format node that has its own if/then keeps both', () {
      final schema = compileSchema({
        r'$schema': draft2020,
        'type': 'string',
        'if': {'minLength': 5},
        'then': {'maxLength': 10},
        'format': 'date',
      }, name: 'format-if', schemasDir: schemas());

      expect('2026-09-23', conformsToSchema(schema));
      expect('2026-9-23', isNot(conformsToSchema(schema)));
      expect('2026-09-23T10:00:00Z', isNot(conformsToSchema(schema)));
      expect('soon', isNot(conformsToSchema(schema)));
      expect(
          explainErrors(schema, '2026-9-23').map((e) => e.keyword), ['format']);
    });

    test('format as a property name or inside data is not a format', () {
      // "email" has no port, so compiling would throw if either were
      // treated as a format keyword.
      final schema = compileSchema({
        r'$schema': draft2020,
        'type': 'object',
        'properties': {
          'format': {'type': 'string'},
        },
        'examples': [
          {'format': 'email'},
        ],
      }, name: 'format-data', schemasDir: schemas());

      expect({'format': 'email'}, conformsToSchema(schema));
      expect({'format': 1}, isNot(conformsToSchema(schema)));
    });

    test('an unported format or another draft fails to compile', () {
      expect(
        () => compileSchema({r'$schema': draft2020, 'format': 'email'},
            name: 'email', schemasDir: schemas()),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('"email" has no ajv-formats port'))),
      );
      expect(
        () => compileSchema(
            {r'$schema': 'http://json-schema.org/draft-07/schema#'},
            name: 'draft7', schemasDir: schemas()),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('contract schemas are 2020-12'))),
      );
    });

    test('explainErrors lists branch errors with the path and keyword ajv uses',
        () {
      final schema = compileSchema({
        r'$schema': draft2020,
        'type': 'object',
        'required': ['kind'],
        'properties': {
          'kind': {
            'oneOf': [
              {'const': 'a'},
              {'const': 'b'},
            ],
          },
          'link': {
            'anyOf': [
              {'const': ''},
              {r'$ref': 'link.schema.json'},
            ],
          },
          'n': {
            'if': {'type': 'number'},
            'then': {'minimum': 0},
          },
          'at': {
            'type': 'string',
            'if': {'minLength': 5},
            'then': {'maxLength': 10},
            'format': 'date',
          },
        },
      }, name: 'explain', schemasDir: schemas());
      List<String> explain(Object? value) => explainErrors(schema, value)
          .map((e) => '${e.instancePath} ${e.keyword}')
          .toList();

      // Each list is ajv's errors for the same value, as instancePath keyword.
      expect(
        explain({
          'kind': 'c',
          'link': {'href': 'nope'},
          'n': -1,
          'at': 'soon',
        }),
        unorderedEquals([
          '/kind const',
          '/kind const',
          '/kind oneOf',
          '/link const',
          '/link/href format',
          '/link anyOf',
          '/n minimum',
          '/n if',
          '/at format',
        ]),
      );
      expect(
        explain({'kind': 'a', 'link': <String, Object?>{}, 'at': '2026-09-23'}),
        unorderedEquals(['/link const', '/link required', '/link anyOf']),
      );
      expect(explain(<String, Object?>{}), [' required']);
      expect(
        explain({'kind': 'a', 'link': '', 'n': 0, 'at': '2026-09-23'}),
        isEmpty,
      );
      expect(
        explainErrors(schema, {'kind': 'z'}).first.toString(),
        startsWith('/kind oneOf: '),
      );
    });

    test('conformsTo and validateContract read contracts/schemas/<name>', () {
      contractsDirOverride = root;

      expect(valid(), conformsTo('event'));
      expect({...valid(), 'url': 'nope'}, isNot(conformsTo('event')));
      expect(
        validateContract('event', {...valid(), 'seenAt': '2026-09-23'})
            .errors
            .map((e) => e.instancePath),
        ['/seenAt'],
      );
      expect(conformsTo('event').describe(StringDescription()).toString(),
          'a payload valid against contracts/schemas/event.schema.json');
      expect(contractSchema('event'), same(contractSchema('event')));
      expect(() => contractSchema('missing'), throwsStateError);
    });

    test('an unresolvable ref fails at compile time without any fetch', () {
      final previous = HttpOverrides.current;
      blockedNetworkAttempts.clear();
      installNetworkGuard();
      addTearDown(() => HttpOverrides.global = previous);

      expect(
        () => compileSchema({
          r'$schema': draft2020,
          r'$ref': 'https://contracts.sellwild.com/missing.schema.json',
        }, name: 'self-test', schemasDir: schemas()),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('missing.schema.json'))),
      );
      expect(blockedNetworkAttempts, isEmpty);
    });
  });

  // The checks validate.mjs runs with ajv, run here with the Dart matcher on
  // the real contract files. A failure means the two validators disagree on
  // that schema, so a factory test using conformsTo could pass what ajv fails.
  group('real contracts agree with validate.mjs', () {
    Object? read(File file) => jsonDecode(file.readAsStringSync());

    test('every schema compiles as 2020-12 with its cross-file refs', () {
      final names = schemaNames();
      expect(names, containsAll(['app-config', 'events-batch', 'listing']));
      for (final name in names) {
        expect(contractSchema(name).schemaVersion, SchemaVersion.draft2020_12,
            reason: name);
      }
    });

    test(
        'valid fixtures conform; invalid ones fail at their declared path and keyword',
        () {
      final shapes = fixtureShapes();
      expect(shapes, containsAll(['client-failure-event', 'events-batch']));
      for (final shape in shapes) {
        for (final file in fixtureFiles(shape)) {
          expect(read(file), conformsTo(shape),
              reason: '$shape/valid/${fixtureName(file)}');
        }
        final expected =
            loadExpectedErrors(shape)['errors'] as Map<String, dynamic>;
        for (final file in fixtureFiles(shape, valid: false)) {
          final name = '${fixtureName(file)}.json';
          final want = expected[name] as Map;
          expect(read(file), isNot(conformsTo(shape)),
              reason: '$shape/invalid/$name');
          // validate.mjs's errorMatches: an error at exactly that
          // instancePath, with that keyword when one is given.
          expect(
            contractErrors(shape, read(file)),
            anyElement(isA<ContractError>()
                .having(
                    (e) => e.instancePath, 'instancePath', want['instancePath'])
                .having(
                    (e) => e.keyword, 'keyword', want['keyword'] ?? anything)),
            reason: '$shape/invalid/$name',
          );
        }
      }
    });

    test(
        'a bad uri under an anyOf branch fails app-config and rn-native-config',
        () {
      // app-config LOCALIZED_LISTINGS is anyOf ['', JSON text,
      // localized-listings-config], and baseUrl there has format uri.
      // rn-native-config.remote is a $ref to app-config.
      final config =
          loadFixture('app-config', 'localized-object') as Map<String, dynamic>;
      final native =
          loadFixture('rn-native-config', 'feed') as Map<String, dynamic>;
      expect(config, conformsTo('app-config'));
      expect({...native, 'remote': config}, conformsTo('rn-native-config'));

      (config['LOCALIZED_LISTINGS'] as Map)['baseUrl'] = 'not a uri';
      // ajv rejects both.
      expect(config, isNot(conformsTo('app-config')));
      expect(
          {...native, 'remote': config}, isNot(conformsTo('rn-native-config')));
      expect(
        contractErrors('app-config', config)
            .map((e) => '${e.instancePath} ${e.keyword}'),
        containsAll([
          '/LOCALIZED_LISTINGS anyOf',
          '/LOCALIZED_LISTINGS/baseUrl format',
        ]),
      );
    });

    test('captured samples conform', () {
      final shapes = sampleShapes();
      expect(shapes, containsAll(['app-config', 'listings-response']));
      for (final shape in shapes) {
        for (final file in sampleFiles(shape)) {
          expect(read(file), conformsTo(shape),
              reason: '$shape/${fixtureName(file)}');
        }
      }
    });

    test('golden vector events conform to client-failure-event', () {
      final doc = loadFailureVectors() as Map<String, dynamic>;
      expect(doc['contract'], 'clientFailure');
      final vectors = (doc['vectors'] as List).cast<Map<String, dynamic>>();
      final withEvent = vectors
          .where((v) => (v['expected'] as Map)['event'] != null)
          .toList();
      expect(withEvent, isNotEmpty);
      for (final v in withEvent) {
        expect(
            (v['expected'] as Map)['event'], conformsTo('client-failure-event'),
            reason: v['name'] as String);
      }
    });

    test('failure-codes.json conforms to its schema', () {
      expect(loadFailureCodes(), conformsTo('failure-codes'));
    });
  });

  group('contract emitter', () {
    late Directory schemas;
    late Directory out;

    setUp(() {
      final root = Directory.systemTemp.createTempSync('sellwild-emit-');
      schemas = Directory('${root.path}/schemas')..createSync();
      File('${schemas.path}/events-batch.schema.json').writeAsStringSync('{}');
      out = Directory('${root.path}/out/flutter');
      addTearDown(() => root.deleteSync(recursive: true));
    });

    test('writes <schema>.<variant>.json as pretty JSON', () {
      final file = emitContract(
        'events-batch',
        'failure_default',
        [
          {'n': 1},
        ],
        outDir: out,
        schemasDir: schemas,
      );

      expect(file.path, '${out.path}/events-batch.failure_default.json');
      expect(jsonDecode(file.readAsStringSync()), [
        {'n': 1},
      ]);
      expect(file.readAsStringSync(), contains('\n  {'));
    });

    test('rejects malformed names, unknown schemas and non-JSON payloads', () {
      File emit(String schema, String variant, Object? payload) =>
          emitContract(schema, variant, payload,
              outDir: out, schemasDir: schemas);

      expect(() => emit('events-batch', 'a.b', 1), throwsArgumentError);
      expect(() => emit('Events_Batch', 'a', 1), throwsArgumentError);
      expect(() => emit('app-config', 'a', 1), throwsArgumentError);
      expect(
        () => emit('events-batch', 'a', DateTime(2026)),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(out.existsSync() ? out.listSync() : const [], isEmpty);
    });

    test(
        'output goes to contracts/out/flutter unless SELLWILD_CONTRACT_OUT is set',
        () {
      expect(
        resolveContractOutPath(contractsRoot: '/r/contracts'),
        '/r/contracts/out/flutter',
      );
      expect(
        resolveContractOutPath(
          contractsRoot: '/r/contracts',
          environment: {'SELLWILD_CONTRACT_OUT': '/tmp/contract-out'},
        ),
        '/tmp/contract-out/flutter',
      );
    });

    test('a real fixture round-trips to the directory validate.mjs reads', () {
      // scripts/coverage/flutter.sh then runs validate.mjs --out
      // flutter-harness on this file, so the emit -> ajv route is exercised on
      // every run. It stays out of contracts/out/flutter, where it would hide
      // validate.mjs's "no emitted files" check on factory output.
      final fixture = loadFixture('events-batch', 'with-client-failure');
      final file = emitContract('events-batch', 'harness-roundtrip', fixture,
          outDir: harnessContractOutDir);

      expect(file.parent.path, harnessContractOutDir.path);
      expect(harnessContractOutDir.parent.path, contractOutDir.parent.path);
      expect(jsonDecode(file.readAsStringSync()), fixture);
      expect(fixture, conformsTo('events-batch'));
    });
  });

  group('fixtures', () {
    test('contracts resolve to a sibling of the package root', () {
      expect(
        resolveContractsPath(cwd: '/r/sellwild-sdk/flutter'),
        '/r/sellwild-sdk/contracts',
      );
      // flutter test's cwd is the package root, and contracts/ sits next to it.
      final pubspec = File('${Directory.current.path}/pubspec.yaml');
      expect(pubspec.readAsStringSync(), startsWith('name: sellwild_sdk\n'));
      expect(contractsDir.parent.path, Directory.current.parent.path);
    });

    test('SELLWILD_CONTRACTS_DIR overrides, relative to cwd', () {
      expect(
        resolveContractsPath(
          cwd: '/r/sellwild-sdk/flutter',
          environment: {'SELLWILD_CONTRACTS_DIR': '/elsewhere/contracts/'},
        ),
        '/elsewhere/contracts',
      );
      expect(
        resolveContractsPath(
          cwd: '/r/sellwild-sdk/flutter',
          environment: {'SELLWILD_CONTRACTS_DIR': 'vendor/contracts'},
        ),
        '/r/sellwild-sdk/flutter/vendor/contracts',
      );
    });

    test('paths cannot escape the contracts directory', () {
      expect(
          () => contractsPath('../flutter/pubspec.yaml'), throwsArgumentError);
      expect(() => contractsPath('/etc/hosts'), throwsArgumentError);
    });

    test('a missing file names the path it looked for', () {
      expect(
        () => readContractJson('schemas/no-such.schema.json'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('no-such.schema.json'))),
      );
    });

    test('loaders read the documented paths', () {
      final root = Directory.systemTemp.createTempSync('sellwild-contracts-');
      addTearDown(() {
        contractsDirOverride = null;
        root.deleteSync(recursive: true);
      });
      void write(String relative, String text) => File('${root.path}/$relative')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
      void json(String relative, Object? value) =>
          write(relative, jsonEncode(value));

      json('schemas/y.schema.json', {'from': 'schema y'});
      json('schemas/x.schema.json', {'from': 'schema x'});
      json('fixtures/x/valid/b.json', {'from': 'valid b'});
      json('fixtures/x/valid/a.json', {'from': 'valid a'});
      write('fixtures/x/valid/notes.txt', 'not a fixture');
      json('fixtures/x/invalid/c.json', {'from': 'invalid c'});
      json('fixtures/x/invalid/_expected-errors.json', {
        'errors': {
          'c.json': {'instancePath': ''},
        },
      });
      json('samples/x/s.json', {'from': 'sample'});
      write('samples/x/s.headers.txt', 'HTTP/1.1 200 OK');
      json('expectations/x.expected.json', {'from': 'expectations'});
      json('golden/log-failure.vectors.json', {'from': 'vectors'});
      json('failure-codes.json', [
        {'from': 'codes'},
      ]);
      contractsDirOverride = root;

      expect(contractsDir.path, root.path);
      expect(loadSchema('x'), {'from': 'schema x'});
      expect(loadFixture('x', 'a'), {'from': 'valid a'});
      expect(loadFixture('x', 'c', valid: false), {'from': 'invalid c'});
      expect(loadExpectedErrors('x')['errors'], contains('c.json'));
      expect(loadSample('x', 's'), {'from': 'sample'});
      expect(loadExpectations('x'), {'from': 'expectations'});
      expect(loadFailureVectors(), {'from': 'vectors'});
      expect(loadFailureCodes(), [
        {'from': 'codes'},
      ]);
      expect(schemaNames(), ['x', 'y']);
      expect(fixtureShapes(), ['x']);
      expect(sampleShapes(), ['x']);
      // Sorted, JSON only, and _expected-errors.json skipped like validate.mjs.
      expect(fixtureFiles('x').map(fixtureName), ['a', 'b']);
      expect(fixtureFiles('x', valid: false).map(fixtureName), ['c']);
      expect(sampleFiles('x').map(fixtureName), ['s']);
      expect(
        () => readContractObject('failure-codes.json'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('expected a JSON object'))),
      );
      expect(
        () => fixtureFiles('nope'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('fixtures/nope/valid'))),
      );
    });

    test('each load of the real golden vectors is a fresh copy', () {
      final first = loadFailureVectors() as Map<String, dynamic>;
      expect(first['contract'], 'clientFailure');
      first['contract'] = 'changed';
      expect((loadFailureVectors() as Map)['contract'], 'clientFailure');
    });

    test('fixtureName strips the directory and extension', () {
      expect(fixtureName(File('/x/fixtures/app-config/valid/weatherbug.json')),
          'weatherbug');
    });
  });
}
