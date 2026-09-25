// Captures what logFailure emits, so a test can assert the exact code fired
// exactly once. Every failure goes to this sink instead of the shared
// SellwildAPIClient.instance, which flutter_test_config.dart blocks.
//
// The sink sits behind logFailure's gate, and the fixed clock keeps every
// repeat inside the gate's 60 s dedupe window, so a failure logged twice
// still reaches the sink once. captureFailures therefore also fails the test
// at tearDown when the gate folded a repeat (rule 2: log once). A test that
// logs a repeat on purpose passes allowFolds: true.

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

/// The failure events logFailure emitted since the call. A fixed clock and
/// uid keep the events deterministic. A null [partnerCode] keeps the current
/// one (configure sets its own).
List<ClientFailureEvent> captureFailures({
  String? partnerCode = 'weatherbug',
  bool allowFolds = false,
}) {
  final events = <ClientFailureEvent>[];
  SellwildFailures.setContext(
    partnerCode: partnerCode,
    clock: () => 1790000000000,
    uid: () => 'u-test',
    sink: (event, flushNow) async => events.add(event),
  );
  if (!allowFolds) addTearDown(expectNoFoldedRepeats);
  return events;
}

/// The gate keys that folded a repeat, as `key (+n)`.
List<String> foldedRepeats() => [
      for (final k in SellwildFailures.gateState.keys)
        if (k.suppressed > 0) '${k.key} (+${k.suppressed})',
    ];

/// Fails when logFailure's gate folded a repeat since the last reset: the
/// same failure was logged more than once.
void expectNoFoldedRepeats() {
  expect(foldedRepeats(), isEmpty,
      reason: 'a failure was logged more than once (rule 2: log once)');
}

/// Ends one case of a loop: fails on a folded repeat, then clears the gate
/// (and the context) for the next case. A plain resetForTests would hide a
/// repeat from the tearDown check.
void endFailureCase() {
  expectNoFoldedRepeats();
  SellwildFailures.resetForTests();
}

/// The actions (failure codes) of [events], in order.
List<String> actionsOf(List<ClientFailureEvent> events) =>
    events.map((e) => e.action).toList();
