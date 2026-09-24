// The pure core against contracts/golden (FAILURES.md section 12): every
// vector in log-failure.vectors.json and log-failure.utf16.vectors.json must
// give the same event (keys in wire order), flushNow, reason and stateAfter
// as the reference, and every `units` row the same result.

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/src/failures/failures_core.dart';

import '../support/contract_schemas.dart';
import '../support/fixtures.dart';

FailureInput inputFrom(Map<String, dynamic> json) => FailureInput(
      code: json['code'],
      component: json['component'],
      severity: json['severity'],
      errName: json['errName'],
      errMessage: json['errMessage'],
      message: json['message'],
      stack: json['stack'],
      httpStatus: json['httpStatus'],
      url: json['url'],
      zoneId: json['zoneId'],
    );

FailureContext contextFrom(Map<String, dynamic> json) => FailureContext(
      partnerCode: json['partnerCode'],
      client: json['client'],
      clientVersion: json['clientVersion'],
      wrapper: json['wrapper'],
      release: json['release'],
      eventsEnabled: json['eventsEnabled'],
      failuresEnabled: json['failuresEnabled'],
      failuresSampleRate: json['failuresSampleRate'],
    );

FailureState stateFrom(Map<String, dynamic> json) => FailureState(
      sessionCount: json['sessionCount'] as int,
      keys: [
        for (final k in (json['keys'] as List).cast<Map<String, dynamic>>())
          FailureKeyEntry(
            key: k['key'] as String,
            lastEmitAt: k['lastEmitAt'] as int,
            suppressed: k['suppressed'] as int,
            emits: k['emits'] as int,
          ),
      ],
    );

Map<String, Object> stateJson(FailureState state) => {
      'sessionCount': state.sessionCount,
      'keys': [
        for (final k in state.keys)
          {
            'key': k.key,
            'lastEmitAt': k.lastEmitAt,
            'suppressed': k.suppressed,
            'emits': k.emits,
          },
      ],
    };

void runVectors(String file) {
  final doc = readContractObject('golden/$file');
  final vectors = (doc['vectors'] as List).cast<Map<String, dynamic>>();

  test('$file has vectors', () => expect(vectors, isNotEmpty));

  for (final v in vectors) {
    test(v['name'], () {
      final context = v['context'] as Map<String, dynamic>;
      final expected = v['expected'] as Map<String, dynamic>;

      final decision = decideFailure(
        stateFrom(v['stateBefore'] as Map<String, dynamic>),
        inputFrom(v['input'] as Map<String, dynamic>),
        contextFrom(context),
        context['uid'],
        context['now'] as int,
      );

      final event = expected['event'] as Map<String, dynamic>?;
      if (event == null) {
        expect(decision.event, isNull);
      } else {
        final actual = decision.event!.toJson();
        expect(actual, event);
        // Wire order (FAILURES.md 6.3), which deep equality ignores.
        expect((actual['attributes'] as Map).keys.toList(),
            (event['attributes'] as Map).keys.toList());
        expect(actual, conformsTo('client-failure-event'));
      }
      expect(decision.flushNow, expected['flushNow']);
      expect(decision.reason, expected['reason']);
      expect(stateJson(decision.state), expected['stateAfter']);
    });
  }
}

typedef Unit = Object? Function(Object? input);

void runUnits(String file, Map<String, Unit> functions) {
  final doc = readContractObject('golden/$file');
  final units = doc['units'] as Map<String, dynamic>;

  test('$file units are all ported', () {
    expect(functions.keys.toSet(), containsAll(units.keys));
  });

  units.forEach((name, rows) {
    final fn = functions[name];
    if (fn == null) return;
    group(name, () {
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        test('${row['input']}', () {
          expect(fn(row['input']), row['expected']);
        });
      }
    });
  });
}

final Map<String, Unit> unitFunctions = {
  'fnv1a32': fnv1a32,
  'truncateUnicode': (args) {
    final list = args as List;
    return truncateUnicode(list[0] as String, list[1] as int);
  },
  'hostOf': hostOf,
  'sanitizeMessage': sanitizeMessage,
  'coerceFlag': coerceFlag,
  'coerceRate': coerceRate,
  'normalizeCode': normalizeCode,
  'normalizeHttpStatus': normalizeHttpStatus,
};

void main() {
  group('log-failure.vectors.json', () {
    runVectors('log-failure.vectors.json');
    runUnits('log-failure.vectors.json', unitFunctions);
  });

  group('log-failure.utf16.vectors.json', () {
    runVectors('log-failure.utf16.vectors.json');
    runUnits('log-failure.utf16.vectors.json', unitFunctions);
  });

  test('limits match the vectors file', () {
    final limits =
        readContractObject('golden/log-failure.vectors.json')['limits']
            as Map<String, dynamic>;

    expect(limits, {
      'codeMax': FailureLimits.codeMax,
      'errName': FailureLimits.errName,
      'msg': FailureLimits.msg,
      'msgBudget': FailureLimits.msgBudget,
      'msgKey': FailureLimits.msgKey,
      'stack': FailureLimits.stack,
      'stackFrames': FailureLimits.stackFrames,
      'zoneId': FailureLimits.zoneId,
      'host': FailureLimits.host,
      'partnerCode': FailureLimits.partnerCode,
      'clientVersion': FailureLimits.clientVersion,
      'release': FailureLimits.release,
      'maxAttributes': failureAttributeKeys.length,
      'eventBytes': FailureLimits.eventBytes,
      'dedupeWindowMs': FailureLimits.dedupeWindowMs,
      'lruSize': FailureLimits.lruSize,
      'perKeyEmits': FailureLimits.perKeyEmits,
      'sessionEmits': FailureLimits.sessionEmits,
    });
  });
}
