// What SellwildListingCard shows, decided purely from the listing and the
// config, plus the values it had to replace (reported once per card by the
// widget in sellwild_listing_card.dart).

import 'package:flutter/material.dart';

import 'failures/sellwild_failure_code.dart';
import 'sellwild_config.dart';
import 'sellwild_models.dart';

/// Titles longer than this are cut and end in '...'.
const int cardTitleMaxLength = 60;

/// Currency code to price prefix. Absent or '' is USD.
const Map<String, String> currencySymbols = {
  'USD': '\$',
  'EUR': '€',
  'GBP': '£',
  'CAD': 'CA\$',
  'AUD': 'A\$',
};

/// The prefix for an absent or unknown currency.
const String defaultCurrencySymbol = '\$';

/// The price badge color when a configured color is not hex.
const Color fallbackCardColor = Colors.grey;

/// One value the card had to replace, for logFailure.
class CardIssue {
  const CardIssue(this.code, this.severity, this.message);

  /// A SellwildFailureCode constant.
  final String code;

  /// A SellwildFailureSeverity constant.
  final String severity;

  final String message;
}

/// Everything the card renders.
class ListingCardView {
  const ListingCardView({
    required this.title,
    required this.photoUrl,
    required this.priceText,
    required this.priceColor,
    required this.priceFontColor,
    required this.issues,
  });

  final String title;

  /// Null shows the grey placeholder.
  final String? photoUrl;

  /// Null hides the price badge.
  final String? priceText;
  final Color priceColor;
  final Color priceFontColor;
  final List<CardIssue> issues;
}

final RegExp _hexColor = RegExp(r'^#?[0-9a-fA-F]{6}$');

/// A `#rrggbb` (or `rrggbb`) color, opaque. Null for anything else. A9 fix:
/// before, any text int.tryParse took was used, so 'fff' became 0x000fff
/// (dark blue, not white).
///
/// A 3-digit `#rgb` is null too, so the card shows [fallbackCardColor] and
/// reports config.color.invalid, on purpose: the native feeds do the same
/// (Android FeedTheme.resolve: Color.parseColor throws, fallback and
/// config.color.invalid; iOS SellwildFeedView.parseColor: 6 or 8 digits
/// only, else the fallback). Expanding `#rgb` here would add Flutter-only
/// drift. Recorded as other.card.cssColor in drift/flutter.json.
Color? parseHexColor(String hex) {
  if (!_hexColor.hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.replaceFirst('#', ''), radix: 16));
}

/// [title], cut to [cardTitleMaxLength] characters plus '...'.
String cardTitle(String title) => title.length > cardTitleMaxLength
    ? '${title.substring(0, cardTitleMaxLength)}...'
    : title;

/// The price prefix for [currency].
String currencySymbolFor(String? currency) =>
    currencySymbols[currency ?? ''] ?? defaultCurrencySymbol;

/// The card for [listing] with [config]: pure.
ListingCardView buildListingCardView(
    SellwildListing listing, SellwildConfig config) {
  final issues = <CardIssue>[];

  Color color(String name, String value) {
    final parsed = parseHexColor(value);
    if (parsed != null) return parsed;
    issues.add(CardIssue(SellwildFailureCode.configColorInvalid,
        SellwildFailureSeverity.error, '$name is not a hex color'));
    return fallbackCardColor;
  }

  final currency = listing.currency;
  if (currency != null &&
      currency.isNotEmpty &&
      !currencySymbols.containsKey(currency)) {
    issues.add(CardIssue(
      SellwildFailureCode.listingsItemInvalid,
      SellwildFailureSeverity.warn,
      // An ISO code is not personal data; other text is not echoed.
      RegExp(r'^[A-Z]{3}$').hasMatch(currency)
          ? 'currency $currency has no symbol; $defaultCurrencySymbol used'
          : 'currency is not a known code; $defaultCurrencySymbol used',
    ));
  }

  // displayPrice is null for no price, a price of 0 or less (no badge by
  // design) and text that is not a finite number ('NaN' and 'Infinity'
  // parse, but are no price), which is reported.
  final rawPrice = listing.price;
  if (rawPrice != null &&
      rawPrice.trim().isNotEmpty &&
      !(double.tryParse(rawPrice)?.isFinite ?? false)) {
    issues.add(const CardIssue(SellwildFailureCode.listingsItemInvalid,
        SellwildFailureSeverity.warn, 'price is not a number; no badge'));
  }

  final photo = listing.primaryPhoto;
  final price = listing.displayPrice;
  return ListingCardView(
    title: cardTitle(listing.title),
    photoUrl: photo != null && photo.url.isNotEmpty ? photo.url : null,
    priceText: price == null ? null : '${currencySymbolFor(currency)}$price',
    priceColor: color('priceColor', config.priceColor),
    priceFontColor: color('priceFontColor', config.priceFontColor),
    issues: List.unmodifiable(issues),
  );
}
