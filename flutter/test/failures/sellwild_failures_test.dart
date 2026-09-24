// The logFailure shell (FAILURES.md 3.4): context, error mapping, the
// never-throw wrapper, the reentrancy guard, the debug echo, kill switches
// and the default route through SellwildAPIClient.instance.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/failures/sellwild_log.dart';

import '../flutter_test_config.dart' show blockedSharedClient;
import '../support/contract_schemas.dart';
import '../support/http_mocks.dart';

const int now = 1790000000000;
const String uid = '8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11';

/// Records what the shell hands to its sink.
class SinkRecorder {
  final List<ClientFailureEvent> events = [];
  final List<bool> flushes = [];

  Future<void> call(ClientFailureEvent event, bool flushNow) async {
    events.add(event);
    flushes.add(flushNow);
  }

  Map<String, String> get attributes => events.single.attributes;
}

class NoMessageException implements Exception {}

class ThrowingToString implements Exception {
  @override
  String toString() => throw StateError('toString failed');
}

SinkRecorder useRecorder({String? partnerCode = 'weatherbug'}) {
  final sink = SinkRecorder();
  SellwildFailures.setContext(
    partnerCode: partnerCode,
    clock: () => now,
    uid: () => uid,
    sink: sink.call,
  );
  return sink;
}

void logListingsHttp() => SellwildFailures.log(
      code: SellwildFailureCode.listingsFetchHttp,
      component: SellwildFailureComponent.listings,
      message: 'HTTP 503',
      httpStatus: 503,
      url: 'https://cache.sellwild.com/listings-img-data-sm?v=2',
      zoneId: '43',
    );

