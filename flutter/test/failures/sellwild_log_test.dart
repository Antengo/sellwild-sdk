// SellwildLog (FAILURES.md section 2): a no-op unless the SDK debug flag is
// on, and the message is not even built while it is off.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/failures/sellwild_log.dart';

void main() {
  test('off: nothing is built or printed', () {
    final printed = <String>[];
    SellwildLog.printer = printed.add;
    var built = 0;

    SellwildLog.debug(() => 'line ${++built}');

    expect(printed, isEmpty);
    expect(built, 0);
  });

  test('on: the line goes to the printer', () {
    final printed = <String>[];
    SellwildLog.printer = printed.add;
    SellwildLog.enabled = true;

    SellwildLog.debug(() => 'trace');

    expect(printed, ['trace']);
  });

  test('SellwildFailures.setContext(debug:) switches it', () {
    SellwildFailures.setContext(debug: true);
    expect(SellwildLog.enabled, isTrue);

    SellwildFailures.setContext(debug: false);
    expect(SellwildLog.enabled, isFalse);
  });

  test('the default printer is debugPrint', () {
    final previous = debugPrint;
    final lines = <String?>[];
    debugPrint = (message, {wrapWidth}) => lines.add(message);
    addTearDown(() => debugPrint = previous);
    SellwildLog.resetForTests();
    SellwildLog.enabled = true;

    SellwildLog.debug(() => '[Sellwild] trace');

    expect(lines, ['[Sellwild] trace']);
  });
}
