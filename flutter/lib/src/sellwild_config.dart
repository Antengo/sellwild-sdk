/// Sellwild SDK configuration.
/// Mirrors the web widget's ICustomizations, adapted for Flutter.
class SellwildConfig {
  // Identity
  final String partnerCode;

  /// URL of the listings API. Optional in 1.2.0+ — typically populated from
  /// remote config. When null, [effectiveListingsUrl] derives a default of
  /// `'$apiBaseUrl/widget/listings?partner=$partnerCode'`.
  final String? listingsUrl;
  final String slug;
  final String name;
  final String apiBaseUrl;

  // Display
  final String? title;
  final String? linkText;
  final String? buyNowText;
  final String titleColor;
  final int titleSize;
  final String linkColor;
  final int fontSize;
  final String fontColor;
  final String priceColor;
  final String priceFontColor;
  final int marginBottom;
  final List<String> colors;
  final bool overlayTitle;
  final bool watermark;
  final String watermarkTitle;

  // Ads - Display
  /// Ad system to initialize. Defaults to "PrebidOnly". AdStack silently
  /// no-ops if this is unset, so the SDK always sets it.
  final String? adType;
  final String? bannerZid;
  final String? bottomBannerZid;
  final String? mobileBannerZid;
  final List<String> mobileZids;
  final bool hideBannerTop;
  final bool hideBannerBottom;
  final String? gamTag;
  final String? gptProxyUrl;
  final bool disableGpt;
  final bool adDisableDisplay;

  /// Global ad-stack override (CDN `AD_STACK`). When set, forces EVERY
  /// placement to this stack regardless of [adStackByZone]. When null, per-zone
  /// applies, falling back to [SellwildAdStack.both]. See [SellwildAdStack].
  final SellwildAdStack? adStack;

  /// Per-placement ad-stack settings (CDN `AD_STACK_BY_ZONE`), keyed by zone id.
  /// Applies only when the global [adStack] is null.
  final Map<String, SellwildAdStack> adStackByZone;

  // Ads - Refresh
  final int adRefreshMax;
  final int adRefreshMaxMobile;
  final Duration adRefreshInterval;
  final int maxFailedAuctions;
  final String? prebidSrc;
  final double floorMultiplier;

  // Ads - Compliance
  final bool gppEnabled;
  final int tcfVersion;
  final List<String> iabCats;

  // Third-party
  final bool boltive;
  final String boltiveClientId;
  final bool lotame;

  // Mobile ad controls (toggled remotely via CMS app config)
  final bool enableInterstitial;
  final bool enableFullscreenVideo;
  final int interstitialsPerSession;
  final int videoTakeoversPerSession;

  // Mobile app identity (for ortb2.app in Prebid.js)
  // Without appBundleId, Prebid.js sends bids as web (ortb2.site) traffic instead
  // of in-app traffic. DSPs that buy app inventory separately will not bid, and
  // app-ads.txt enforcement is bypassed.
  final String? appBundleId;   // iOS bundle ID or Android package name
  final String? appStoreUrl;   // App Store / Play Store URL

  // Prebid Server S2S (optional)
  // Route all Prebid.js bidder calls through a Prebid Server instance instead of running
  // client-side adapters in the WebView. Solves cookie/IDFA limitations.
  // Leave null to use the default Prebid.js client-side mode.
  final PrebidServerConfig? prebidServer;

  // Debug
  final bool debug;

  /// Raw remote-config payload as fetched from the CDN. Populated by
  /// [SellwildSDK.configure]. The widget's WebView attribute parser is
  /// case-insensitive and accepts arbitrary keys, so every entry in this
  /// payload is forwarded to the widget verbatim. The SDK does NOT need a
  /// release whenever the CMS adds a new bidder or remote setting.
  final Map<String, dynamic>? remoteJson;

  const SellwildConfig({
    required this.partnerCode,
    this.listingsUrl,
    this.slug = '',
    this.name = '',
    this.apiBaseUrl = 'https://api.sellwild.com',
    this.title,
    this.linkText = 'View all',
    this.buyNowText = 'Buy now',
    this.titleColor = '#000000',
    this.titleSize = 16,
    this.linkColor = '#0066cc',
    this.fontSize = 13,
    this.fontColor = '#ffffff',
    this.priceColor = '#333333',
    this.priceFontColor = '#ffffff',
    this.marginBottom = 10,
    this.colors = const ['#333333'],
    this.overlayTitle = false,
    this.watermark = false,
    this.watermarkTitle = 'Powered by Sellwild',
    this.adType,
    this.bannerZid,
    this.bottomBannerZid,
    this.mobileBannerZid,
    this.mobileZids = const [],
    this.hideBannerTop = false,
    this.hideBannerBottom = false,
    this.gamTag,
    this.gptProxyUrl,
    this.disableGpt = false,
    this.adDisableDisplay = false,
    this.adStack,
    this.adStackByZone = const {},
    this.adRefreshMax = 0,
    this.adRefreshMaxMobile = 0,
    this.adRefreshInterval = const Duration(seconds: 30),
    this.maxFailedAuctions = 3,
    this.prebidSrc,
    this.floorMultiplier = 1.0,
    this.gppEnabled = false,
    this.tcfVersion = 0,
    this.iabCats = const [],
    this.boltive = false,
    this.boltiveClientId = '',
    this.lotame = false,
    this.enableInterstitial = false,
    this.enableFullscreenVideo = false,
    this.interstitialsPerSession = 1,
    this.videoTakeoversPerSession = 0,
    this.appBundleId,
    this.appStoreUrl,
    this.prebidServer,
    this.debug = false,
    this.remoteJson,
  });

