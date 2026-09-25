import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sellwild_sample/src/diagnostics_screen.dart';
import 'package:sellwild_sample/src/feed_screen.dart';
import 'package:sellwild_sample/src/listings_screen.dart';
import 'package:sellwild_sample/src/sample_app.dart';
import 'package:sellwild_sample/src/sample_config.dart';
import 'package:sellwild_sample/src/sample_ids.dart';
import 'package:sellwild_sample/src/sample_model.dart';
import 'package:sellwild_sample/src/widgets.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

/// Two listings without photos (a photo would need the network).
final String _listingsBody = jsonEncode({
  'result': {
    'rs': [
      {
        'id': 'a',
        'title': 'Desk lamp',
        'price': '25',
        'user': {'firstName': 'Nick', 'lastName': 'Park'},
      },
      {'id': 'b', 'title': 'Road bike', 'price': '300'},
    ],
  },
});

/// The listings client answers every GET with [_listingsBody], and POSTs
/// (events) with 200.
void _useFakeListings() {
  SellwildAPIClient.instance = SellwildAPIClient(
    client: MockClient((request) async => request.method == 'GET'
        ? http.Response(_listingsBody, 200)
        : http.Response('', 200)),
  );
}

/// The label of the node with [id], as the platform sees it (with the
/// nodes merged into it).
String _label(WidgetTester tester, String id) => tester
    .getSemantics(find.bySemanticsIdentifier(id))
    .getSemanticsData()
    .label;

SampleBoot _fallbackBoot() {
  final config =
      withSampleValues(const SellwildConfig(partnerCode: 'sellwild'));
  return SampleBoot(config, configSourceOf(config));
}

