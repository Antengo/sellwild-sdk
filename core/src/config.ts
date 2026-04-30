import { SellwildConfig, PartialSellwildConfig } from './types'

export const API_BASE_URL = 'https://api.sellwild.com'
export const WIDGET_BASE_URL = 'https://widget.sellwild.com'
export const SELLWILD_URL = 'https://sellwild.com'
export const EVENTS_URL = 'https://tbd4rmdvjk.execute-api.us-east-1.amazonaws.com/dev/events/queue'

const defaultConfig: Omit<SellwildConfig, 'partnerCode' | 'listingsUrl'> = {
  slug: '',
  name: '',
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

  // Debug
  debug: false,
  membershipType: '',
  minBidCacheTTL: 0,
  eventHistoryTTL: 0,
}

export function buildConfig(partial: PartialSellwildConfig): SellwildConfig {
  return {
    ...defaultConfig,
    ...partial,
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
