import 'package:sellwild_sdk/sellwild_sdk.dart';

/// What the sample passes to the SDK. It is the same on every platform's
/// sample app, so the e2e flows see the same app.
abstract final class SampleSettings {
  /// Sellwild's own partner code. Never use a real partner's code here.
  static const partnerCode = 'sellwild';

  /// There is no app config for this slug on the CDN (it answers 403). So
  /// configure keeps the SDK's built-in config and reports
  /// config.fetch.http once a launch. That is expected.
  static const slug = 'sellwild-sample';

  /// Sellwild's own listings feed, passed as the public listingsUrl.
  static const listingsUrl =
      'https://cache.sellwild.com/listings-img-data-sm-avif-fandom';

  /// This app's bundle id (iOS) and application id (Android).
  static const appId = 'com.sellwild.sample.flutter';

  /// Google's public GPT test ad unit. SellwildBanner uses GPT when the
  /// config has a GAM tag; the built-in Flutter config has none, and a made-up
  /// zone id would send requests to Sellwild's live ad server.
  static const gamTestAdUnit = '/6499/example/banner';

  /// The feed puts one ad row after this many listing cards.
  static const cardsPerAd = 4;
}

/// Where the config came from: the CDN, or the SDK's built-in fallback.
enum ConfigSource { remote, fallback }

/// [config]'s source: configure sets remoteJson only when the CDN answered
/// with a config.
ConfigSource configSourceOf(SellwildConfig config) =>
    config.remoteJson == null ? ConfigSource.fallback : ConfigSource.remote;

/// The configure `overrides` of the sample: app-controlled values. The
/// listings URL, app id and debug flag are always the sample's; the title and
/// GAM tag only when the CDN config has none.
///
/// SellwildConfig has no copyWith, so every field is copied by hand. A field
/// the SDK adds later needs a line here, or it drops back to its default.
SellwildConfig withSampleValues(SellwildConfig c) {
  final gamTag = c.gamTag;
  return SellwildConfig(
    partnerCode: c.partnerCode,
    listingsUrl: SampleSettings.listingsUrl,
    slug: c.slug,
    name: c.name,
    title: c.title ?? 'Sellwild Sample',
    linkText: c.linkText,
    buyNowText: c.buyNowText,
    titleColor: c.titleColor,
    titleSize: c.titleSize,
    linkColor: c.linkColor,
    fontSize: c.fontSize,
    fontColor: c.fontColor,
    priceColor: c.priceColor,
    priceFontColor: c.priceFontColor,
    marginBottom: c.marginBottom,
    colors: c.colors,
    overlayTitle: c.overlayTitle,
    watermark: c.watermark,
    watermarkTitle: c.watermarkTitle,
    adType: c.adType,
    bannerZid: c.bannerZid,
    bottomBannerZid: c.bottomBannerZid,
    mobileBannerZid: c.mobileBannerZid,
    mobileZids: c.mobileZids,
    hideBannerTop: c.hideBannerTop,
    hideBannerBottom: c.hideBannerBottom,
    gamTag: gamTag == null || gamTag.isEmpty
        ? SampleSettings.gamTestAdUnit
        : gamTag,
    gptProxyUrl: c.gptProxyUrl,
    disableGpt: c.disableGpt,
    adDisableDisplay: c.adDisableDisplay,
    adStack: c.adStack,
    adStackByZone: c.adStackByZone,
    adRefreshMax: c.adRefreshMax,
    adRefreshMaxMobile: c.adRefreshMaxMobile,
    adRefreshInterval: c.adRefreshInterval,
    maxFailedAuctions: c.maxFailedAuctions,
    prebidSrc: c.prebidSrc,
    floorMultiplier: c.floorMultiplier,
    gppEnabled: c.gppEnabled,
    tcfVersion: c.tcfVersion,
    iabCats: c.iabCats,
    boltive: c.boltive,
    boltiveClientId: c.boltiveClientId,
    lotame: c.lotame,
    enableInterstitial: c.enableInterstitial,
    enableFullscreenVideo: c.enableFullscreenVideo,
    interstitialsPerSession: c.interstitialsPerSession,
    videoTakeoversPerSession: c.videoTakeoversPerSession,
    appBundleId: SampleSettings.appId,
    appStoreUrl: c.appStoreUrl,
    prebidServer: c.prebidServer,
    debug: true,
    eventsEnabled: c.eventsEnabled,
    failuresEnabled: c.failuresEnabled,
    failuresSampleRate: c.failuresSampleRate,
    remoteJson: c.remoteJson,
  );
}
