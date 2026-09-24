// The Flutter registry mirror against contracts/failure-codes.json
// (FAILURES.md 4.2): SellwildFailureCode.all holds exactly the codes whose
// `clients` include flutter, in registry order, and the component and
// severity constants match the pure core's lists.

import 'package:flutter_test/flutter_test.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';
import 'package:sellwild_sdk/src/failures/failures_core.dart';

import '../support/fixtures.dart';

void main() {
  final registry = (loadFailureCodes() as List).cast<Map<String, dynamic>>();

  test('SellwildFailureCode.all is every flutter code, in registry order', () {
    final flutterCodes = [
      for (final entry in registry)
        if ((entry['clients'] as List).contains('flutter'))
          entry['code'] as String,
    ];

    expect(flutterCodes, isNotEmpty);
    expect(SellwildFailureCode.all, flutterCodes);
  });

  test('every mirrored code passes the pure core format check unchanged', () {
    for (final code in SellwildFailureCode.all) {
      expect(normalizeCode(code), code);
    }
  });

  test('the call sites use registry codes', () {
    // The codes this lane's call sites pass (sellwild_sdk_configure.dart,
    // sellwild_api.dart).
    const used = [
      SellwildFailureCode.configFetchNetwork,
      SellwildFailureCode.configFetchTimeout,
      SellwildFailureCode.configFetchHttp,
      SellwildFailureCode.configFetchParse,
      SellwildFailureCode.configParseInvalid,
      SellwildFailureCode.configApplyException,
      SellwildFailureCode.configOverridesException,
      SellwildFailureCode.listingsFetchNetwork,
      SellwildFailureCode.listingsFetchTimeout,
      SellwildFailureCode.listingsFetchHttp,
      SellwildFailureCode.listingsFetchParse,
      SellwildFailureCode.listingsParseInvalid,
      SellwildFailureCode.listingsItemInvalid,
      SellwildFailureCode.listingsClientMissing,
    ];

    expect(SellwildFailureCode.all, containsAll(used));
  });

  test('component and severity constants match the core', () {
    expect(
      [
        SellwildFailureComponent.configure,
        SellwildFailureComponent.remoteConfig,
        SellwildFailureComponent.listings,
        SellwildFailureComponent.localized,
        SellwildFailureComponent.feed,
        SellwildFailureComponent.banner,
        SellwildFailureComponent.native,
        SellwildFailureComponent.video,
        SellwildFailureComponent.house,
        SellwildFailureComponent.bridge,
        SellwildFailureComponent.webview,
        SellwildFailureComponent.widget,
        SellwildFailureComponent.shorts,
        SellwildFailureComponent.tv,
        SellwildFailureComponent.flipcard,
        SellwildFailureComponent.growthcode,
        SellwildFailureComponent.geo,
        SellwildFailureComponent.storage,
      ],
      failureComponents,
    );
    expect(
      [
        SellwildFailureSeverity.fatal,
        SellwildFailureSeverity.error,
        SellwildFailureSeverity.warn,
      ],
      failureSeverities,
    );
  });

  test('every registry component is a known label', () {
    for (final entry in registry) {
      final component = entry['component'] as String;
      expect(
        component == 'unknown' || failureComponents.contains(component),
        isTrue,
        reason: '${entry['code']} has component $component',
      );
    }
  });
}