  /// Effective listings URL. Returns [listingsUrl] when set, otherwise derives
  /// a deterministic default from [partnerCode].
  String get effectiveListingsUrl {
    final url = listingsUrl;
    if (url != null && url.isNotEmpty) return url;
    return '$apiBaseUrl/widget/listings?partner=$partnerCode';
  }

  Map<String, dynamic> toJson() => {
        'partnerCode': partnerCode,
        'listingsUrl': effectiveListingsUrl,
        'slug': slug,
        'name': name,
        'apiBaseUrl': apiBaseUrl,
        if (title != null) 'title': title,
        if (linkText != null) 'linkText': linkText,
        if (buyNowText != null) 'buyNowText': buyNowText,
        'titleColor': titleColor,
        'titleSize': titleSize,
        'linkColor': linkColor,
        'fontSize': fontSize,
        'fontColor': fontColor,
        'priceColor': priceColor,
        'priceFontColor': priceFontColor,
        'marginBottom': marginBottom,
        'colors': colors,
        'overlayTitle': overlayTitle,
        'watermark': watermark,
        'hideBannerTop': hideBannerTop,
        'hideBannerBottom': hideBannerBottom,
        if (gamTag != null) 'gamTag': gamTag,
        if (gptProxyUrl != null) 'gptProxyUrl': gptProxyUrl,
        'disableGpt': disableGpt,
        'adRefreshMax': adRefreshMax,
        'adRefreshMaxMobile': adRefreshMaxMobile,
        'adRefreshInterval': adRefreshInterval.inMilliseconds,
        'boltive': boltive,
        'boltiveClientId': boltiveClientId,
        'enableInterstitial': enableInterstitial,
        'enableFullscreenVideo': enableFullscreenVideo,
        'interstitialsPerSession': interstitialsPerSession,
        'videoTakeoversPerSession': videoTakeoversPerSession,
        'debug': debug,
      };
}

/// Configuration for routing Prebid.js header bidding through a Prebid Server instance.
/// Solves cookie and IDFA limitations that affect Prebid.js running in a native WebView.
class PrebidServerConfig {
  /// Your Prebid Server account ID.
  final String accountId;

  /// Full URL to the Prebid Server auction endpoint.
  /// e.g. 'https://prebid-server.example.com/openrtb2/auction'
  final String endpoint;

  /// Bidder codes to route through Prebid Server.
  /// Must match the s2s adapter names in your Prebid Server config.
  final List<String> bidders;

  /// S2S auction timeout in ms. Default: 1500.
  final int timeout;

  /// Optional Prebid Server /cookie_sync endpoint.
  final String? syncEndpoint;

  const PrebidServerConfig({
    required this.accountId,
    required this.endpoint,
    required this.bidders,
    this.timeout = 1500,
    this.syncEndpoint,
  });
}

/// Which ad SDK stack a placement runs. Toggled remotely via the CDN keys
/// `AD_STACK` (global) and `AD_STACK_BY_ZONE` (per-zone) so GAM (Google Ad
/// Manager / Google Ads) and Prebid can be segmented without an SDK release.
///
///  - [both]       Prebid auction fetches demand, then GAM renders (default).
///  - [gamOnly]    Plain GAM request, no Prebid auction.
///  - [prebidOnly] Prebid's own rendering path; NO GAM ad request is made, so
///                 no GAM request/serving fees are incurred.
enum SellwildAdStack {
  both,
  gamOnly,
  prebidOnly;

  /// Parse a CDN string (case/alias tolerant). Returns null if unknown.
  static SellwildAdStack? parse(Object? raw) {
    if (raw is! String) return null;
    final k = raw.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    switch (k) {
      case 'both':
      case 'all':
      case 'default':
        return SellwildAdStack.both;
      case 'gam':
      case 'gamonly':
      case 'google':
      case 'gads':
      case 'googleads':
        return SellwildAdStack.gamOnly;
      case 'prebid':
      case 'prebidonly':
      case 'prebidsdk':
        return SellwildAdStack.prebidOnly;
      default:
        return null;
    }
  }

  /// Resolve the effective stack for a placement.
  ///
  /// Precedence (matches all platforms):
  ///   1. Global [config.adStack] — hard-wins for every placement.
  ///   2. Per-zone [config.adStackByZone] for [zoneId].
  ///   3. [both] (today's default behavior).
  static SellwildAdStack resolve(SellwildConfig config, [String? zoneId]) {
    final global = config.adStack;
    if (global != null) return global;
    if (zoneId != null) {
      final perZone = config.adStackByZone[zoneId];
      if (perZone != null) return perZone;
    }
    return SellwildAdStack.both;
  }
}

enum SellwildAdSize {
  banner320x50(320, 50),
  mrec300x250(300, 250),
  leaderboard728x90(728, 90),
  halfPage300x600(300, 600),
  wideSkyscraper160x600(160, 600);

  const SellwildAdSize(this.width, this.height);
  final int width;
  final int height;

  String get label => '${width}x$height';
}
