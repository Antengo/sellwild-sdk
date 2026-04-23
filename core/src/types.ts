// Core types shared across all SDK platforms

export interface SellwildPhoto {
  url: string
  thumbUrl: string
  background?: string
}

export interface SellwildUser {
  id: string
  firstName: string
  lastName: string
  username: string
  membershipType: string
  trustLevel: string
  has_photo: string
  photos: SellwildPhoto[]
  isPhoneVerified: boolean
}

export interface SellwildListing {
  id: string
  status: string
  title: string
  text: string
  url: string
  categoryId: string
  categoryGroupId: string
  currency: string
  price: string
  strikePrice: string
  has_photo: boolean
  photo_count: number
  photos: SellwildPhoto[]
  createdDate: string
  videoUrl: string
  shippable: string
  listingType: string
  dataSourceId: string
  user: SellwildUser
  distance?: number
}

export interface SellwildListingsResponse {
  listings: SellwildListing[]
  config: Record<string, unknown>
  widgetCacheVersionId?: string
}

// Ad network configuration
export interface AdNetworkConfig {
  disabled?: boolean
}

export interface IxConfig extends AdNetworkConfig {
  siteIdM: string
  siteIdMB: string
  siteIdD: string
  siteIdDB: string
  siteIdD160x600: string
  siteIdD300x600: string
}

export interface OpenxConfig extends AdNetworkConfig {
  delDomain: string
  unitM: string
  unitMB: string
  unitD: string
  unitDB: string
  unitD160x600: string
  unitD300x600: string
}

export interface PubmaticConfig extends AdNetworkConfig {
  pubIdM: string
  pubIdD: string
  adSlotM: string
  adSlotMB: string
  adSlotD: string
  adSlotD300x250: string
  adSlotD728x90: string
  adSlotD160x600: string
  adSlotD300x600: string
}

export interface AppnexusConfig extends AdNetworkConfig {
  placementIdM: number
  placementIdD: number
  placementIdM300x250: number
  placementIdM320x50: number
  placementIdD300x250: number
  placementIdD728x90: number
  placementIdD160x600: number
  placementIdD300x600: number
}

export interface RubiconConfig extends AdNetworkConfig {
  accountId: number
  siteIdM: number
  zoneIdM: number
  siteIdD: number
  zoneIdD: number
}

export interface WaterfallPartnerConfig extends AdNetworkConfig {
  floorM: number
  floorD: number
  placementM300x250: string
  placementM320x50: string
  placementD300x250: string
  placementD728x90: string
  placementD160x600: string
  placementD300x600: string
  probabilityM: number
  probabilityD: number
  frequencyMax: number
  frequencyDuration: number
  geo: string
}

export interface ApStagConfig {
  pubId: string
  floorM: number
  floorD: number
}

export interface GeoBlock {
  continents: string
  countries: string
  states: string
  cities: string
}

// Main SDK configuration (mobile-adapted from ICustomizations)
export interface SellwildConfig {
  // Identity
  partnerCode: string
  slug: string
  name: string

  // API
  listingsUrl: string
  apiBaseUrl: string

  // Display
  title?: string
  linkText?: string
  buyNowText?: string
  titleColor: string
  titleSize: number
  linkColor: string
  linkSize: number
  fontSize: number
  fontFamily: string
  fontColor: string
  fontUrl: string
  priceColor: string
  priceFontColor: string
  marginBottom: number
  cardWidth: string
  cardHeight: string
  overlayTitle: boolean
  colors: string[]
  css?: string
  watermark: boolean
  watermarkTitle: string

  // Layout
  defaultWidth: number
  breakpoints: { col2: number; col3: number; col4: number; col5: number; col6: number }

  // Ads - display
  bannerZid: number | string
  bottomBannerZid: number | string
  mobileBannerZid: number | string
  mobileZids: (number | string)[]
  displayZids: (number | string)[]
  skyscraperZid: number | string
  hideBannerTop: boolean
  hideBannerBottom: boolean
  gamTag: string
  gamTagDesc: string
  gptProxyUrl: string
  disableGpt: boolean
  adUnits: string
  safeFrame: boolean
  adDisableDisplay: boolean

  // Ads - refresh
  adRefreshMax: number
  adRefreshMaxMobile: number
  adRefreshInterval: number
  maxFailedAuctions: number
  prebidDefer: number
  prebidSrc: string
  floorMultiplier: number

