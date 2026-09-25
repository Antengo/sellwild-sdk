// Pure mapping of the remote app config (contracts/schemas/app-config
// .schema.json) onto SellwildConfig. SellwildSDK.apply is the thin shell: it
// passes the host OS in and reports what this returns through logFailure.
//
// A value is an issue when it breaks the contract (a JSON type the schema
// does not allow for that key, or CODE '') or cannot be used (an unknown ad
// stack mode, a refresh interval no Duration can hold). A contract-valid value Flutter does
// not read (a numeric zone id, an integral double for an integer key, text
// IAB_CATS) is known drift, recorded in contracts/expectations/drift/
// flutter.json, and not a runtime failure. JSON null is the same as absent
// (FAILURES.md 12.5), so it is never an issue.

import 'failures/failures_core.dart' show coerceFlag, coerceRate;
import 'failures/sellwild_failure_code.dart';
import 'sellwild_config.dart';

/// One remote-config value [applyRemoteConfig] could not use.
class RemoteConfigIssue {
  const RemoteConfigIssue(this.code, this.severity, this.detail);

  /// A SellwildFailureCode constant.
  final String code;

  /// A SellwildFailureSeverity constant.
  final String severity;

  /// What is wrong, naming the key. Never the value itself, which is CMS
  /// text, except a number.
  final String detail;
}

/// What [applyRemoteConfig] built, and the values it could not use.
class RemoteConfigResult {
  const RemoteConfigResult(this.config, this.issues);

  final SellwildConfig config;
  final List<RemoteConfigIssue> issues;
}

/// One logFailure call: every issue with the same code, in the order found.
class RemoteConfigReport {
  const RemoteConfigReport(this.code, this.severity, this.message);

  final String code;
  final String severity;
  final String message;
}

/// The largest AD_REFRESH_INTERVAL (ms) a Duration holds exactly. Beyond it
/// `Duration(milliseconds:)` wraps around to a negative interval.
const double maxRefreshIntervalMs = 9007199254740991;

/// Below this many ms a refresh interval was almost surely written in
/// seconds (30 for 30 s). It is still applied as ms, as before.
const double secondsStyleRefreshBelowMs = 1000;

/// The JSON kind of [value], for issue text.
String jsonKind(Object? value) => switch (value) {
      null => 'null',
      String() => 'text',
      bool() => 'a boolean',
      int() => 'an integer',
      double() => 'a number',
      List() => 'an array',
      Map() => 'an object',
      _ => value.runtimeType.toString(),
    };

