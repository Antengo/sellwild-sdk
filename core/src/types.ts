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
  /**
   * URL of the listings API. When unset, the SDK derives a default of
   * `${apiBaseUrl}/widget/listings?partner=${partnerCode}`.
   * Optional in 1.2.0+ — typically populated from remote config.
   */
  listingsUrl?: string
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

  /**
   * Global ad-stack override (CDN `AD_STACK`). When set, forces EVERY placement
   * to this stack regardless of per-zone settings — an operational kill-switch.
   * When unset, per-zone (`adStackByZone`) applies, falling back to `both`.
   */
  adStack?: AdStack
  /**
   * Per-placement ad-stack settings (CDN `AD_STACK_BY_ZONE`), keyed by zone id.
   * Applies only when the global `adStack` is unset. e.g. `{ "43": "prebidOnly" }`.
   */
  adStackByZone?: Record<string, AdStack>

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
  /** @deprecated 1.2.1 — populate via remote config; access raw values through `config.remote['IX']`. Kept for back-compat; will be removed in 2.0. */
  ix?: IxConfig
  /** @deprecated 1.2.1 — see `config.remote['OPENX']`. Will be removed in 2.0. */
  openx?: OpenxConfig
  /** @deprecated 1.2.1 — see `config.remote['PUBMATIC']`. Will be removed in 2.0. */
  pubmatic?: PubmaticConfig
  /** @deprecated 1.2.1 — see `config.remote['APPNEXUS']`. Will be removed in 2.0. */
  appnexus?: AppnexusConfig
  /** @deprecated 1.2.1 — see `config.remote['RUBICON']`. Will be removed in 2.0. */
  rubicon?: RubiconConfig
  /** @deprecated 1.2.1 — see `config.remote['APSTAG']`. Will be removed in 2.0. */
  apstag?: ApStagConfig

  // Waterfall partners
  /** @deprecated 1.2.1 — see `config.remote['PUB_VENTURES']`. Will be removed in 2.0. */
  pubVentures?: WaterfallPartnerConfig
  /** @deprecated 1.2.1 — see `config.remote['SAAMBAA']`. Will be removed in 2.0. */
  saambaa?: WaterfallPartnerConfig & { placementD970x250: string; hardcap: number; exclusive: boolean }
  /** @deprecated 1.2.1 — see `config.remote['OPSCO']`. Will be removed in 2.0. */
  opsco?: WaterfallPartnerConfig
  /** @deprecated 1.2.1 — see `config.remote['BIDSTREAM']`. Will be removed in 2.0. */
  bidstream?: WaterfallPartnerConfig

  /**
   * Raw remote-config payload as fetched from the CDN.
   * Populated by `configure(partnerCode, slug)` with the entire JSON document.
   *
   * The widget's WebView attribute parser is case-insensitive and accepts
   * CONSTANT_CASE keys, so every entry in `remote` is forwarded to the widget
   * verbatim. This means the SDK does NOT need a release whenever the CMS
   * adds a new bidder or remote setting — partners receive new fields
   * automatically the moment the CDN JSON includes them.
   *
   * Static callers using `buildConfig({...})` may set this manually.
   */
  remote?: Record<string, unknown>

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

  // Geo — partner-supplied location. On native (iOS/Android) it is emitted as
  // OpenRTB device.geo and seeds SellwildGeoStore; `state` is intended to key
  // per-state listing caches. Bridged to native via the config prop.
  geo?: SellwildGeo

  // Mobile ad controls — toggled remotely via CMS app config
  enableInterstitial?: boolean       // Allow interstitial ads
  enableFullscreenVideo?: boolean    // Allow fullscreen video takeovers
  interstitialsPerSession?: number   // Max interstitials per user session (default: 1)
  videoTakeoversPerSession?: number  // Max fullscreen video takeovers per session (default: 0)

  // Debug
  debug: boolean
  // Server-side auction debug — adds ext.prebid.debug=1 + returnallbidstatus to
  // the Prebid Server auction so the response carries the full debug block
  // (per-bidder status, resolvedrequest, cache calls). Heavier responses; leave
  // off in production. Independent of `debug` (SDK log verbosity).
  pbsDebug?: boolean
  membershipType: string
  minBidCacheTTL: number
  eventHistoryTTL: number
}

/**
 * Partner-supplied geo, emitted as OpenRTB device.geo on native Prebid
 * auctions. All fields optional. On native it also seeds SellwildGeoStore for
 * non-ad consumers. `state` maps to OpenRTB `region`.
 */
export interface SellwildGeo {
  country?: string  // ISO-3166-1 alpha-3, e.g. "USA"
  state?: string    // -> ortb device.geo.region; also keys per-state caches
  city?: string
  zip?: string
  metro?: string    // DMA
  lat?: number
  lon?: number
  type?: number     // ortb geo.type: 1 = GPS, 2 = IP, 3 = user
}

export type PartialSellwildConfig = Partial<SellwildConfig> & {
  partnerCode: string
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

/**
 * Which ad SDK stack a placement runs. Toggled remotely so revenue/measurement
 * can segment GAM (Google Ad Manager / Google Ads) and Prebid independently
 * without an SDK release.
 *
 *  - `both`       — Prebid auction fetches demand, then GAM renders (default;
 *                   the winning Prebid creative or GAM's own line items serve).
 *  - `gamOnly`    — plain GAM request, no Prebid auction.
 *  - `prebidOnly` — Prebid's own rendering path; NO GAM ad request is made, so
 *                   no GAM request/serving fees are incurred.
 */
export type AdStack = 'both' | 'gamOnly' | 'prebidOnly'

// Ad placement size
export type AdSize = '300x250' | '320x50' | '728x90' | '160x600' | '300x600' | '1x1'

export type AdPlacementType = 'banner_top' | 'banner_bottom' | 'inline' | 'interstitial'

export interface AdPlacement {
  type: AdPlacementType
  size: AdSize
  zoneId?: number | string
  gamTag?: string
}