  // Ads - geo
  adGeoBlock?: GeoBlock
  adGeoBlockRefresh?: GeoBlock

  // Ads - compliance
  gppEnabled: boolean
  tcfVersion: number
  gdprApplies?: boolean
  tcString?: string
  consentManagement: string
  schainSid: string
  s2sConfig: string
  iabCats: string[]

  // Ad network bidders
  ix?: IxConfig
  openx?: OpenxConfig
  pubmatic?: PubmaticConfig
  appnexus?: AppnexusConfig
  rubicon?: RubiconConfig
  apstag?: ApStagConfig

  // Waterfall partners
  pubVentures?: WaterfallPartnerConfig
  saambaa?: WaterfallPartnerConfig & { placementD970x250: string; hardcap: number; exclusive: boolean }
  opsco?: WaterfallPartnerConfig
  bidstream?: WaterfallPartnerConfig

  // Third-party integrations
  boltive: boolean
  boltiveClientId: string
  lotame: boolean
  audigent: boolean
  identityHub: boolean
  growthcode: string
  bhTag: string

  // Prebid Server S2S — routes header bidding through a Prebid Server instance instead of
  // running client-side adapters in the WebView. Solves cookie/IDFA limitations.
  // Leave undefined to use the default Prebid.js client-side mode.
  prebidServer?: PrebidServerConfig

  // Mobile app identity — used to populate ortb2.app when Prebid.js runs in a native WebView.
  // Without these, Prebid.js sends bids as web (ortb2.site) traffic instead of in-app traffic,
  // which suppresses fill from DSPs that buy app inventory differently and breaks app-ads.txt enforcement.
  appBundleId?: string    // iOS bundle ID or Android package name (e.g., "com.mycompany.myapp")
  appStoreUrl?: string    // App Store or Google Play URL for the host app

  // Debug
  debug: boolean
  membershipType: string
  minBidCacheTTL: number
  eventHistoryTTL: number
}

export type PartialSellwildConfig = Partial<SellwildConfig> & {
  partnerCode: string
  listingsUrl: string
}

// ─── Prebid Server (S2S) configuration ───────────────────────────────────────
//
// Two Prebid modes are supported by this SDK:
//
//  Mode A — Prebid.js in WebView (default)
//    Prebid.js runs client-side inside the WebView. Each bidder adapter makes
//    direct HTTP requests from the WebView. Works without any additional setup
//    but has the limitations described in VALIDATION.md (cookies, IDFA, etc.).
//
//  Mode B — Prebid Server S2S
//    Prebid.js in the WebView routes all bids through a Prebid Server instance
//    using the s2sConfig module. The WebView makes one server call; Prebid Server
//    fans out to all configured bidders server-side. Solves cookie and IDFA
//    issues because the auction happens server-to-server.
//    Requires a running Prebid Server (self-hosted or AppNexus/Magnite hosted).
//
// Set `prebidServer` on SellwildConfig to enable Mode B.

export interface PrebidServerConfig {
  /** Your Prebid Server account ID */
  accountId: string
  /**
   * Full URL to your Prebid Server auction endpoint.
   * e.g. 'https://prebid-server.example.com/openrtb2/auction'
   * Hosted options: AppNexus (https://prebid.adnxs.com/pbs/v1/openrtb2/auction),
   *                 Rubicon (https://prebid-server.rubiconproject.com/openrtb2/auction)
   */
  endpoint: string
  /**
   * Bidder codes to route through Prebid Server.
   * Must match the s2s adapter names in your Prebid Server config.
   * e.g. ['appnexus', 'rubicon', 'ix', 'openx']
   */
  bidders: string[]
  /** S2S auction timeout in ms. Default: 1500 */
  timeout?: number
  /**
   * Prebid Server /cookie_sync endpoint (optional).
   * If omitted, derived from `endpoint` by replacing the path.
   */
  syncEndpoint?: string
}

// SDK event types
export interface SdkEvent {
  event: string
  action?: string
  label?: string
  amount?: number
  attributes?: Record<string, string | number | boolean>
}

// Ad placement size
export type AdSize = '300x250' | '320x50' | '728x90' | '160x600' | '300x600' | '1x1'

export type AdPlacementType = 'banner_top' | 'banner_bottom' | 'inline' | 'interstitial'

export interface AdPlacement {
  type: AdPlacementType
  size: AdSize
  zoneId?: number | string
  gamTag?: string
}
