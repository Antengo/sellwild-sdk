// Runs around every test file (flutter_test picks it up by name).
//
// Tests never touch the network (contract amendment A8):
//   1. Real dart:io HttpClients are blocked (support/network_guard.dart). In
//      files that use testWidgets, flutter_test's own HttpOverrides (every
//      request answers 400) replace the guard when the binding starts.
//   2. SellwildAPIClient.instance, which logFailure sends through by default,
//      starts on a MockClient that records every request instead of posting
//      to events.sellwild.com. A test that sends through it without
//      installing its own client fails in tearDown, naming the requests.
//      Tests that need the shared client replace it and put this one back.
//   3. logFailure's gate state and context, and the shared client's partner
//      and kill switch, are reset after each test.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'support/network_guard.dart';

/// Requests that reached the default SellwildAPIClient.instance.
final List<http.Request> unexpectedSharedClientRequests = [];

/// The instance every test file starts with.
final SellwildAPIClient blockedSharedClient = SellwildAPIClient(
  client: MockClient((request) async {
    unexpectedSharedClientRequests.add(request);
    return http.Response('', 599);
  }),
);

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  installNetworkGuard();
  SellwildAPIClient.instance = blockedSharedClient;
  tearDown(() {
    SellwildFailures.resetForTests();
    SellwildAPIClient.instance = blockedSharedClient
      ..partnerCode = null
      ..eventsEnabled = true;
    if (unexpectedSharedClientRequests.isEmpty) return;
    final sent = unexpectedSharedClientRequests
        .map((r) => '${r.method} ${r.url}')
        .toList();
    unexpectedSharedClientRequests.clear();
    fail('A test sent $sent through the shared SellwildAPIClient.instance. '
        'Inject a sink (SellwildFailures.setContext) or a client.');
  });
  await testMain();
}