/// Maps the CONSTANT_CASE keys of [raw] onto [base]. [isAndroid] picks the
/// APP_*_ANDROID or APP_*_IOS keys. Pure: never throws for any JSON [raw].
RemoteConfigResult applyRemoteConfig(
  Map<String, dynamic> raw,
  SellwildConfig base, {
  required bool isAndroid,
}) {
  final r = _Reader(raw);
  final config = SellwildConfig(
    // Identity. CODE '' breaks the schema (minLength 1) and keeps base, as
    // in core: before, it wiped the partner from every event.
    partnerCode: r.nonEmptyStr('CODE') ?? base.partnerCode,
    slug: r.str('SLUG') ?? base.slug,
    name: r.str('NAME') ?? base.name,
    // '' is the CMS value for "the default cache" (schema), so it keeps base.
    listingsUrl: _nonEmpty(r.str('LISTINGS')) ?? base.listingsUrl,

    // Display
    title: r.str('TITLE') ?? base.title,
    linkText: r.str('LINK_TEXT') ?? base.linkText,
    buyNowText: r.str('BUY_NOW_TEXT') ?? base.buyNowText,
    titleColor: r.color('TITLE_COLOR') ?? base.titleColor,
    titleSize: base.titleSize,
    linkColor: r.color('LINK_COLOR') ?? base.linkColor,
    fontSize: base.fontSize,
    fontColor: r.color('FONT_COLOR') ?? base.fontColor,
    priceColor: r.color('PRICE_COLOR') ?? base.priceColor,
    priceFontColor: r.color('PRICE_FONT_COLOR') ?? base.priceFontColor,
    marginBottom:
        r.integer('MARGIN_BOTTOM', fractionAllowed: true) ?? base.marginBottom,
    colors: r.strList('COLORS') ?? base.colors,
    overlayTitle: r.boolean('OVERLAY_TITLE') ?? base.overlayTitle,
    watermark: r.boolean('WATERMARK') ?? base.watermark,
    watermarkTitle: r.str('WATERMARK_TITLE') ?? base.watermarkTitle,

    // Ad zones
    adType: base.adType,
    bannerZid: r.str('BANNER_ZID', numberAllowed: true) ?? base.bannerZid,
    bottomBannerZid:
        r.str('BOTTOM_BANNER_ZID', numberAllowed: true) ?? base.bottomBannerZid,
    mobileBannerZid:
        r.str('MOBILE_BANNER_ZID', numberAllowed: true) ?? base.mobileBannerZid,
    mobileZids: r.strList('MOBILE_ZID') ?? base.mobileZids,
    hideBannerTop: r.boolean('HIDE_BANNER_TOP') ?? base.hideBannerTop,
    hideBannerBottom: r.boolean('HIDE_BANNER_BOTTOM') ?? base.hideBannerBottom,
    // '' is no ad unit path (as in core; iOS and Android skip an empty tag
    // too), so it keeps base. Before, the banner built defineSlot('').
    gamTag: _nonEmpty(r.str('GAM')) ?? base.gamTag,
    gptProxyUrl: base.gptProxyUrl,
    disableGpt: r.boolean('DISABLE_GPT') ?? base.disableGpt,
    adDisableDisplay: r.boolean('AD_DISABLE_DISPLAY') ?? base.adDisableDisplay,

    // Ad-stack segmentation (GAM vs Prebid)
    adStack: r.adStack() ?? base.adStack,
    adStackByZone: r.adStackByZone() ?? base.adStackByZone,

    // Refresh
    adRefreshMax: r.integer('AD_REFRESH_MAX') ?? base.adRefreshMax,
    adRefreshMaxMobile:
        r.integer('AD_REFRESH_MAX_MOBILE') ?? base.adRefreshMaxMobile,
    adRefreshInterval: r.refreshInterval() ?? base.adRefreshInterval,
    maxFailedAuctions:
        r.integer('MAX_FAILED_AUCTIONS') ?? base.maxFailedAuctions,
    prebidSrc: base.prebidSrc,
    floorMultiplier: base.floorMultiplier,

    // Compliance
    gppEnabled: r.boolean('GPP_ENABLED') ?? base.gppEnabled,
    tcfVersion: r.integer('TCF_VERSION') ?? base.tcfVersion,
    iabCats: r.strList('IAB_CATS', textAllowed: true) ?? base.iabCats,

    // Third-party
    boltive: r.boolean('BOLTIVE') ?? base.boltive,
    boltiveClientId: r.str('BOLTIVE_CLIENT_ID') ?? base.boltiveClientId,
    lotame: r.boolean('LOTAME') ?? base.lotame,

    // Mobile ad controls
    enableInterstitial:
        r.boolean('ENABLE_INTERSTITIAL') ?? base.enableInterstitial,
    enableFullscreenVideo:
        r.boolean('ENABLE_FULLSCREEN_VIDEO') ?? base.enableFullscreenVideo,
    interstitialsPerSession:
        r.integer('INTERSTITIALS_PER_SESSION') ?? base.interstitialsPerSession,
    videoTakeoversPerSession: r.integer('VIDEO_TAKEOVERS_PER_SESSION') ??
        base.videoTakeoversPerSession,

    // App identity: the per-OS key wins (APP_*_IOS/_ANDROID), else the
    // shared one, else base.
    appBundleId:
        r.str(isAndroid ? 'APP_BUNDLE_ID_ANDROID' : 'APP_BUNDLE_ID_IOS') ??
            r.str('APP_BUNDLE_ID') ??
            base.appBundleId,
    appStoreUrl:
        r.str(isAndroid ? 'APP_STORE_URL_ANDROID' : 'APP_STORE_URL_IOS') ??
            r.str('APP_STORE_URL') ??
            base.appStoreUrl,

    // Prebid Server (carried over from base, not read from remote)
    prebidServer: base.prebidServer,

    // Debug
    debug: r.boolean('DEBUG') ?? base.debug,

    // Kill switches (FAILURES.md 5.3, 5.4). Absent or JSON null keeps base.
    eventsEnabled: coerceFlag(r.flag('EVENTS_ENABLED'), base.eventsEnabled),
    failuresEnabled:
        coerceFlag(r.flag('FAILURES_ENABLED'), base.failuresEnabled),
    failuresSampleRate: switch (r.rate('FAILURES_SAMPLE_RATE')) {
      null => base.failuresSampleRate,
      final Object rate => coerceRate(rate),
    },

    // Raw passthrough: every CDN key flows to the WebView verbatim, so new
    // bidders and settings need no SDK release.
    remoteJson: raw,
  );
  return RemoteConfigResult(config, List.unmodifiable(r.issues));
}

