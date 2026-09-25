/// Stable element ids for the Maestro flows (e2e/maestro). The one list is
/// contracts/e2e/ids.json: add an id there first, and never rename one.
abstract final class SampleId {
  // Tabs
  static const tabFeed = 'sw.tab.feed';
  static const tabAds = 'sw.tab.ads';
  static const tabListings = 'sw.tab.listings';
  static const tabDiagnostics = 'sw.tab.diagnostics';
  static const tabLegacy = 'sw.tab.legacy';

  // Feed
  static const feedList = 'sw.feed.list';
  static const feedStatus = 'sw.feed.status';
  static const feedAd = 'sw.feed.ad';
  static const listingCard = 'sw.listing.card';

  // Ads
  static const adBanner = 'sw.ad.banner';
  static const adBannerSize = 'sw.ad.banner.size';
  static const adMrec = 'sw.ad.mrec';
  static const adMrecSize = 'sw.ad.mrec.size';

  // Listings
  static const listingsList = 'sw.listings.list';
  static const listingsRefresh = 'sw.listings.refresh';
  static const listingsStatus = 'sw.listings.status';

  // Diagnostics
  static const diagSdkVersion = 'sw.diag.sdk_version';
  static const diagPartner = 'sw.diag.partner';
  static const diagConfigSource = 'sw.diag.config_source';
  static const diagListingsUrl = 'sw.diag.listings_url';
  static const diagFailures = 'sw.diag.failures';
  static const diagFailureContext = 'sw.diag.failure_context';

  // Legacy
  static const legacyTitle = 'sw.legacy.title';
  static const legacyStatus = 'sw.legacy.status';
  static const legacyWebView = 'sw.legacy.webview';
}
