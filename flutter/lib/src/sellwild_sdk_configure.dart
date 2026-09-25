import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'failures/sellwild_failure_code.dart';
import 'failures/sellwild_failures.dart';
import 'remote_config.dart';
import 'sellwild_api.dart';
import 'sellwild_config.dart';

/// First-class entry point for configuring the Sellwild SDK.
///
/// In 1.2.0+, partners can integrate the SDK with just a `partnerCode` and
/// `slug`. Everything else — listings URL, ad zones, app identity, refresh
/// intervals, waterfall partners, compliance flags — is fetched from the
/// Sellwild CDN at app launch.
///
/// ```dart
/// final config = await SellwildSDK.configure(
///   partnerCode: 'weatherbug',
///   slug: 'weatherbug-main',
/// );
/// ```
///
/// On any network failure, timeout, or 404 the call returns a
/// `SellwildConfig(partnerCode: ...)` with deterministic defaults (the
/// listings endpoint is derived from `partnerCode`), so ads still render. The
/// failure is reported once through logFailure (config.fetch.*).
class SellwildSDK {
  SellwildSDK._();

  /// The host OS check configure passes to [apply]: the one place the SDK
  /// reads Platform. Tests replace it to reach the Android keys.
  @visibleForTesting
  static bool Function() isAndroidHost = _platformIsAndroid;

  static bool _platformIsAndroid() => Platform.isAndroid;

  /// Build a [SellwildConfig] by fetching `partnerCode/slug.json` from the
  /// Sellwild CDN and applying it onto SDK defaults.
  ///
  /// [overrides] runs after the remote config is applied. Use it for
  /// app-controlled values (e.g. `appBundleId` from your app package). If it
  /// throws, the failure is reported and the exception reaches the caller.
  static Future<SellwildConfig> configure({
    required String partnerCode,
    required String slug,
    Duration timeout = const Duration(seconds: 5),
    SellwildConfig Function(SellwildConfig)? overrides,
    http.Client? client,
  }) async {
    // Partner first, before any fetch, so a config failure carries it
    // (FAILURES.md 3.2), and so events stamp `attributes.code`.
    SellwildFailures.setContext(partnerCode: partnerCode);
    SellwildAPIClient.instance.partnerCode = partnerCode;

    var config = SellwildConfig(partnerCode: partnerCode);
    final httpClient = client ?? http.Client();
    try {
      // Either way config keeps the defaults it could not replace, so ads
      // still render; that fallback is not a second failure.
      config = await _fetchRemote(
        httpClient,
        'https://widget.sellwild.com/app/$partnerCode/$slug.json',
        timeout,
        config,
      );
    } finally {
      if (client == null) httpClient.close();
    }

    if (overrides != null) {
      try {
        config = overrides(config);
      } catch (e) {
        SellwildFailures.log(
          code: SellwildFailureCode.configOverridesException,
          component: SellwildFailureComponent.configure,
          error: e,
        );
        rethrow;
      }
    }

    SellwildFailures.setContext(
      partnerCode: config.partnerCode,
      debug: config.debug,
      eventsEnabled: config.eventsEnabled,
      failuresEnabled: config.failuresEnabled,
      failuresSampleRate: config.failuresSampleRate,
    );
    SellwildAPIClient.instance
      ..partnerCode = config.partnerCode
      ..eventsEnabled = config.eventsEnabled;
    return config;
  }

  /// GETs the remote config at [url] and applies it onto [base]. Returns
  /// [base] unchanged when any step fails, after reporting that step once.
  static Future<SellwildConfig> _fetchRemote(
    http.Client httpClient,
    String url,
    Duration timeout,
    SellwildConfig base,
  ) async {
    void report(
      String code, {
      String component = SellwildFailureComponent.remoteConfig,
      Object? error,
      String? message,
      int? status,
    }) =>
        SellwildFailures.log(
          code: code,
          component: component,
          error: error,
          message: message,
          httpStatus: status,
          url: url,
        );

    final http.Response response;
    try {
      // Version beacon: fires on every config fetch (independent of the events
      // kill switch) and lands in CloudFront cs(User-Agent) logs for an
      // installed-base census.
      response = await httpClient.get(
        Uri.parse(url),
        headers: {'User-Agent': 'SellwildSDK/$sellwildSdkVersion (flutter)'},
      ).timeout(timeout);
    } catch (e) {
      report(
        e is TimeoutException
            ? SellwildFailureCode.configFetchTimeout
            : SellwildFailureCode.configFetchNetwork,
        error: e,
      );
      return base;
    }
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      // A missing config is a 403 AccessDenied from S3, not a 404.
      report(SellwildFailureCode.configFetchHttp,
          message: 'HTTP $status', status: status);
      return base;
    }

    final Object? raw;
    try {
      raw = jsonDecode(response.body);
    } on FormatException catch (e) {
      report(SellwildFailureCode.configFetchParse, error: e);
      return base;
    }
    if (raw is! Map<String, dynamic>) {
      report(SellwildFailureCode.configParseInvalid,
          message: 'config JSON is ${raw == null ? 'null' : raw.runtimeType}');
      return base;
    }

    try {
      return _applyAndReport(raw, base, isAndroidHost(), url);
    } catch (e) {
      // Applying is configure's own step, not the remote fetch.
      report(SellwildFailureCode.configApplyException,
          component: SellwildFailureComponent.configure, error: e);
      return base;
    }
  }

  /// Maps CONSTANT_CASE CDN keys onto the corresponding [SellwildConfig] fields.
  /// Exposed for testing. The mapping is pure (applyRemoteConfig in
  /// remote_config.dart); each value it cannot use is reported once through
  /// logFailure (config.field.invalid, config.color.invalid,
  /// config.adstack.invalid, config.refresh_interval.invalid) and the base
  /// value is kept. configure always gives [isAndroid]; an external caller
  /// that leaves it out gets [isAndroidHost], the one impure fallback, to
  /// pick the APP_*_IOS/_ANDROID keys.
  static SellwildConfig apply(
    Map<String, dynamic> raw,
    SellwildConfig base, {
    bool? isAndroid,
  }) =>
      _applyAndReport(raw, base, isAndroid ?? isAndroidHost(), null);

  static SellwildConfig _applyAndReport(
    Map<String, dynamic> raw,
    SellwildConfig base,
    bool isAndroid,
    String? url,
  ) {
    final result = applyRemoteConfig(raw, base, isAndroid: isAndroid);
    for (final report in groupIssues(result.issues)) {
      SellwildFailures.log(
        code: report.code,
        component: SellwildFailureComponent.remoteConfig,
        severity: report.severity,
        message: report.message,
        url: url,
      );
    }
    return result.config;
  }
}
