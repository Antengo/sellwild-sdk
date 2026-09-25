// SellwildAPIClient with an injected MockClient: fetchListings against real
// captured caches and every failure path (each reported once, then thrown as
// before), and sendEvent (stamping, uid, clock, kill switch, never throws,
// never reports itself: FAILURES.md 8.4).

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'factories/shape_factories.dart';
import 'flutter_test_config.dart' show blockedSharedClient;
import 'support/contract_schemas.dart';
import 'support/failure_capture.dart';
import 'support/fixtures.dart';
import 'support/http_mocks.dart';

const String cacheUrl = 'https://cache.sellwild.com/listings-img-data-sm';
const SellwildConfig config = SellwildConfig(partnerCode: 'weatherbug');

final RegExp uuidV4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

void main() {
  final responses = ListingsResponseFactory();

  group('fetchListings on real listings caches', () {
    final expectations =
        loadExpectations('listings-response') as Map<String, dynamic>;
    for (final c
        in (expectations['cases'] as List).cast<Map<String, dynamic>>()) {
      final file = c['file'] as String;
      test(file, () async {
        final failures = captureFailures();
        final recorder = HttpRecorder.json(readContractJson(file));
        final client = SellwildAPIClient(client: recorder.client);
        final expected = c['expected'] as Map<String, dynamic>;

        final res = await client.fetchListings(config);

        expect(res.listings.map((l) => l.id).toList(), expected['ids']);
        final versionId = expected['widgetCacheVersionId'];
        // Flutter keeps an absent widgetCacheVersionId as null, not '0'.
        expect(res.widgetCacheVersionId, versionId == '0' ? isNull : versionId);
        expect(recorder.single.url.toString(), cacheUrl);
        expect(failures, isEmpty);
      });
    }
  });

  group('fetchListings', () {
    test('caches by URL until clearCache', () async {
      final recorder =
          HttpRecorder.json(loadFixture('listings-response', 'rpc-envelope'));
      final client = SellwildAPIClient(client: recorder.client);

      final first = await client.fetchListings(config);
      final second = await client.fetchListings(config);
      expect(second, same(first));
      expect(recorder.requests, hasLength(1));
      expect(first.config, {'browse': 1});
      expect(first.widgetCacheVersionId, '12');

      client.clearCache();
      await client.fetchListings(config);
      expect(recorder.requests, hasLength(2));
    });

    test('non-200: listings.fetch.http, then SellwildException', () async {
      final failures = captureFailures();
      final client = SellwildAPIClient(client: HttpRecorder.status(503).client);

      await expectLater(
          client.fetchListings(config), throwsA(isA<SellwildException>()));

      final event = failures.single;
      expect(event.action, 'listings.fetch.http');
      expect(event.label, 'listings');
      expect(event.attributes['httpStatus'], '503');
      expect(event.attributes['host'], 'cache.sellwild.com');
      expect(event.attributes['msg'], 'HTTP 503');
    });

    test('a LISTINGS URL that does not parse: listings.url.invalid, no fetch',
        () async {
      final failures = captureFailures();
      final recorder = HttpRecorder.status(200);
      final client = SellwildAPIClient(client: recorder.client);
      final applied = SellwildSDK.apply(
          AppConfigFactory().listingsMalformed(), config,
          isAndroid: false);

      await expectLater(
          client.fetchListings(applied), throwsA(isA<FormatException>()));

      expect(recorder.requests, isEmpty);
      expect(actionsOf(failures), ['listings.url.invalid']);
      final event = failures.single;
      expect(event.label, 'listings');
      expect(event.attributes['severity'], 'error');
      expect(event.attributes['errName'], 'FormatException');
      expect(event.attributes['msg'],
          startsWith('listings URL is not a valid URL: '));
    });

    test('network error: listings.fetch.network, then the error', () async {
      final failures = captureFailures();
      final client = SellwildAPIClient(client: HttpRecorder.failing().client);

      await expectLater(
          client.fetchListings(config), throwsA(isA<http.ClientException>()));

      expect(failures.single.action, 'listings.fetch.network');
      expect(failures.single.attributes['errName'], 'ClientException');
      expect(failures.single.attributes['host'], 'cache.sellwild.com');
    });

    test('timeout: listings.fetch.timeout', () async {
      final failures = captureFailures();
      final client = SellwildAPIClient(
          client: HttpRecorder.failing(TimeoutException('GET')).client);

      await expectLater(
          client.fetchListings(config), throwsA(isA<TimeoutException>()));

      expect(failures.single.action, 'listings.fetch.timeout');
    });

    test('after dispose: listings.client.missing (warn)', () async {
      final failures = captureFailures();
      final recorder = HttpRecorder.status(200);
      final client = SellwildAPIClient(client: recorder.client);

      client.dispose();
      await expectLater(
          client.fetchListings(config), throwsA(isA<http.ClientException>()));

      expect(recorder.closed, isTrue);
      expect(failures.single.action, 'listings.client.missing');
      expect(failures.single.attributes['severity'], 'warn');
    });

    test('an HTML error page: listings.fetch.parse, then FormatException',
        () async {
      final failures = captureFailures();
      final client = SellwildAPIClient(
          client: HttpRecorder.text('<html>Bad Gateway</html>').client);

      await expectLater(
          client.fetchListings(config), throwsA(isA<FormatException>()));

      expect(failures.single.action, 'listings.fetch.parse');
      expect(failures.single.attributes['errName'], 'FormatException');
    });

    test('a JSON array: listings.parse.invalid, then TypeError', () async {
      final failures = captureFailures();
      final client = SellwildAPIClient(
          client: HttpRecorder.json(responses.bodyArray()).client);

      await expectLater(
          client.fetchListings(config), throwsA(isA<TypeError>()));

      expect(failures.single.action, 'listings.parse.invalid');
    });

    test('rs not an array (invalid fixture): listings.parse.invalid', () async {
      final failures = captureFailures();
      final client = SellwildAPIClient(
          client: HttpRecorder.json(loadFixture(
                  'listings-response', 'rs-not-array',
                  valid: false))
              .client);

      await expectLater(
          client.fetchListings(config), throwsA(isA<TypeError>()));

      expect(failures.single.action, 'listings.parse.invalid');
    });

    test('result null and no rs: an empty feed as before, reported', () async {
      final failures = captureFailures();
      final client = SellwildAPIClient(
          client: HttpRecorder.json(
                  loadFixture('listings-response', 'result-null', valid: false))
              .client);

      final res = await client.fetchListings(config);

      expect(res.listings, isEmpty);
      expect(failures.single.action, 'listings.parse.invalid');
      expect(failures.single.attributes['msg'], 'no result.rs array');
    });

    test('a bad config with no rs is reported once, then TypeError', () async {
      final failures = captureFailures();
      final client = SellwildAPIClient(
          client: HttpRecorder.json(responses.configNumber()).client);

      await expectLater(
          client.fetchListings(config), throwsA(isA<TypeError>()));

      // Not also 'no result.rs array': every cast runs before that report.
      expect(failures.single.action, 'listings.parse.invalid');
      expect(failures.single.attributes['errName'], '_TypeError');
    });

    test('entries that are not objects are dropped and reported', () async {
      final failures = captureFailures();
      final body = responses.nonObjectEntries();
      final item = ((body['result'] as Map)['rs'] as List).first as Map;
      final client = SellwildAPIClient(client: HttpRecorder.json(body).client);

      final res = await client.fetchListings(config);

      expect(res.listings.single.id, item['id']);
      expect(failures.single.action, 'listings.item.invalid');
      expect(failures.single.attributes['severity'], 'warn');
      expect(failures.single.attributes['msg'],
          '2 result.rs entries are not objects; dropped');
    });

    test('photos entries that are not objects: listings.item.invalid once',
        () async {
      final failures = captureFailures();
      final body = responses.nonObjectPhotos();
      final client = SellwildAPIClient(client: HttpRecorder.json(body).client);

      final res = await client.fetchListings(config);

      // Every item is kept, without its bad photos entry (as before).
      expect(res.listings, hasLength(3));
      expect(res.listings.map((l) => l.photos.length).toSet(), {1});
      final event = failures.single;
      expect(event.action, 'listings.item.invalid');
      expect(event.label, 'listings');
      expect(event.attributes['severity'], 'warn');
      // 2 in the first item and 1 in the second: each entry is counted.
      expect(
          event.attributes['msg'], '3 photos entries are not objects; dropped');
      expect(event.attributes['host'], 'cache.sellwild.com');
    });

    test('one entry that is not an object: listings.item.invalid once',
        () async {
      final failures = captureFailures();
      final body = responses.oneNonObjectEntry();
      final item = ((body['result'] as Map)['rs'] as List).first as Map;
      final client = SellwildAPIClient(client: HttpRecorder.json(body).client);

      final res = await client.fetchListings(config);

      expect(res.listings.single.id, item['id']);
      expect(failures.map((e) => e.action), ['listings.item.invalid']);
      expect(failures.single.attributes['msg'],
          '1 result.rs entries are not objects; dropped');
    });

    test('one photos entry that is not an object: listings.item.invalid once',
        () async {
      final failures = captureFailures();
      final body = responses.oneNonObjectPhoto();
      final client = SellwildAPIClient(client: HttpRecorder.json(body).client);

      final res = await client.fetchListings(config);

      // Both items are kept; the first without its bad entry.
      expect(res.listings, hasLength(2));
      expect(failures.map((e) => e.action), ['listings.item.invalid']);
      expect(failures.single.attributes['msg'],
          '1 photos entries are not objects; dropped');
    });

    test('photos entries of other kinds (a number, null, an array) count too',
        () async {
      final failures = captureFailures();
      final body = responses.otherKindPhotos();
      final client = SellwildAPIClient(client: HttpRecorder.json(body).client);

      final res = await client.fetchListings(config);

      // Both items are kept; the first keeps only its real photo.
      expect(res.listings, hasLength(2));
      expect(res.listings.first.photos, hasLength(1));
      expect(failures.map((e) => e.action), ['listings.item.invalid']);
      expect(failures.single.attributes['msg'],
          '3 photos entries are not objects; dropped');
    });

    test('an item without photos is kept and not reported', () async {
      final failures = captureFailures();
      final body = responses.itemWithoutPhotos();
      final client = SellwildAPIClient(client: HttpRecorder.json(body).client);

      final res = await client.fetchListings(config);

      expect(res.listings.single.photos, isEmpty);
      expect(failures, isEmpty);
    });

    test('an unreadable item is reported once, not for its photos too',
        () async {
      final failures = captureFailures();
      final body = responses.unreadableItemWithNonObjectPhotos();
      final item = ((body['result'] as Map)['rs'] as List).first as Map;
      final client = SellwildAPIClient(client: HttpRecorder.json(body).client);

      final res = await client.fetchListings(config);

      // The dropped item's photos are not counted as dropped photos: one
      // item, one report.
      expect(res.listings.single.id, item['id']);
      expect(failures.map((e) => e.action), ['listings.item.parse']);
      expect(failures.single.attributes['msg'],
          startsWith('1 result.rs items failed to decode; dropped: '));
    });

    test('items fromJson cannot read: listings.item.parse once, dropped',
        () async {
      final failures = captureFailures();
      final body = responses.unreadableItems();
      final item = ((body['result'] as Map)['rs'] as List).first as Map;
      final client = SellwildAPIClient(client: HttpRecorder.json(body).client);

      final res = await client.fetchListings(config);

      // The readable item survives; before, one bad item failed the feed.
      expect(res.listings.single.id, item['id']);
      final event = failures.single;
      expect(event.action, 'listings.item.parse');
      expect(event.label, 'listings');
      expect(event.attributes['severity'], 'error');
      expect(event.attributes['errName'], '_TypeError');
      expect(event.attributes['msg'],
          startsWith('2 result.rs items failed to decode; dropped: '));
      expect(event.attributes['host'], 'cache.sellwild.com');
    });

    test('the one report carries the first unreadable item\'s error',
        () async {
      // The error text of [item], as the report writes it.
      String errorOf(Object? item) {
        try {
          SellwildListing.fromJson(item as Map<String, dynamic>);
        } catch (e) {
          return '$e';
        }
        fail('the item decoded');
      }

      // The same two unreadable items (an object title, text photos) in
      // both orders: each time the report names the first one's error.
      for (final body in [
        responses.unreadableItems(),
        responses.unreadableItemsSwapped(),
      ]) {
        final failures = captureFailures();
        final rs = (body['result'] as Map)['rs'] as List;
        final client =
            SellwildAPIClient(client: HttpRecorder.json(body).client);

        final res = await client.fetchListings(config);

        expect(res.listings, hasLength(1));
        expect(errorOf(rs[1]), isNot(errorOf(rs[2])));
        expect(failures.map((e) => e.action), ['listings.item.parse']);
        expect(failures.single.attributes['msg'],
            '2 result.rs items failed to decode; dropped: ${errorOf(rs[1])}');
        endFailureCase();
      }
    });
  });

  group('sendEvent', () {
    test('posts one stamped event with the uid and clock', () async {
      final recorder = HttpRecorder.status(200);
      final client = SellwildAPIClient(
          client: recorder.client, clock: () => 1790000000000, uid: 'u-1')
        ..partnerCode = 'weatherbug';

      await client.sendEvent(
        event: 'firstAdViewed',
        action: 'view',
        label: '43',
        attributes: {'zone': '43', 'type': 'spoof', 'sdkVersion': '0'},
      );

      final request = recorder.single;
      expect(request.method, 'POST');
      expect(
          request.url.toString(), 'https://events.sellwild.com/events/queue');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      final batch = recorder.jsonBody();
      expect(batch, [
        {
          'event': 'firstAdViewed',
          'action': 'view',
          'label': '43',
          'attributes': {
            'code': 'weatherbug',
            'zone': '43',
            'type': 'flutter',
            'sdkVersion': sellwildSdkVersion,
          },
          'uid': 'u-1',
          'createdTime': 1790000000000,
        }
      ]);
      expect(batch, conformsTo('events-batch'));
      expect(client.failedEventSends, 0);
    });

    test("a caller's code wins over the partner code; none without a partner",
        () async {
      final recorder = HttpRecorder.status(200);
      final client = SellwildAPIClient(client: recorder.client)
        ..partnerCode = 'weatherbug';

      await client
          .sendEvent(event: 'click', uid: 'u', attributes: {'code': 'antengo'});
      client.partnerCode = '';
      await client.sendEvent(event: 'click', uid: 'u', createdTime: 5);

      Map<String, dynamic> attributesOf(int i) =>
          ((recorder.jsonBody(i) as List).single as Map)['attributes']
              as Map<String, dynamic>;
      expect(attributesOf(0)['code'], 'antengo');
      expect(attributesOf(1).containsKey('code'), isFalse);
      expect(((recorder.jsonBody(1) as List).single as Map)['createdTime'], 5);
    });

    test('kill switch: enabled false or EVENTS_ENABLED off sends nothing',
        () async {
      final recorder = HttpRecorder.status(200);
      final client = SellwildAPIClient(client: recorder.client);

      await client.sendEvent(event: 'click', enabled: false);
      client.eventsEnabled = false;
      await client.sendEvent(event: 'click');

      expect(recorder.requests, isEmpty);
    });

    test('never throws and never reports itself', () async {
      final failures = captureFailures();
      final sends = <SellwildAPIClient>[
        SellwildAPIClient(client: HttpRecorder.failing().client),
        SellwildAPIClient(client: HttpRecorder.status(500).client),
        SellwildAPIClient(client: HttpRecorder.status(200).client),
      ];

      for (final client in sends) {
        await expectLater(client.sendEvent(event: 'click'), completes);
      }
      // A value jsonEncode cannot encode.
      await expectLater(
          sends.last.sendEvent(event: 'click', attributes: {'x': Object()}),
          completes);

      expect(sends.map((c) => c.failedEventSends), [1, 1, 1]);
      expect(failures, isEmpty);
      expect(SellwildFailures.gateState.sessionCount, 0);
      expect(SellwildFailures.internalErrorCount, 0);
    });
  });

  group('uid', () {
    test('one v4 UUID per process, unless injected', () {
      expect(SellwildAPIClient.processUid, matches(uuidV4Pattern));
      expect(SellwildAPIClient().uid, SellwildAPIClient.processUid);
      expect(SellwildAPIClient(uid: 'mine').uid, 'mine');
    });

    test('uuidV4 sets the version and variant bits', () {
      final all = SellwildAPIClient.uuidV4(_Fixed(0xff));
      final none = SellwildAPIClient.uuidV4(_Fixed(0x00));

      expect(all, 'ffffffff-ffff-4fff-bfff-ffffffffffff');
      expect(none, '00000000-0000-4000-8000-000000000000');
      expect(SellwildAPIClient.uuidV4(Random(7)), matches(uuidV4Pattern));
    });
  });

  test('instance can be replaced for tests', () {
    final mine = SellwildAPIClient(client: HttpRecorder.status(200).client);
    SellwildAPIClient.instance = mine;
    addTearDown(() => SellwildAPIClient.instance = blockedSharedClient);

    expect(SellwildAPIClient.instance, same(mine));
  });

  test('SellwildException names its message', () {
    expect(SellwildException('HTTP 503').toString(),
        'SellwildException: HTTP 503');
  });
}

/// A Random whose every byte is [value].
class _Fixed implements Random {
  _Fixed(this.value);

  final int value;

  @override
  int nextInt(int max) => value;

  @override
  bool nextBool() => value.isOdd;

  @override
  double nextDouble() => value / 256;
}
