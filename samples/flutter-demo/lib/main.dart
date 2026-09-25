/// Sellwild Sample (Flutter): the SDK's Flutter surfaces on five tabs.
///
///   cd samples/flutter-demo && flutter run
///
/// What the Flutter SDK has, and so what this app shows:
///   1. Native: SellwildSDK.configure, SellwildAPIClient.fetchListings and
///      clearCache, SellwildListingCard (a Flutter card), and the public
///      failure sink (SellwildFailures.setContext(sink: ...)).
///   2. WebView: SellwildBanner (every Flutter ad) and SellwildWidget (the
///      deprecated all-in-one widget, on the Legacy tab only).
///   3. Not in the Flutter SDK: a feed component, a native ad view and a
///      house ad view. The app builds its feed from fetchListings, and its
///      ads are SellwildBanner WebViews.
///
/// No Google Mobile Ads SDK is linked, so there is no GADApplicationIdentifier
/// (iOS) and no com.google.android.gms.ads.APPLICATION_ID (Android).
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'src/sample_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The e2e flows (e2e/maestro) find elements by their Semantics
  // identifiers. Keep the semantics tree on from launch, so the ids are there
  // before a test driver asks. An app without e2e flows does not need this.
  SemanticsBinding.instance.ensureSemantics();
  runApp(const SampleApp());
}