void main() {
  late List<String> printed;

  setUp(() {
    printed = [];
    SellwildLog.printer = printed.add;
  });

  group('SellwildFailures.log', () {
    test('sends one event with the context, uid and clock', () {
      final sink = useRecorder();

      logListingsHttp();

      final event = sink.events.single;
      expect(event.toJson(), {
        'event': 'clientFailure',
        'action': 'listings.fetch.http',
        'label': 'listings',
        'attributes': {
          'code': 'weatherbug',
          'client': 'flutter',
          'clientVersion': sellwildSdkVersion,
          'severity': 'error',
          'fv': '1',
          'msg': 'HTTP 503',
          'httpStatus': '503',
          'host': 'cache.sellwild.com',
          'zoneId': '43',
          'seq': '1',
          'repeat': '1',
        },
        'uid': uid,
        'createdTime': now,
      });
      expect(event.toJson(), conformsTo('client-failure-event'));
      expect(sink.flushes, [true]);
      expect(SellwildFailures.gateState.sessionCount, 1);
    });

    test('the first event of the session and fatal ones flush at once', () {
      final sink = useRecorder();

      logListingsHttp();
      SellwildFailures.log(
          code: SellwildFailureCode.configFetchHttp,
          component: SellwildFailureComponent.remoteConfig);
      SellwildFailures.log(
          code: SellwildFailureCode.configApplyException,
          component: SellwildFailureComponent.configure,
          severity: SellwildFailureSeverity.fatal);

      expect(sink.flushes, [true, false, true]);
    });

    test('the same failure inside a minute is folded into the next one', () {
      final sink = useRecorder();

      logListingsHttp();
      logListingsHttp();

      expect(sink.events, hasLength(1));
      expect(SellwildFailures.gateState.keys.single.suppressed, 1);
    });

    test('wrapper and clientVersion from the context are sent', () {
      final sink = useRecorder();
      SellwildFailures.setContext(wrapper: 'flutter', clientVersion: '9.9.9');

      logListingsHttp();

      expect(sink.attributes['wrapper'], 'flutter');
      expect(sink.attributes['clientVersion'], '9.9.9');
    });

    test('no partner yet sends code unknown', () {
      final sink = useRecorder(partnerCode: null);

      logListingsHttp();

      expect(sink.attributes['code'], 'unknown');
    });
  });

  group('error mapping (FAILURES.md 3.3)', () {
    Map<String, String> logError(Object error, {String? message}) {
      final sink = useRecorder();
      SellwildFailures.log(
        code: SellwildFailureCode.listingsFetchNetwork,
        component: SellwildFailureComponent.listings,
        error: error,
        message: message,
      );
      return sink.attributes;
    }

    test('an exception gives its type name and message', () {
      final cases = <Object, (String, String)>{
        const FormatException('Unexpected character'): (
          'FormatException',
          'Unexpected character'
        ),
        http.ClientException('Connection refused'): (
          'ClientException',
          'Connection refused'
        ),
        TimeoutException('config GET', const Duration(seconds: 5)): (
          'TimeoutException',
          'config GET'
        ),
        const SocketException('Failed host lookup'): (
          'SocketException',
          'Failed host lookup'
        ),
        const HttpException('Connection closed'): (
          'HttpException',
          'Connection closed'
        ),
        SellwildException('HTTP 503 from cache'): (
          'SellwildException',
          'HTTP 503 from cache'
        ),
        StateError('closed'): ('StateError', 'closed'),
      };
      cases.forEach((error, expected) {
        SellwildFailures.resetForTests();
        final attributes = logError(error);
        expect(attributes['errName'], expected.$1, reason: '$error');
        expect(attributes['msg'], expected.$2, reason: '$error');
      });
    });

    test('an exception without a message falls back to toString()', () {
      final noMessage = logError(TimeoutException(null));
      expect(noMessage['errName'], 'TimeoutException');
      expect(noMessage['msg'], 'TimeoutException');

      SellwildFailures.resetForTests();
      final custom = logError(NoMessageException());
      expect(custom['errName'], 'NoMessageException');
      expect(custom['msg'], "Instance of 'NoMessageException'");

      SellwildFailures.resetForTests();
      final empty = logError(const FormatException(''));
      expect(empty['msg'], 'FormatException');
    });

    test('a thrown string is the message, with no type name', () {
      final attributes = logError('socket closed');

      expect(attributes.containsKey('errName'), isFalse);
      expect(attributes['msg'], 'socket closed');
    });

    test('message and error message are joined and sanitized', () {
      final attributes = logError(
        http.ClientException('Failed host lookup: https://jane@x.io/p?q=1'),
        message: 'fetch 1234567 failed',
      );

      expect(attributes['msg'], 'fetch <n> failed: Failed host lookup: x.io');
    });

    test('a throwing toString is counted and the report still goes out', () {
      final attributes = logError(ThrowingToString());

      expect(attributes['errName'], 'ThrowingToString');
      expect(attributes.containsKey('msg'), isFalse);
      expect(SellwildFailures.internalErrorCount, 1);
    });

    test('a very long message is cut before sanitizing; 200 are sent', () {
      final attributes = logError('boom', message: 'x' * 5000);

      expect(attributes['msg']!.runes, hasLength(200));
      expect(attributes['msg'], endsWith('…'));
    });

    test('the core sees at most 1000 units of message and of error', () {
      // 998 digits sanitize to "<n>", so what follows them would be sent.
      // Only the 2 letters within the first 1000 units may reach the core.
      final long = '${'1' * 998}ABCDEFG';

      final attributes = logError(StateError(long), message: long);

      expect(attributes['msg'], '<n>AB');
    });
  });

  group('never throws, never recurses (FAILURES.md 3.4)', () {
    test('a sink that throws is counted', () {
      SellwildFailures.setContext(
          clock: () => now,
          uid: () => uid,
          sink: (event, flushNow) => throw StateError('sink down'));

      expect(logListingsHttp, returnsNormally);
      expect(SellwildFailures.internalErrorCount, 1);
    });

    test('a sink whose future fails is counted once it fails', () async {
      final failed = Completer<void>();
      SellwildFailures.setContext(
          clock: () => now,
          uid: () => uid,
          sink: (event, flushNow) => failed.future);

      logListingsHttp();
      expect(SellwildFailures.internalErrorCount, 0);
      failed.completeError(http.ClientException('offline'));
      await pumpEventQueue();

      expect(SellwildFailures.internalErrorCount, 1);
    });

    test('a clock or uid that throws is counted and nothing is sent', () {
      final sink = useRecorder();
      SellwildFailures.setContext(clock: () => throw StateError('no clock'));

      expect(logListingsHttp, returnsNormally);
      SellwildFailures.setContext(
          clock: () => now, uid: () => throw StateError('no uid'));
      expect(logListingsHttp, returnsNormally);

      expect(sink.events, isEmpty);
      expect(SellwildFailures.internalErrorCount, 2);
      expect(SellwildFailures.gateState.sessionCount, 0);
    });

    test('a nested call from inside log is ignored', () {
      var calls = 0;
      SellwildFailures.setContext(
        clock: () => now,
        uid: () => uid,
        sink: (event, flushNow) async {
          calls++;
          SellwildFailures.log(
              code: SellwildFailureCode.configFetchNetwork,
              component: SellwildFailureComponent.remoteConfig);
        },
      );

      logListingsHttp();

      expect(calls, 1);
      expect(SellwildFailures.gateState.sessionCount, 1);
      // The guard is released afterwards: the next call is decided.
      SellwildFailures.log(
          code: SellwildFailureCode.configFetchNetwork,
          component: SellwildFailureComponent.remoteConfig);
      expect(calls, 2);
    });

    test('a printer that throws during the echo is counted twice at most', () {
      useRecorder();
      SellwildFailures.setContext(debug: true);
      SellwildLog.printer = (line) => throw StateError('printer down');

      expect(logListingsHttp, returnsNormally);

      // Once for the echo, once for the internal-error echo that also threw.
      expect(SellwildFailures.internalErrorCount, 2);
    });
  });

  group('debug echo (FAILURES.md 2)', () {
    test('prints one sanitized line per call only when debug is on', () {
      useRecorder();

      logListingsHttp();
      expect(printed, isEmpty);

      SellwildFailures.setContext(debug: true);
      SellwildFailures.log(
        code: SellwildFailureCode.listingsFetchNetwork,
        component: SellwildFailureComponent.listings,
        message: 'lookup https://cache.sellwild.com/x?uid=jane@example.com',
      );
      logListingsHttp();
      SellwildFailures.log(
          code: 'Not A Code', component: SellwildFailureComponent.listings);

      expect(printed, [
        '[Sellwild] failure listings.fetch.network listings error sent '
            'lookup cache.sellwild.com',
        '[Sellwild] failure listings.fetch.http listings error deduped '
            'HTTP 503',
        '[Sellwild] failure client.code.invalid listings error sent',
      ]);
    });

    test('echoes an internal error by type only', () {
      SellwildFailures.setContext(
          debug: true,
          clock: () => now,
          uid: () => uid,
          sink: (event, flushNow) => throw StateError('sink down'));

      logListingsHttp();

      expect(printed, ['[Sellwild] failure internal-error StateError']);
    });
  });

  group('kill switches (FAILURES.md 5.3, 5.4)', () {
    test('EVENTS_ENABLED off drops even fatal failures', () {
      final sink = useRecorder();
      SellwildFailures.setContext(eventsEnabled: false);

      SellwildFailures.log(
          code: SellwildFailureCode.configFetchHttp,
          component: SellwildFailureComponent.remoteConfig,
          severity: SellwildFailureSeverity.fatal);

      expect(sink.events, isEmpty);
    });

    test('FAILURES_ENABLED "off" drops failures', () {
      final sink = useRecorder();
      SellwildFailures.setContext(failuresEnabled: 'off');

      logListingsHttp();

      expect(sink.events, isEmpty);
    });

    test('sample rate 0 drops all but fatal failures', () {
      final sink = useRecorder();
      SellwildFailures.setContext(failuresSampleRate: 0.0);

      logListingsHttp();
      SellwildFailures.log(
          code: SellwildFailureCode.configFetchHttp,
          component: SellwildFailureComponent.remoteConfig,
          severity: SellwildFailureSeverity.fatal);

      expect(sink.events.single.attributes['severity'], 'fatal');
    });
  });

  group('context', () {
    test('a null argument keeps the current value', () {
      final sink = useRecorder();
      SellwildFailures.setContext(
          eventsEnabled: true, failuresSampleRate: 0.5, debug: true);

      SellwildFailures.setContext(partnerCode: 'antengo');

      final c = SellwildFailures.context;
      expect(c.partnerCode, 'antengo');
      expect(c.eventsEnabled, isTrue);
      expect(c.failuresSampleRate, 0.5);
      expect(c.debug, isTrue);
      expect(c.sink, isNotNull);
      expect(c.clientVersion, sellwildSdkVersion);
      expect(SellwildLog.enabled, isTrue);
      expect(sink.events, isEmpty);
    });

    test('resetForTests clears context, state, counters and SellwildLog', () {
      useRecorder();
      SellwildFailures.setContext(debug: true, sink: (e, f) => throw 'x');
      logListingsHttp();
      expect(SellwildFailures.internalErrorCount, 1);

      SellwildFailures.resetForTests();

      final c = SellwildFailures.context;
      expect(c.partnerCode, isNull);
      expect(c.debug, isFalse);
      expect(c.sink, isNull);
      expect(c.clock, isNull);
      expect(c.uid, isNull);
      expect(SellwildFailures.internalErrorCount, 0);
      expect(SellwildFailures.gateState.sessionCount, 0);
      expect(SellwildLog.enabled, isFalse);
      expect(SellwildLog.printer, isNot(same(printed.add)));
    });
  });

  group('default route: SellwildAPIClient.instance (FAILURES.md 8)', () {
    late HttpRecorder events;

    setUp(() {
      events = HttpRecorder.status(200);
      SellwildAPIClient.instance = SellwildAPIClient(
          client: events.client, uid: 'queue-uid', clock: () => 1);
    });

    tearDown(() => SellwildAPIClient.instance = blockedSharedClient);

    test('posts the event with the queue uid and the wall clock', () async {
      SellwildFailures.setContext(partnerCode: 'weatherbug');
      final before = DateTime.now().millisecondsSinceEpoch;

      logListingsHttp();
      await pumpEventQueue();

      final after = DateTime.now().millisecondsSinceEpoch;
      final request = events.single;
      expect(request.method, 'POST');
      expect(
          request.url.toString(), 'https://events.sellwild.com/events/queue');
      final batch = events.jsonBody() as List;
      expect(batch, conformsTo('events-batch'));
      final event = batch.single as Map<String, dynamic>;
      expect(event['event'], 'clientFailure');
      expect(event['uid'], 'queue-uid');
      expect(event['createdTime'], inInclusiveRange(before, after));
      expect(event['attributes'], {
        'code': 'weatherbug',
        'client': 'flutter',
        'clientVersion': sellwildSdkVersion,
        'severity': 'error',
        'fv': '1',
        'msg': 'HTTP 503',
        'httpStatus': '503',
        'host': 'cache.sellwild.com',
        'zoneId': '43',
        'seq': '1',
        'repeat': '1',
        'type': 'flutter',
        'sdkVersion': sellwildSdkVersion,
      });
    });

    test('the events uid decides sampling', () async {
      // fnv1a32('queue-uid:failures') / 2^32 is about 0.0135: out at a rate
      // of 0.01, in at 0.02.
      SellwildFailures.setContext(failuresSampleRate: 0.01);
      logListingsHttp();
      await pumpEventQueue();
      expect(events.requests, isEmpty);

      SellwildFailures.setContext(failuresSampleRate: 0.02);
      logListingsHttp();
      await pumpEventQueue();
      expect(events.requests, hasLength(1));
    });
  });
}
