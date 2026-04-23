/// Sellwild mobile advertising SDK for Flutter.
///
/// Provides widgets and utilities for embedding Sellwild marketplace listings
/// and ad units inside Flutter mobile apps.
///
/// Quick start:
/// ```dart
/// import 'package:sellwild_sdk/sellwild_sdk.dart';
///
/// final config = SellwildConfig(
///   partnerCode: 'mysite',
///   listingsUrl: 'https://api.sellwild.com/widget/listings?partner=mysite',
/// );
///
/// // Full widget
/// SellwildWidget(config: config, onListingTap: (l) => openDetail(l))
///
/// // Banner ad
/// SellwildBanner(config: config, adSize: SellwildAdSize.mrec300x250, zoneId: '12345')
/// ```
library sellwild_sdk;

export 'src/sellwild_config.dart';
export 'src/sellwild_models.dart';
export 'src/sellwild_widget.dart';
export 'src/sellwild_api.dart';
export 'src/sellwild_listing_card.dart';
