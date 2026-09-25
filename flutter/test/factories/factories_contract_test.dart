// Every factory variant against contracts/schemas in-process (json_schema,
// formats asserted as ajv does), every invalid variant fails for its intended
// reason, and the valid ones are emitted to contracts/out/flutter for
// `node contracts/scripts/validate.mjs --out flutter` (scripts/coverage/
// flutter.sh runs it). The SDK parsers must also accept every valid variant.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import '../support/contract_emitter.dart';
import '../support/contract_schemas.dart';
import '../support/failure_capture.dart';
import '../support/http_mocks.dart';
import 'contract_factory.dart';
import 'event_factories.dart';
import 'shape_factories.dart';

final List<ContractFactory> factories = [
  AppConfigFactory(),
  ListingFactory(),
  ListingsResponseFactory(),
  BridgeMessageFactory(),
  ClientFailureEventFactory(),
  EventsBatchFactory(),
];

void main() {
  for (final factory in factories) {
    group(factory.schema, () {
      for (final variant in factory.variants) {
        test('${variant.name} conforms and is emitted', () async {
          final payload = await variant.build();

          expect(payload, conformsTo(factory.schema));
          final file =
              emitContract(factory.schema, 'factory-${variant.name}', payload);
          expect(file.existsSync(), isTrue);
        });
      }

      for (final variant in factory.invalid) {
        test(
            '${variant.name} fails at "${variant.instancePath}" '
            '(${variant.keyword})', () async {
          final payload = await variant.build();

          expect(payload, isNot(conformsTo(factory.schema)));
          final errors = contractErrors(factory.schema, payload);
          expect(
            errors.any((e) =>
                e.instancePath == variant.instancePath &&
                (variant.keyword == null || e.keyword == variant.keyword)),
            isTrue,
            reason: '$errors',
          );
        });
      }
    });
  }

  group('the SDK reads every valid variant', () {
    test('app-config: SellwildSDK.apply', () async {
      // Some variants are built to be reported (sellwild_sdk_apply_test.dart).
      // Each variant is its own apply, and two share the out-of-range
      // AD_REFRESH_INTERVAL report, so the gate folds that one on purpose.
      captureFailures(allowFolds: true);
      final factory = AppConfigFactory();
      const base = SellwildConfig(partnerCode: 'x');

      for (final variant in factory.variants) {
        final raw = await variant.build() as Map<String, dynamic>;
        final config = SellwildSDK.apply(raw, base, isAndroid: false);
        expect(config.partnerCode, raw['CODE'], reason: variant.name);
        expect(config.remoteJson, same(raw));
      }
      final off = SellwildSDK.apply(factory.failuresOff(), base);
      expect(off.failuresEnabled, isFalse);
      expect(off.failuresSampleRate, 0.25);
      final text = SellwildSDK.apply(factory.switchesAsText(), base);
      expect(text.eventsEnabled, isFalse);
      expect(text.failuresEnabled, isTrue);
      expect(text.failuresSampleRate, 0.5);
    });

    test('app-config: the overflow text is the default with 1e400', () {
      final factory = AppConfigFactory();

      final decoded = jsonDecode(factory.refreshIntervalOverflowText())
          as Map<String, dynamic>;

      expect(decoded['AD_REFRESH_INTERVAL'], double.infinity);
      expect(decoded..remove('AD_REFRESH_INTERVAL'),
          factory.build({'AD_REFRESH_INTERVAL': remove}));
    });

    test('listing: SellwildListing.fromJson', () async {
      for (final variant in ListingFactory().variants) {
        final json = await variant.build() as Map<String, dynamic>;
        final listing = SellwildListing.fromJson(json);
        expect(listing.id, '${json['id']}', reason: variant.name);
        expect(listing.title, json['title'], reason: variant.name);
        expect(listing.photos, hasLength((json['photos'] as List).length));
      }
    });

    test('listings-response: SellwildAPIClient.fetchListings', () async {
      for (final variant in ListingsResponseFactory().variants) {
        final json = await variant.build() as Map<String, dynamic>;
        final client =
            SellwildAPIClient(client: HttpRecorder.json(json).client);

        final res = await client
            .fetchListings(const SellwildConfig(partnerCode: 'weatherbug'));

        final rs = (json['result'] as Map)['rs'] as List;
        expect(res.listings.map((l) => l.id),
            rs.map((item) => '${(item as Map)['id']}'),
            reason: variant.name);
      }
    });
  });
}