/// Groups [issues] into one report per code, in the order the codes were
/// first found; the message lists each issue's detail.
List<RemoteConfigReport> groupIssues(List<RemoteConfigIssue> issues) {
  final byCode = <String, List<RemoteConfigIssue>>{};
  for (final issue in issues) {
    (byCode[issue.code] ??= []).add(issue);
  }
  return [
    for (final MapEntry(key: code, value: group) in byCode.entries)
      RemoteConfigReport(
        code,
        group.first.severity,
        group.map((i) => i.detail).join('; '),
      ),
  ];
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

/// Reads typed values from the raw config and records every value it could
/// not use.
class _Reader {
  _Reader(this.raw);

  final Map<String, dynamic> raw;
  final List<RemoteConfigIssue> issues = [];

  void _issue(String detail,
          {String code = SellwildFailureCode.configFieldInvalid,
          String severity = SellwildFailureSeverity.warn}) =>
      issues.add(RemoteConfigIssue(code, severity, detail));

  void _wrongKind(String key, Object value,
          {String code = SellwildFailureCode.configFieldInvalid,
          String severity = SellwildFailureSeverity.warn}) =>
      _issue('$key is ${jsonKind(value)}', code: code, severity: severity);

  /// Text (schema: string). With [numberAllowed] the schema also allows a
  /// number, which Flutter does not read (drift, not an issue).
  String? str(String key, {bool numberAllowed = false}) {
    final Object? value = raw[key];
    if (value is String) return value;
    if (value != null && !(numberAllowed && value is num)) {
      _wrongKind(key, value);
    }
    return null;
  }

  /// Text the schema requires to be non-empty: '' is an issue and null.
  String? nonEmptyStr(String key) {
    final value = str(key);
    if (value != null && value.isEmpty) {
      _issue('$key is empty');
      return null;
    }
    return value;
  }

  /// A CSS color as text. A color that is not text keeps the base color.
  String? color(String key) {
    final Object? value = raw[key];
    if (value is String) return value;
    if (value != null) {
      _wrongKind(key, value,
          code: SellwildFailureCode.configColorInvalid,
          severity: SellwildFailureSeverity.error);
    }
    return null;
  }

  /// An integer. A finite integral double (5.0) is contract-valid but not
  /// read (drift); so is any finite double when [fractionAllowed] (the
  /// schema says number).
  int? integer(String key, {bool fractionAllowed = false}) {
    final Object? value = raw[key];
    if (value is int) return value;
    if (value is double &&
        value.isFinite &&
        (fractionAllowed || value == value.roundToDouble())) {
      return null;
    }
    if (value is double) {
      _issue(value.isFinite
          ? '$key is not an integer'
          : '$key is not a finite number');
    } else if (value != null) {
      _wrongKind(key, value);
    }
    return null;
  }

  bool? boolean(String key) {
    final Object? value = raw[key];
    if (value is bool) return value;
    if (value != null) _wrongKind(key, value);
    return null;
  }

  /// A list of text. Items that are not text are dropped (as before) and
  /// reported. With [textAllowed] one text is contract-valid but not read
  /// (drift).
  List<String>? strList(String key, {bool textAllowed = false}) {
    final Object? value = raw[key];
    if (value is List) {
      final out = value.whereType<String>().toList();
      final dropped = value.length - out.length;
      if (dropped > 0) _issue('$key has $dropped items that are not text');
      return out;
    }
    if (value != null && !(textAllowed && value is String)) {
      _wrongKind(key, value);
    }
    return null;
  }

  /// EVENTS_ENABLED / FAILURES_ENABLED (schema: boolean, number or text).
  /// The value goes to coerceFlag as is.
  Object? flag(String key) {
    final Object? value = raw[key];
    if (value != null && value is! bool && value is! num && value is! String) {
      _wrongKind(key, value);
    }
    return value;
  }

  /// FAILURES_SAMPLE_RATE (schema: number or text), for coerceRate.
  Object? rate(String key) {
    final Object? value = raw[key];
    if (value != null && value is! num && value is! String) {
      _wrongKind(key, value);
    }
    return value;
  }

  /// AD_STACK. '' is unset (schema).
  SellwildAdStack? adStack() {
    final Object? value = raw['AD_STACK'];
    if (value == null || value == '') return null;
    final parsed = SellwildAdStack.parse(value);
    if (parsed == null) {
      _issue(
          value is String
              ? 'AD_STACK is not a known mode'
              : 'AD_STACK is ${jsonKind(value)}',
          code: SellwildFailureCode.configAdstackInvalid);
    }
    return parsed;
  }

  /// AD_STACK_BY_ZONE. '' is unset (schema); anything but an object keeps
  /// base. Zones with an unknown mode are dropped and reported.
  Map<String, SellwildAdStack>? adStackByZone() {
    final Object? value = raw['AD_STACK_BY_ZONE'];
    if (value is! Map) {
      if (value != null && value != '') {
        _wrongKind('AD_STACK_BY_ZONE', value,
            code: SellwildFailureCode.configAdstackInvalid);
      }
      return null;
    }
    final out = <String, SellwildAdStack>{};
    final unknown = <String>[];
    value.forEach((zone, mode) {
      final parsed = SellwildAdStack.parse(mode);
      if (parsed != null) {
        out['$zone'] = parsed;
      } else {
        unknown.add('$zone');
      }
    });
    if (unknown.isNotEmpty) {
      _issue(
          'AD_STACK_BY_ZONE has no known mode for zones ${unknown.join(',')}',
          code: SellwildFailureCode.configAdstackInvalid);
    }
    return out;
  }

  /// AD_REFRESH_INTERVAL in milliseconds (matches iOS, Android and core),
  /// not seconds. Null keeps base: absent, not a number, or beyond what a
  /// Duration holds (before, Infinity threw and 1e300 wrapped to -1 ms).
  Duration? refreshInterval() {
    const key = 'AD_REFRESH_INTERVAL';
    final Object? value = raw[key];
    if (value is! num) {
      if (value != null) _wrongKind(key, value);
      return null;
    }
    final ms = value.toDouble();
    if (!ms.isFinite || ms.abs() > maxRefreshIntervalMs) {
      _issue('$key is out of range');
      return null;
    }
    if (ms > 0 && ms < secondsStyleRefreshBelowMs) {
      _issue('$key is $value ms; written in seconds?',
          code: SellwildFailureCode.configRefreshIntervalInvalid);
    }
    return Duration(milliseconds: ms.round());
  }
}
