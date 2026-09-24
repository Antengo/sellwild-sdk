// The SDK's debug logger (contracts/FAILURES.md section 2). One of the two
// Flutter files allowed to print: every call is a no-op unless [enabled],
// which SellwildFailures.setContext keeps equal to the SDK debug flag
// (SellwildConfig.debug).
//
// Trace output only. A failure is never handled by printing it here: it goes
// to SellwildFailures.log, whose debug echo is the one failure line printed
// through [SellwildLog.debug].

import 'package:flutter/foundation.dart';

abstract final class SellwildLog {
  /// Whether [debug] prints. Follows the SDK debug flag.
  static bool enabled = false;

  /// Where lines go: debugPrint in the SDK; tests capture them.
  @visibleForTesting
  static void Function(String line) printer = _debugPrint;

  /// Builds and prints the line only when [enabled], so callers pay nothing
  /// when it is off.
  static void debug(String Function() message) {
    if (enabled) printer(message());
  }

  /// Tests only; SellwildFailures.resetForTests calls it.
  static void resetForTests() {
    enabled = false;
    printer = _debugPrint;
  }
}

void _debugPrint(String line) => debugPrint(line);
