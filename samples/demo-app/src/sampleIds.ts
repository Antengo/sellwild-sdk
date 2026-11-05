// Stable element ids for the Maestro flows (e2e/maestro). The one list is
// contracts/e2e/ids.json: add an id there first, and never rename one. Each
// id is set as a testID: the accessibilityIdentifier on iOS and the
// resource-id on Android.
export const SampleId = {
  // Tabs
  tabFeed: 'sw.tab.feed',
  tabAds: 'sw.tab.ads',
  tabListings: 'sw.tab.listings',
  tabDiagnostics: 'sw.tab.diagnostics',

  // Feed
  feedList: 'sw.feed.list',
  feedStatus: 'sw.feed.status',

  // Ads
  adBanner: 'sw.ad.banner',
  adBannerSize: 'sw.ad.banner.size',
  adMrec: 'sw.ad.mrec',
  adMrecSize: 'sw.ad.mrec.size',

  // Listings
  listingsList: 'sw.listings.list',
  listingsRefresh: 'sw.listings.refresh',
  listingsStatus: 'sw.listings.status',
  listingCard: 'sw.listing.card',

  // Diagnostics
  diagSdkVersion: 'sw.diag.sdk_version',
  diagPartner: 'sw.diag.partner',
  diagConfigSource: 'sw.diag.config_source',
  diagListingsUrl: 'sw.diag.listings_url',
  diagFailures: 'sw.diag.failures',
} as const;
