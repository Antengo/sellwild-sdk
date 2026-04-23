/// Sellwild SDK configuration.
/// Mirrors the web widget's ICustomizations, adapted for Flutter.
class SellwildConfig {
  // Identity
  final String partnerCode;
  final String listingsUrl;
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

  const SellwildConfig({
    required this.partnerCode,
    required this.listingsUrl,
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
    this.appBundleId,
    this.appStoreUrl,
    this.prebidServer,
    this.debug = false,
  });

  Map<String, dynamic> toJson() => {
        'partnerCode': partnerCode,
        'listingsUrl': listingsUrl,
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