void main() {
  setUp(SellwildFailures.resetForTests);

  group('feedRows', () {
    test('puts two cards a row and an ad after every four cards', () {
      expect(feedRows(10), const [
        FeedCards(0, 2),
        FeedCards(2, 4),
        FeedAd(0),
        FeedCards(4, 6),
        FeedCards(6, 8),
        FeedAd(1),
        FeedCards(8, 10),
      ]);
    });

    test('has no ad after the last card, and no rows for no listings', () {
      expect(feedRows(4), const [FeedCards(0, 2), FeedCards(2, 4)]);
      expect(feedRows(3), const [FeedCards(0, 2), FeedCards(2, 3)]);
      expect(feedRows(0), isEmpty);
    });
  });

  group('text helpers', () {
    test('sizeLabel rounds to whole points', () {
      expect(sizeLabel(const Size(320, 50)), '320x50');
      expect(sizeLabel(const Size(299.6, 250.4)), '300x250');
    });

    test('listingsStatus is the contract text', () {
      expect(listingsStatus(10, 2), '10 listings, load 2');
    });

    test('sellerName is first name and last initial', () {
      const nick = SellwildUser(
        id: '1',
        firstName: ' Nick ',
        lastName: 'Park',
        username: '',
        membershipType: '',
        trustLevel: '',
      );
      expect(sellerName(nick), 'Nick P.');
      expect(sellerName(null), isNull);
    });

    test('dataUrlBytes decodes data URLs only', () {
      expect(dataUrlBytes('data:image/png;base64,AAEC'), [0, 1, 2]);
      expect(dataUrlBytes('https://example.com/a.png'), isNull);
      expect(dataUrlBytes(null), isNull);
      expect(dataUrlBytes('data:image/png;base64,%'), isNull);
    });

    test('failureCodesText lists each code once, with a count', () {
      expect(failureCodesText(const []), 'none yet');
      expect(
        failureCodesText(const ['config.fetch.http', 'a.b.c', 'a.b.c']),
        'config.fetch.http, a.b.c x2',
      );
    });
  });

  group('withSampleValues', () {
    test('fills the built-in config with the sample values', () {
      final config =
          withSampleValues(const SellwildConfig(partnerCode: 'sellwild'));
      expect(config.partnerCode, 'sellwild');
      expect(config.listingsUrl, SampleSettings.listingsUrl);
      expect(config.appBundleId, SampleSettings.appId);
      expect(config.gamTag, SampleSettings.gamTestAdUnit);
      expect(config.title, 'Sellwild Sample');
      expect(config.debug, isTrue);
      expect(configSourceOf(config), ConfigSource.fallback);
    });

    test('keeps what the CDN config set', () {
      const remote = SellwildConfig(
        partnerCode: 'sellwild',
        title: 'From the CDN',
        gamTag: '/1/cdn',
        mobileZids: ['z1'],
        priceColor: '#123456',
        failuresSampleRate: 0.5,
        remoteJson: {'CODE': 'sellwild'},
      );
      final config = withSampleValues(remote);
      expect(config.title, 'From the CDN');
      expect(config.gamTag, '/1/cdn');
      expect(config.mobileZids, ['z1']);
      expect(config.priceColor, '#123456');
      expect(config.failuresSampleRate, 0.5);
      expect(config.remoteJson, {'CODE': 'sellwild'});
      expect(configSourceOf(config), ConfigSource.remote);
    });
  });

  test('the failure sink records each code and passes the event on', () async {
    final sent = <String>[];
    final model = SampleModel(send: (event, _) async => sent.add(event.action))
      ..installFailureSink();
    SellwildFailures.log(
      code: SellwildFailureCode.configFetchHttp,
      component: SellwildFailureComponent.remoteConfig,
      httpStatus: 403,
    );
    expect(sent, ['config.fetch.http']);
    await Future<void>.delayed(Duration.zero);
    expect(model.failureCodes.value, ['config.fetch.http']);
  });

  testWidgets('Diagnostics shows the contract values by id', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiagnosticsScreen(
          boot: _fallbackBoot(),
          failureCodes: ValueNotifier(const ['config.fetch.http']),
        ),
      ),
    ));
    expect(_label(tester, SampleId.diagSdkVersion), sellwildSdkVersion);
    expect(_label(tester, SampleId.diagPartner), 'sellwild / sellwild-sample');
    expect(_label(tester, SampleId.diagConfigSource), 'fallback');
    expect(
        _label(tester, SampleId.diagListingsUrl), SampleSettings.listingsUrl);
    expect(_label(tester, SampleId.diagFailures), 'config.fetch.http');
    semantics.dispose();
  });

  testWidgets('Listings loads, and Refresh clears the cache and loads again',
      (tester) async {
    final semantics = tester.ensureSemantics();
    _useFakeListings();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListingsScreen(config: _fallbackBoot().config)),
    ));
    await tester.pumpAndSettle();
    expect(_label(tester, SampleId.listingsStatus), '2 listings, load 1');
    expect(find.bySemanticsIdentifier(SampleId.listingCard), findsNWidgets(2));

    await tester.tap(find.bySemanticsIdentifier(SampleId.listingsRefresh));
    await tester.pumpAndSettle();
    expect(_label(tester, SampleId.listingsStatus), '2 listings, load 2');
    semantics.dispose();
  });

  testWidgets('the tab bar has the five tabs by id and title', (tester) async {
    final semantics = tester.ensureSemantics();
    _useFakeListings();
    await tester.pumpWidget(MaterialApp(
      home: SampleTabs(boot: _fallbackBoot(), model: SampleModel()),
    ));
    await tester.pumpAndSettle();
    const tabs = {
      SampleId.tabFeed: 'Feed',
      SampleId.tabAds: 'Ads',
      SampleId.tabListings: 'Listings',
      SampleId.tabDiagnostics: 'Diagnostics',
      SampleId.tabLegacy: 'Legacy',
    };
    for (final MapEntry(key: id, value: title) in tabs.entries) {
      expect(_label(tester, id), title);
    }
    // Feed opens first: two cards, no ad row for two listings.
    expect(find.bySemanticsIdentifier(SampleId.feedList), findsOneWidget);
    expect(find.bySemanticsIdentifier(SampleId.listingCard), findsNWidgets(2));

    await tester.tap(find.bySemanticsIdentifier(SampleId.tabDiagnostics));
    await tester.pumpAndSettle();
    expect(_label(tester, SampleId.diagPartner), 'sellwild / sellwild-sample');
    // The Feed's cards are off screen now, and out of the semantics tree.
    expect(find.bySemanticsIdentifier(SampleId.listingCard), findsNothing);
    semantics.dispose();
  });
}
