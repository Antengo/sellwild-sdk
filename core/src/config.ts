import { SellwildConfig, PartialSellwildConfig } from './types'
import { fetchRemoteConfig, type RemoteConfigOptions } from './remote-config'

export const API_BASE_URL = 'https://api.sellwild.com'
export const WIDGET_BASE_URL = 'https://widget.sellwild.com'
export const SELLWILD_URL = 'https://sellwild.com'
export const EVENTS_URL = 'https://events.sellwild.com/events/queue'

const defaultConfig: Omit<SellwildConfig, 'partnerCode'> = {
  slug: '',
  name: '',
  listingsUrl: undefined,
  apiBaseUrl: API_BASE_URL,

  // Display defaults
  title: '',
  linkText: 'View all',
  buyNowText: 'Buy now',
  titleColor: '#000000',
  titleSize: 16,
  linkColor: '#0066cc',
  linkSize: 14,
  fontSize: 13,
  fontFamily: '',
  fontColor: '#ffffff',
  fontUrl: '',
  priceColor: '#333333',
  priceFontColor: '#ffffff',
  marginBottom: 10,
  cardWidth: '300px',
  cardHeight: '250px',
  overlayTitle: false,
  colors: ['#333333'],
  watermark: false,
  watermarkTitle: 'Powered%20by%20Sellwild',

  // Layout
  defaultWidth: 1200,
  breakpoints: { col2: 600, col3: 900, col4: 1200, col5: 1500, col6: 1800 },

  // Ads
  bannerZid: 0,
  bottomBannerZid: 0,
  mobileBannerZid: 0,
  mobileZids: [],
  displayZids: [],
  skyscraperZid: 0,
  hideBannerTop: false,
  hideBannerBottom: false,
  gamTag: '',
  gamTagDesc: '',
  gptProxyUrl: '',
  disableGpt: false,
  adUnits: '',
  safeFrame: false,
  adDisableDisplay: false,

  // Ad refresh
  adRefreshMax: 0,
  adRefreshMaxMobile: 0,
  adRefreshInterval: 30000,
  maxFailedAuctions: 3,
  prebidDefer: 0,
  prebidSrc: '',
  floorMultiplier: 1,

  // Compliance
  gppEnabled: false,
  tcfVersion: 0,
  consentManagement: '',
  schainSid: '',
  s2sConfig: '',
  iabCats: [],

  // Third-party
  boltive: false,
  boltiveClientId: '',
  lotame: false,
  audigent: false,
  identityHub: false,
  growthcode: '',
  bhTag: '',

  // Analytics — events on by default; CMS EVENTS_ENABLED=false is the kill switch
  eventsEnabled: true,

  // Debug
  debug: false,
  membershipType: '',
  minBidCacheTTL: 0,
  eventHistoryTTL: 0,
}

/**
 * @deprecated since 1.2.0 — prefer `configure(partnerCode, slug)` for the
 * remote-config-first flow. `buildConfig` remains for static/offline integrations.
 */
export function buildConfig(partial: PartialSellwildConfig): SellwildConfig {
  return {
    ...defaultConfig,
    ...partial,
  } as SellwildConfig
}

/**
 * @deprecated since 1.2.0 — prefer `configure(partnerCode, slug, { overrides })`.
 *
 * Builds config with remote overrides from the CDN.
 *
 * Merge order: defaults → partner static config → remote CDN config
 *
 * The remote config is fetched from widget.sellwild.com/app/{partnerCode}/{slug}.json.
 * If the fetch fails (network, timeout, 404), falls back silently to the
 * static config so the app is never blocked by remote config availability.
 */
export async function buildConfigWithRemote(
  partial: PartialSellwildConfig,
  remoteSlug: string,
  options?: RemoteConfigOptions,
): Promise<SellwildConfig> {
  const remote = await fetchRemoteConfig(partial.partnerCode, remoteSlug, options)
  return {
    ...defaultConfig,
    ...partial,
    ...remote,
  } as SellwildConfig
}

export interface ConfigureOptions extends RemoteConfigOptions {
  /**
   * App-controlled values that override the remote CDN config.
   * Use this for values the host app must control at runtime — for example,
   * `appBundleId` from the host's bundle metadata, or `debug: __DEV__`.
   *
   * Merge order: defaults → remote CDN config → overrides
   */
  overrides?: Partial<SellwildConfig>
}

/**
 * The first-class entry point for the SDK in 1.2.0+. Fetches the partner's
 * remote config from the Sellwild CDN and returns a fully-populated
 * `SellwildConfig`.
 *
 * The CDN JSON at `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`
 * carries `LISTINGS`, ad zones, refresh intervals, partners, and compliance
 * flags. Anything missing falls back to the SDK's deterministic defaults.
 *
 * Failure handling: if the fetch fails (network error, timeout, non-2xx),
 * `configure` returns a defaulted `SellwildConfig` with the supplied
 * `partnerCode` and `slug`. Ads still render — `listingsUrl` defaults to
 * `${apiBaseUrl}/widget/listings?partner=${partnerCode}`.
 *
 * @example
 *   const config = await configure('weatherbug', 'weatherbug-main')
 *
 * @example with overrides
 *   const config = await configure('weatherbug', 'weatherbug-main', {
 *     overrides: { appBundleId: 'com.aws.android', debug: __DEV__ },
 *   })
 */
export async function configure(
  partnerCode: string,
  slug: string,
  options: ConfigureOptions = {},
): Promise<SellwildConfig> {
  const { overrides, ...remoteOptions } = options
  const remote = await fetchRemoteConfig(partnerCode, slug, remoteOptions)
  return {
    ...defaultConfig,
    partnerCode,
    slug,
    ...remote,
    ...(overrides ?? {}),
  } as SellwildConfig
}

export function getMainUrl(config: SellwildConfig, type: 'sell' | 'post' | 'buy', source: string): string {
  const base = SELLWILD_URL
  const params = new URLSearchParams({
    p: config.partnerCode,
    utm_source: source,
    utm_medium: 'widget',
  })
  return `${base}/${type}?${params.toString()}`
}

export function currencyToSymbol(currency: string): string {
  const map: Record<string, string> = {
    USD: '$',
    EUR: '€',
    GBP: '£',
    CAD: 'CA$',
    AUD: 'A$',
  }
  return map[currency] || currency || '$'
}
