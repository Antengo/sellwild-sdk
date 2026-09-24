// Factories for what the Flutter SDK sends: clientFailure events and the
// events batch POSTed to events.sellwild.com/events/queue. Besides the
// contracts fixtures, variants are produced by the SDK code itself (the pure
// core, the logFailure shell, and SellwildAPIClient.sendEvent's POST body
// captured by a MockClient), so the schema check covers the real output.

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/failures/failures_core.dart';

import '../flutter_test_config.dart' show blockedSharedClient;
import '../support/fixtures.dart';
import '../support/http_mocks.dart';
import 'contract_factory.dart';

const int factoryNow = 1790000000000;
const String factoryUid = '8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11';

/// One clientFailure event. Base:
/// fixtures/client-failure-event/valid/listings-http.json.
class ClientFailureEventFactory extends JsonObjectFactory {
  ClientFailureEventFactory()
      : super('client-failure-event',
            'fixtures/client-failure-event/valid/listings-http.json');

  /// The base as the Flutter SDK would stamp it.
  Map<String, dynamic> flutter() {
    final out = build({'_synthetic': remove});
    (out['attributes'] as Map<String, dynamic>)
      ..['client'] = 'flutter'
      ..['clientVersion'] = sellwildSdkVersion;
    return out;
  }

  /// What the pure core emits for a missing remote config (S3 answers 403).
  Map<String, Object> coreConfigHttp() => decideFailure(
        FailureState.initial,
        const FailureInput(
          code: SellwildFailureCode.configFetchHttp,
          component: SellwildFailureComponent.remoteConfig,
          message: 'HTTP 403',
          httpStatus: 403,
          url: 'https://widget.sellwild.com/app/realgm/realgm-realgm.json',
        ),
        const FailureContext(
          partnerCode: 'realgm',
          client: 'flutter',
          clientVersion: sellwildSdkVersion,
        ),
        factoryUid,
        factoryNow,
      ).event!.toJson();

  /// What the logFailure shell emits for a caught error.
  Map<String, Object> shellWithError() {
    ClientFailureEvent? sent;
    SellwildFailures.setContext(
      partnerCode: 'weatherbug',
      clock: () => factoryNow,
      uid: () => factoryUid,
      sink: (event, flushNow) async => sent = event,
    );
    try {
      SellwildFailures.log(
        code: SellwildFailureCode.listingsFetchParse,
        component: SellwildFailureComponent.listings,
        error: const FormatException('Unexpected character (at character 1)'),
        url: 'https://cache.sellwild.com/listings-img-data-sm',
      );
    } finally {
      SellwildFailures.resetForTests();
    }
    return sent!.toJson();
  }

  @override
  List<Variant> get variants => [
        Variant('default', flutter),
        Variant('core-config-http', coreConfigHttp),
        Variant('shell-with-error', shellWithError),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('legacy-snake-code',
            () => build({'action': 'listings_fetch_failed'}),
            instancePath: '/action', keyword: 'pattern'),
        InvalidVariant('seq-number', () {
          final out = build();
          (out['attributes'] as Map<String, dynamic>)['seq'] = 1;
          return out;
        }, instancePath: '/attributes/seq', keyword: 'type'),
      ];
}

/// The events batch. Base: fixtures/events-batch/valid/flutter-minimal.json.
class EventsBatchFactory implements ContractFactory {
  @override
  String get schema => 'events-batch';

  List<dynamic> base() =>
      readContractJson('fixtures/events-batch/valid/flutter-minimal.json')
          as List<dynamic>;

  /// The POST body SellwildAPIClient.sendEvent sends for an analytics event.
  Future<Object?> sendEventBody() async {
    final recorder = HttpRecorder.status(200);
    final client = SellwildAPIClient(
        client: recorder.client, clock: () => factoryNow, uid: factoryUid)
      ..partnerCode = 'weatherbug';
    await client.sendEvent(event: 'firstAdViewed', label: '43');
    return recorder.jsonBody();
  }

  /// The POST body a logFailure call produces on its default route.
  Future<Object?> clientFailureBody() async {
    final recorder = HttpRecorder.status(200);
    SellwildAPIClient.instance =
        SellwildAPIClient(client: recorder.client, uid: factoryUid)
          ..partnerCode = 'weatherbug';
    SellwildFailures.setContext(
        partnerCode: 'weatherbug', clock: () => factoryNow);
    try {
      SellwildFailures.log(
        code: SellwildFailureCode.listingsFetchHttp,
        component: SellwildFailureComponent.listings,
        message: 'HTTP 503',
        httpStatus: 503,
        url: 'https://cache.sellwild.com/listings-img-data-sm',
      );
      await pumpEventQueue();
    } finally {
      SellwildAPIClient.instance = blockedSharedClient;
      SellwildFailures.resetForTests();
    }
    return recorder.jsonBody();
  }

  @override
  List<Variant> get variants => [
        Variant('default', base),
        Variant('send-event', sendEventBody),
        Variant('client-failure', clientFailureBody),
      ];

  @override
  List<InvalidVariant> get invalid => [
        InvalidVariant('empty', () => <Object?>[],
            instancePath: '', keyword: 'minItems'),
        InvalidVariant('missing-uid', () {
          final out = base();
          (out.first as Map<String, dynamic>).remove('uid');
          return out;
        }, instancePath: '/0', keyword: 'required'),
      ];
}
