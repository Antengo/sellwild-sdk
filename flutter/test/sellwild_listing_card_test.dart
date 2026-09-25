// SellwildListingCard: what it renders for real listing items, and each
// value it has to replace reported through logFailure: an unknown currency
// or a photo that fails to load once per card, a color that is not hex once
// per config.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/listing_card_view.dart';

import 'factories/shape_factories.dart';
import 'support/failure_capture.dart';

void main() {
  final listings = ListingFactory();

  SellwildListing listingFrom(Map<String, dynamic> json) =>
      SellwildListing.fromJson(json);

  /// A config built at run time, so each test gets its own object.
  SellwildConfig configWith({
    String priceColor = '#333333',
    String priceFontColor = '#ffffff',
    int fontSize = 13,
  }) =>
      SellwildConfig(
        partnerCode: 'weatherbug${DateTime.now().microsecondsSinceEpoch}',
        priceColor: priceColor,
        priceFontColor: priceFontColor,
        fontSize: fontSize,
      );

  Future<void> pumpCard(
      WidgetTester tester, SellwildListing listing, SellwildConfig config,
      {void Function(SellwildListing)? onTap}) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child:
            SellwildListingCard(listing: listing, config: config, onTap: onTap),
      ),
    ));
  }

  /// The decoration of the badge that shows [price].
  BoxDecoration badgeDecoration(WidgetTester tester, String price) {
    final badge =
        find.ancestor(of: find.text(price), matching: find.byType(Container));
    return tester.widget<Container>(badge.first).decoration! as BoxDecoration;
  }

  group('buildListingCardView (pure)', () {
    test('a real cache item: title, photo, price and colors', () {
      final json = listings.build();

      final view = buildListingCardView(listingFrom(json), configWith());

      expect(view.title, json['title']);
      expect(view.photoUrl, (json['photos'] as List).first['url']);
      expect(view.priceText, '\$${json['price']}');
      expect(view.priceColor, const Color(0xFF333333));
      expect(view.priceFontColor, const Color(0xFFFFFFFF));
      expect(view.issues, isEmpty);
    });

    test('a long title is cut to 60 characters', () {
      final title = listings.longTitle()['title'] as String;

      final view =
          buildListingCardView(listingFrom(listings.longTitle()), configWith());

      expect(view.title, '${title.substring(0, 60)}...');
      expect(cardTitle('short'), 'short');
    });

    test('a title of exactly 60 characters is kept; 61 is cut', () {
      String titleOf(Map<String, dynamic> json) =>
          buildListingCardView(listingFrom(json), configWith()).title;
      final sixty = listings.titleOfLength(60)['title'] as String;
      final sixtyOne = listings.titleOfLength(61)['title'] as String;

      expect(sixty, hasLength(cardTitleMaxLength));
      expect(titleOf(listings.titleOfLength(60)), sixty);
      expect(titleOf(listings.titleOfLength(61)),
          '${sixtyOne.substring(0, 60)}...');
    });

    test('known currencies get their symbol; absent is USD', () {
      final eur = buildListingCardView(
          listingFrom(listings.withCurrency('EUR')), configWith());

      expect(eur.priceText, startsWith('€'));
      expect(eur.issues, isEmpty);
      expect(currencySymbolFor(null), '\$');
      expect(currencySymbolFor(''), '\$');
      expect(currencySymbols.keys.map(currencySymbolFor),
          ['\$', '€', '£', 'CA\$', 'A\$']);
    });

    test('an unknown currency: \$ and a listings.item.invalid issue', () {
      final code = buildListingCardView(
          listingFrom(listings.withCurrency('JPY')), configWith());
      final text = buildListingCardView(
          listingFrom(listings.withCurrency('dollars')), configWith());
      // Three letters that are not all upper case are not an ISO code.
      final threeLetters = [
        for (final currency in ['jpy', 'Usd', 'eUR'])
          buildListingCardView(
              listingFrom(listings.withCurrency(currency)), configWith()),
      ];

      expect(code.priceText, startsWith('\$'));
      expect(code.issues.map((i) => (i.code, i.severity, i.message)), [
        (
          'listings.item.invalid',
          'warn',
          'currency JPY has no symbol; \$ used'
        ),
      ]);
      // Text that is not an ISO code is not echoed.
      expect(
          text.issues.single.message, 'currency is not a known code; \$ used');
      for (final view in threeLetters) {
        expect(view.priceText, startsWith('\$'));
        expect(view.issues.map((i) => (i.code, i.severity, i.message)), [
          (
            'listings.item.invalid',
            'warn',
            'currency is not a known code; \$ used'
          ),
        ]);
      }
    });

    test('no price, a zero price: no badge', () {
      expect(
          buildListingCardView(listingFrom(listings.noPrice()), configWith())
              .priceText,
          isNull);
      expect(
          buildListingCardView(listingFrom(listings.zeroPrice()), configWith())
              .priceText,
          isNull);
    });

    test('a price that is not a number: no badge, listings.item.invalid', () {
      final view =
          buildListingCardView(listingFrom(listings.priceText()), configWith());

      expect(view.priceText, isNull);
      expect(view.issues.map((i) => (i.code, i.severity, i.message)), [
        ('listings.item.invalid', 'warn', 'price is not a number; no badge'),
      ]);
      // No price and a zero price hide the badge by design: no issue.
      for (final json in [listings.noPrice(), listings.zeroPrice()]) {
        expect(buildListingCardView(listingFrom(json), configWith()).issues,
            isEmpty);
      }
    });

    test("currency '' is USD: \$ and no issue", () {
      final json = listings.withCurrency('');

      final view = buildListingCardView(listingFrom(json), configWith());

      expect(view.priceText, '\$${json['price']}');
      expect(view.issues, isEmpty);
    });

    test('a price that is no finite number: no badge, reported (A9 fix)', () {
      for (final text in ['NaN', 'Infinity', '-Infinity', '1e400']) {
        final listing = listingFrom(listings.nonFinitePrice(text));

        final view = buildListingCardView(listing, configWith());

        // Before: 'NaN' and 'Infinity' showed as '$NaN' and '$Infinity'
        // badges, and none of the four was reported.
        expect(listing.displayPrice, isNull, reason: text);
        expect(view.priceText, isNull, reason: text);
        expect(
            view.issues.map((i) => (i.code, i.severity, i.message)),
            [
              (
                'listings.item.invalid',
                'warn',
                'price is not a number; no badge'
              ),
            ],
            reason: text);
      }
    });

    test("a blank price ('' or spaces) is no price: no badge, no issue", () {
      for (final blank in ['', '  ']) {
        final view = buildListingCardView(
            listingFrom(listings.blankPrice(blank)), configWith());

        expect(view.priceText, isNull, reason: "'$blank'");
        expect(view.issues, isEmpty, reason: "'$blank'");
      }
    });

    testWidgets('a blank price is not reported by the card', (tester) async {
      final failures = captureFailures();

      await pumpCard(
          tester, listingFrom(listings.blankPrice('  ')), configWith());

      expect(failures, isEmpty);
    });

    testWidgets('a price that is not a number is reported once by the card',
        (tester) async {
      final failures = captureFailures();

      await pumpCard(tester, listingFrom(listings.priceText()), configWith());

      expect(actionsOf(failures), ['listings.item.invalid']);
      expect(failures.single.label, 'feed');
      expect(find.textContaining('\$'), findsNothing);
    });

    test('no photos, an empty photo URL: the placeholder', () {
      expect(
          buildListingCardView(listingFrom(listings.noPhotos()), configWith())
              .photoUrl,
          isNull);
      expect(
          buildListingCardView(
                  listingFrom(listings.photoEmptyUrl()), configWith())
              .photoUrl,
          isNull);
    });

    test('colors that are not hex: grey and a config.color.invalid issue', () {
      final view = buildListingCardView(listingFrom(listings.build()),
          configWith(priceColor: 'red', priceFontColor: 'rgb(0,0,0)'));

      expect(view.priceColor, fallbackCardColor);
      expect(view.priceFontColor, fallbackCardColor);
      expect(view.issues.map((i) => (i.code, i.severity, i.message)), [
        ('config.color.invalid', 'error', 'priceColor is not a hex color'),
        ('config.color.invalid', 'error', 'priceFontColor is not a hex color'),
      ]);
    });

    test('parseHexColor', () {
      expect(parseHexColor('#234966'), const Color(0xFF234966));
      expect(parseHexColor('234966'), const Color(0xFF234966));
      expect(parseHexColor('#ABCdef'), const Color(0xFFABCDEF));
      expect(parseHexColor('red'), isNull);
      expect(parseHexColor(''), isNull);
    });

    test('parseHexColor: only #rrggbb (A9 fix)', () {
      // Before: 'fff' parsed as 0x000fff, a dark blue, not white; a sign or
      // a second '#' was accepted too.
      for (final text in [
        'fff',
        '#fff',
        '#2349660',
        '#23496680',
        '+23496',
        '-23496',
        '##234966',
        '#23 496',
      ]) {
        expect(parseHexColor(text), isNull, reason: text);
      }
    });

    test('a 3-digit color: grey and config.color.invalid', () {
      final view = buildListingCardView(
          listingFrom(listings.build()), configWith(priceColor: '#fff'));

      expect(view.priceColor, fallbackCardColor);
      expect(view.issues.map((i) => (i.code, i.severity, i.message)), [
        ('config.color.invalid', 'error', 'priceColor is not a hex color'),
      ]);
    });
  });

  group('SellwildListingCard', () {
    testWidgets('renders the title, badge and colors; no failures',
        (tester) async {
      final failures = captureFailures();
      final json = listings.noPhotosIn('GBP');

      await pumpCard(
          tester,
          listingFrom(json),
          configWith(
              priceColor: '#112233', priceFontColor: '#445566', fontSize: 17));

      expect(find.text(json['title'] as String), findsOneWidget);
      final price = tester.widget<Text>(find.text('£${json['price']}'));
      expect(price.style!.color, const Color(0xFF445566));
      final title = tester.widget<Text>(find.text(json['title'] as String));
      expect(title.style!.fontSize, 17);
      expect(badgeDecoration(tester, '£${json['price']}').color,
          const Color(0xFF112233));
      expect(failures, isEmpty);
    });

    testWidgets('a tap calls onTap with the listing; no onTap is fine',
        (tester) async {
      captureFailures();
      final listing = listingFrom(listings.build());
      final tapped = <SellwildListing>[];

      await pumpCard(tester, listing, configWith(), onTap: tapped.add);
      await tester.tap(find.byType(SellwildListingCard));
      await pumpCard(tester, listing, configWith());
      await tester.tap(find.byType(SellwildListingCard));

      expect(tapped, [same(listing)]);
    });

    testWidgets('no photo: the placeholder and no network', (tester) async {
      final failures = captureFailures();

      await pumpCard(tester, listingFrom(listings.noPhotos()), configWith());
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(failures, isEmpty);
    });

    testWidgets('a photo that fails to load: feed.image.network once',
        (tester) async {
      final failures = captureFailures();
      final json = listings.build();

      // flutter_test answers every image request with HTTP 400.
      await pumpCard(tester, listingFrom(json), configWith());
      await tester.pumpAndSettle();
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(actionsOf(failures), ['feed.image.network']);
      final event = failures.single;
      expect(event.label, 'feed');
      expect(event.attributes['severity'], 'warn');
      expect(event.attributes['errName'], 'NetworkImageLoadException');
      expect(event.attributes['host'],
          Uri.parse((json['photos'] as List).first['url'] as String).host);
    });

    testWidgets("currency '' shows \$ and is not reported", (tester) async {
      final failures = captureFailures();
      final json = listings.noPhotosIn('');

      await pumpCard(tester, listingFrom(json), configWith());

      expect(find.text('\$${json['price']}'), findsOneWidget);
      expect(failures, isEmpty);
    });

    testWidgets('a NaN price shows no badge and is reported once',
        (tester) async {
      final failures = captureFailures();

      await pumpCard(
          tester, listingFrom(listings.nonFinitePrice('NaN')), configWith());

      expect(find.textContaining('\$'), findsNothing);
      expect(actionsOf(failures), ['listings.item.invalid']);
      expect(
          failures.single.attributes['msg'], 'price is not a number; no badge');
    });

    testWidgets(
        'a new listing: its URL alone is not a failure; its photo failing is',
        (tester) async {
      final failures = captureFailures();
      final first = listings.build();
      final second = listings.bargainhunter();
      String hostOf(Map<String, dynamic> json) =>
          Uri.parse((json['photos'] as List).first['url'] as String).host;

      // flutter_test answers every image request with HTTP 400. The second
      // listing reuses the first card's Image and its error placeholder.
      await pumpCard(tester, listingFrom(first), configWith());
      await tester.pumpAndSettle();
      expect(failures.map((e) => e.attributes['host']), [hostOf(first)]);
      // Two minutes on, so the logFailure gate does not fold the repeat.
      SellwildFailures.setContext(clock: () => 1790000000000 + 120000);

      // Image keeps the first photo's error while the second one loads, so
      // the placeholder is rebuilt with the old error and the new URL. That
      // is not a failure of the new photo: nothing is reported yet.
      await pumpCard(tester, listingFrom(second), configWith());
      expect(find.byType(Image), findsOneWidget);
      expect(failures.map((e) => e.attributes['host']), [hostOf(first)]);

      // The second photo fails too: its own error is reported, once.
      await tester.pumpAndSettle();
      await tester.pump();

      expect(actionsOf(failures), ['feed.image.network', 'feed.image.network']);
      expect(failures.map((e) => e.attributes['host']),
          [hostOf(first), hostOf(second)]);
    });

    testWidgets('a rebuild that keeps the failed photo does not report again',
        (tester) async {
      final failures = captureFailures();
      final listing = listingFrom(listings.build());
      final config = configWith();

      // flutter_test answers every image request with HTTP 400.
      await pumpCard(tester, listing, config);
      await tester.pumpAndSettle();
      expect(actionsOf(failures), ['feed.image.network']);

      // The same card rebuilt: Image hands its placeholder the same error.
      // Two minutes on, so the logFailure gate would not fold a repeat.
      SellwildFailures.setContext(clock: () => 1790000000000 + 120000);
      await pumpCard(tester, listing, config);
      await tester.pumpAndSettle();

      expect(actionsOf(failures), ['feed.image.network']);
      expect(SellwildFailures.gateState.sessionCount, 1);
    });

    testWidgets('each replaced value is reported once per card, not per build',
        (tester) async {
      final failures = captureFailures();
      final json = listings.noPhotosIn('JPY');
      final listing = listingFrom(json);
      final config = configWith(priceColor: 'red');

      await pumpCard(tester, listing, config);
      await pumpCard(tester, listing, config);
      await tester.pump();

      expect(actionsOf(failures),
          ['listings.item.invalid', 'config.color.invalid']);
      // Not even folded into the first report by the logFailure gate: the
      // rebuild did not report again.
      expect(SellwildFailures.gateState.keys.map((k) => k.suppressed), [0, 0]);
      expect(failures.map((e) => e.label).toSet(), {'feed'});
      expect(badgeDecoration(tester, '\$${json['price']}').color,
          fallbackCardColor);
      expect(SellwildFailures.gateState.sessionCount, 2);

      // Another listing in the same card is checked again. Two minutes on,
      // so the logFailure gate does not fold the repeat into the first. The
      // color is the same config's, already reported, so it is not again.
      SellwildFailures.setContext(clock: () => 1790000000000 + 120000);
      await pumpCard(tester, listingFrom(listings.noPhotosIn('JPY')), config);
      await tester.pump();

      expect(SellwildFailures.gateState.sessionCount, 3);
      expect(actionsOf(failures), [
        'listings.item.invalid',
        'config.color.invalid',
        'listings.item.invalid',
      ]);
    });

    testWidgets('a feed of cards with one bad color reports it once',
        (tester) async {
      final failures = captureFailures();
      final config = configWith(priceColor: 'red', priceFontColor: '#fff');

      await tester.pumpWidget(MaterialApp(
        home: SingleChildScrollView(
          child: Column(children: [
            for (final json in [
              listings.noPhotos(),
              listings.noPhotosIn('GBP'),
              listings.titleOfLength(61),
            ])
              SellwildListingCard(listing: listingFrom(json), config: config),
          ]),
        ),
      ));

      // One report per bad color for the whole feed, not one per card, and
      // not folded by the logFailure gate: the cards did not repeat it.
      expect(actionsOf(failures),
          ['config.color.invalid', 'config.color.invalid']);
      expect(failures.map((e) => e.attributes['msg']), [
        'priceColor is not a hex color',
        'priceFontColor is not a hex color',
      ]);
      expect(SellwildFailures.gateState.keys.map((k) => k.suppressed), [0, 0]);
      expect(find.byType(SellwildListingCard), findsNWidgets(3));
    });

    testWidgets('the same listing with another config is checked again',
        (tester) async {
      final failures = captureFailures();
      final listing = listingFrom(listings.noPhotosIn('GBP'));

      await pumpCard(tester, listing, configWith(priceColor: 'red'));
      // Two minutes on, so the logFailure gate does not fold the repeat.
      SellwildFailures.setContext(clock: () => 1790000000000 + 120000);
      await pumpCard(tester, listing, configWith(priceColor: 'blue'));
      await tester.pump();

      expect(actionsOf(failures),
          ['config.color.invalid', 'config.color.invalid']);
      expect(SellwildFailures.gateState.sessionCount, 2);
    });
  });
}
