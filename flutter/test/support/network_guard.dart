// Loud block on real HTTP for tests (contract amendment A8).
//
// flutter_test only swaps in its own HttpOverrides (every request answers 400)
// once a TestWidgetsFlutterBinding exists, i.e. in files that use testWidgets
// or call ensureInitialized. A plain test() file gets the real dart:io
// HttpClient. installNetworkGuard() closes that gap: any dart:io HttpClient,
// including the one behind package:http's default http.Client(), throws
// RealNetworkAccessError on first use and the attempt is recorded.
//
// SDK code under test should get an injected MockClient (see http_mocks.dart);
// the guard only catches code that forgot to take one.

import 'dart:io';

/// One blocked attempt to use a real dart:io HttpClient.
class BlockedNetworkAttempt {
  const BlockedNetworkAttempt(this.member, this.arguments);

  /// HttpClient member that was called, e.g. `openUrl`.
  final String member;
  final List<Object?> arguments;

  @override
  String toString() => '$member(${arguments.join(', ')})';
}

class RealNetworkAccessError extends Error {
  RealNetworkAccessError(this.attempt);

  final BlockedNetworkAttempt attempt;

  @override
  String toString() => 'RealNetworkAccessError: a test tried to use a real '
      'HttpClient ($attempt). Inject an http.Client (test/support/http_mocks.dart).';
}

/// Every attempt blocked since the guard was installed or last cleared.
final List<BlockedNetworkAttempt> blockedNetworkAttempts = [];

class NetworkGuardOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedHttpClient();
}

/// Makes every new dart:io HttpClient in this isolate a blocked one.
void installNetworkGuard() {
  HttpOverrides.global = NetworkGuardOverrides();
}

class _BlockedHttpClient implements HttpClient {
  // Closing is harmless and code under test closes clients it owns in a
  // finally block; throwing there would hide the real attempt.
  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final attempt = BlockedNetworkAttempt(
      _memberName(invocation.memberName),
      invocation.positionalArguments,
    );
    blockedNetworkAttempts.add(attempt);
    throw RealNetworkAccessError(attempt);
  }

  // Symbol has no public name accessor; its toString is `Symbol("name")`.
  static String _memberName(Symbol symbol) {
    final text = symbol.toString();
    final match = RegExp(r'^Symbol\("(.*)"\)$').firstMatch(text);
    return match?.group(1) ?? text;
  }
}
