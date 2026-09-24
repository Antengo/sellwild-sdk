// Pure-core cases the golden vectors cannot express: Dart doubles that
// JavaScript would see as integers (JSON `503.0`), ints past 2^53, the
// canonical JSON escapes, and the helpers the shell uses.

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/src/failures/failures_core.dart';

void main() {
  group('integral doubles read as JavaScript numbers', () {
    test('normalizeHttpStatus', () {
      expect(normalizeHttpStatus(503.0), '503');
      expect(normalizeHttpStatus(99.0), isNull);
      expect(normalizeHttpStatus(1000.0), isNull);
      expect(normalizeHttpStatus(double.nan), isNull);
      expect(normalizeHttpStatus(double.infinity), isNull);
      expect(normalizeHttpStatus(true), isNull);
    });

    test('normalizeZoneId keeps safe integers only', () {
      expect(normalizeZoneId(43.0), '43');
      expect(normalizeZoneId(-0.0), '0');
      expect(normalizeZoneId(1e20), isNull);
      expect(normalizeZoneId(43.5), isNull);
      expect(normalizeZoneId(9007199254740991), '9007199254740991');
      expect(normalizeZoneId(-9007199254740991), '-9007199254740991');
      expect(normalizeZoneId(9007199254740992), isNull);
      expect(normalizeZoneId(false), isNull);
      expect(normalizeZoneId(' 43 '), '43');
    });
  });

  group('canonicalJson (FAILURES.md 6.4)', () {
    const event = ClientFailureEvent(
      action: 'a.b.c',
      label: 'listings',
      // Not in wire order on purpose.
      attributes: {'code': 'w', 'seq': '1', 'msg': 'é😀/'},
      uid: 'q"b\\c\b\f\n\r\t\u0001\u001f',
      createdTime: 1790000000000,
    );

    test('matches the reference: wire order, minimal escapes', () {
      // contracts/reference/log-failure.mjs canonicalJson on the same event.
      expect(
        canonicalJson(event),
        '{"event":"clientFailure","action":"a.b.c","label":"listings",'
        '"attributes":{"code":"w","msg":"é😀/","seq":"1"},'
        r'"uid":"q\"b\\c\b\f\n\r\t\u0001\u001f",'
        '"createdTime":1790000000000}',
      );
    });

    test('size is UTF-8 bytes', () => expect(eventByteSize(event), 179));
  });

  group('helpers', () {
    test('coerceFlag uses the given default for unset values', () {
      expect(coerceFlag(null, false), isFalse);
      expect(coerceFlag(const <Object>[], false), isFalse);
      expect(coerceFlag('yes', false), isTrue);
    });

    test('non-string uids and inputs', () {
      expect(fnv1a32(42), fnv1a32(''));
      expect(isSampled(42, 0.5), isSampled('', 0.5));
      expect(cleanText(42), '');
      expect(hostOf(42), isNull);
      expect(sanitizeStack(42, null), isNull);
    });

    test('sanitizeStack keeps the first line when errName is empty', () {
      expect(sanitizeStack('Error: x\nat f (a/b.js:1:2)', ''),
          'Error: x\nat f (b.js:1:2)');
      expect(sanitizeStack('Error: x\nat f (a/b.js:1:2)', 'Error'),
          'at f (b.js:1:2)');
    });

    test('messageFull joins message and error message once', () {
      expect(messageFull(const FailureInput(message: 'a', errMessage: 'b')),
          'a: b');
      expect(
          messageFull(const FailureInput(message: 'a', errMessage: 'a')), 'a');
      expect(messageFull(const FailureInput(errMessage: 'jane@example.com')),
          '<email>');
      expect(messageFull(const FailureInput()), '');
    });

    test('echoLine names the outcome and the sanitized message', () {
      const input = FailureInput(
        code: 'listings.fetch.http',
        component: 'listings',
        severity: 'warn',
        message: 'GET https://cache.sellwild.com/x?q=1 failed',
      );

      expect(
          echoLine(input, null),
          '[Sellwild] failure listings.fetch.http listings warn sent '
          'GET cache.sellwild.com failed');
      expect(echoLine(const FailureInput(code: 'x'), 'sampled_out'),
          '[Sellwild] failure client.code.invalid unknown error sampled_out');
    });

    test('dedupeKey uses the first 64 code points of the message', () {
      final long = '😀' * 70;

      expect(dedupeKey('a.b.c', 'listings', null, long),
          'a.b.c|listings||${'😀' * 64}');
    });

    test('FailureState.initial is empty', () {
      expect(FailureState.initial.sessionCount, 0);
      expect(FailureState.initial.keys, isEmpty);
    });
  });
}
