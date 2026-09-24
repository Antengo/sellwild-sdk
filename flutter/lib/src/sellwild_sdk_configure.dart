import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'failures/failures_core.dart' show coerceFlag, coerceRate;
import 'failures/sellwild_failure_code.dart';
import 'failures/sellwild_failures.dart';
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
  SellwildSDK._(); // coverage:ignore-line static only class never built

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
      return apply(raw, base, isAndroid: isAndroidHost());
    } catch (e) {
      // Applying is configure's own step, not the remote fetch.
      report(SellwildFailureCode.configApplyException,
          component: SellwildFailureComponent.configure, error: e);
      return base;
    }
  }

  /// Maps CONSTANT_CASE CDN keys onto the corresponding [SellwildConfig] fields.
  /// Exposed for testing. Pure when [isAndroid] is given, as configure always
  /// gives it. An external caller that leaves it out gets [isAndroidHost], the
  /// one impure fallback, to pick the APP_*_IOS/_ANDROID keys.
  static SellwildConfig apply(
    Map<String, dynamic> raw,
    SellwildConfig base, {
    bool? isAndroid,
  }) {
    final android = isAndroid ?? isAndroidHost();
    String? str(String k) => raw[k] is String ? raw[k] as String : null;
    int? integer(String k) => raw[k] is int ? raw[k] as int : null;
    double? dbl(String k) {
      final v = raw[k];
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return null;
    }

    bool? boolean(String k) => raw[k] is bool ? raw[k] as bool : null;
    List<String>? strList(String k) {
      final v = raw[k];
      if (v is List) return v.whereType<String>().toList();
      return null;
    }

    // AD_REFRESH_INTERVAL is milliseconds (matches iOS/Android/core), not seconds.
    final refreshMs = dbl('AD_REFRESH_INTERVAL');

    return SellwildConfig(
      // Identity
      partnerCode: str('CODE') ?? base.partnerCode,
      slug: str('SLUG') ?? base.slug,
      name: str('NAME') ?? base.name,
      listingsUrl: str('LISTINGS') ?? base.listingsUrl,

      // Display
      title: str('TITLE') ?? base.title,
      linkText: str('LINK_TEXT') ?? base.linkText,
      buyNowText: str('BUY_NOW_TEXT') ?? base.buyNowText,
      titleColor: str('TITLE_COLOR') ?? base.titleColor,
      titleSize: base.titleSize,
      linkColor: str('LINK_COLOR') ?? base.linkColor,
      fontSize: base.fontSize,
      fontColor: str('FONT_COLOR') ?? base.fontColor,
      priceColor: str('PRICE_COLOR') ?? base.priceColor,
      priceFontColor: str('PRICE_FONT_COLOR') ?? base.priceFontColor,
      marginBottom: integer('MARGIN_BOTTOM') ?? base.marginBottom,
      colors: strList('COLORS') ?? base.colors,
      overlayTitle: boolean('OVERLAY_TITLE') ?? base.overlayTitle,
      watermark: boolean('WATERMARK') ?? base.watermark,
      watermarkTitle: str('WATERMARK_TITLE') ?? base.watermarkTitle,

      // Ad zones
      adType: base.adType,
      bannerZid: str('BANNER_ZID') ?? base.bannerZid,
      bottomBannerZid: str('BOTTOM_BANNER_ZID') ?? base.bottomBannerZid,
      mobileBannerZid: str('MOBILE_BANNER_ZID') ?? base.mobileBannerZid,
      mobileZids: strList('MOBILE_ZID') ?? base.mobileZids,
      hideBannerTop: boolean('HIDE_BANNER_TOP') ?? base.hideBannerTop,
      hideBannerBottom: boolean('HIDE_BANNER_BOTTOM') ?? base.hideBannerBottom,
      gamTag: str('GAM') ?? base.gamTag,
      gptProxyUrl: base.gptProxyUrl,
      disableGpt: boolean('DISABLE_GPT') ?? base.disableGpt,
      adDisableDisplay: boolean('AD_DISABLE_DISPLAY') ?? base.adDisableDisplay,

      // Ad-stack segmentation (GAM vs Prebid)
      adStack: SellwildAdStack.parse(raw['AD_STACK']) ?? base.adStack,
      adStackByZone: () {
        final v = raw['AD_STACK_BY_ZONE'];
        if (v is! Map) return base.adStackByZone;
        final out = <String, SellwildAdStack>{};
        v.forEach((zone, mode) {
          final parsed = SellwildAdStack.parse(mode);
          if (parsed != null) out['$zone'] = parsed;
        });
        return out;
      }(),

      // Refresh
      adRefreshMax: integer('AD_REFRESH_MAX') ?? base.adRefreshMax,
      adRefreshMaxMobile:
          integer('AD_REFRESH_MAX_MOBILE') ?? base.adRefreshMaxMobile,
      adRefreshInterval: refreshMs != null
          ? Duration(milliseconds: refreshMs.round())
          : base.adRefreshInterval,
      maxFailedAuctions: integer('MAX_FAILED_AUCTIONS') ?? base.maxFailedAuctions,
      prebidSrc: base.prebidSrc,
      floorMultiplier: base.floorMultiplier,

      // Compliance
      gppEnabled: boolean('GPP_ENABLED') ?? base.gppEnabled,
      tcfVersion: integer('TCF_VERSION') ?? base.tcfVersion,
      iabCats: strList('IAB_CATS') ?? base.iabCats,

      // Third-party
      boltive: boolean('BOLTIVE') ?? base.boltive,
      boltiveClientId: str('BOLTIVE_CLIENT_ID') ?? base.boltiveClientId,
      lotame: boolean('LOTAME') ?? base.lotame,

      // Mobile ad controls
      enableInterstitial:
          boolean('ENABLE_INTERSTITIAL') ?? base.enableInterstitial,
      enableFullscreenVideo:
          boolean('ENABLE_FULLSCREEN_VIDEO') ?? base.enableFullscreenVideo,
      interstitialsPerSession:
          integer('INTERSTITIALS_PER_SESSION') ?? base.interstitialsPerSession,
      videoTakeoversPerSession: integer('VIDEO_TAKEOVERS_PER_SESSION') ??
          base.videoTakeoversPerSession,

      // App identity — per-platform override wins (APP_*_IOS/_ANDROID), else shared, else base.
      appBundleId:
          str(android ? 'APP_BUNDLE_ID_ANDROID' : 'APP_BUNDLE_ID_IOS') ??
              str('APP_BUNDLE_ID') ??
              base.appBundleId,
      appStoreUrl:
          str(android ? 'APP_STORE_URL_ANDROID' : 'APP_STORE_URL_IOS') ??
              str('APP_STORE_URL') ??
              base.appStoreUrl,

      // Prebid Server (carry over from base — not overridden by remote in 1.2.0)
      prebidServer: base.prebidServer,

      // Debug
      debug: boolean('DEBUG') ?? base.debug,

      // Kill switches (FAILURES.md 5.3, 5.4). Absent or JSON null keeps base.
      eventsEnabled: coerceFlag(raw['EVENTS_ENABLED'], base.eventsEnabled),
      failuresEnabled:
          coerceFlag(raw['FAILURES_ENABLED'], base.failuresEnabled),
      failuresSampleRate: raw['FAILURES_SAMPLE_RATE'] == null
          ? base.failuresSampleRate
          : coerceRate(raw['FAILURES_SAMPLE_RATE']),

      // Raw passthrough — every CDN key flows to the WebView verbatim,
      // so new bidders/settings don't require an SDK release.
      remoteJson: raw,
    );
  }
}
