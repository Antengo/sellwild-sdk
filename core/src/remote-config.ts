import { SellwildConfig, AdStack } from './types'
import { WIDGET_BASE_URL } from './config'

/**
 * Remote config — fetches app config JSON from the CDN.
 *
 * The sellwild-widget CMS publishes configs as JSON at:
 *   https://widget.sellwild.com/app/{slug}.json
 *
 * The JSON uses CONSTANT_CASE keys (IX, AD_REFRESH_MAX, HIDE_BANNER_TOP, etc.)
 * which we map to the camelCase SellwildConfig fields the SDK expects.
 */

// ── Key mapping ─────────────────────────────────────────────────────────────

/** Maps CONSTANT_CASE CDN keys → camelCase SellwildConfig keys */
const KEY_MAP: Record<string, keyof SellwildConfig> = {
  CODE: 'partnerCode',
  NAME: 'name',
  SLUG: 'slug',
  LISTINGS: 'listingsUrl',

  // Display
  TITLE: 'title',
  LINK_TEXT: 'linkText',
  BUY_NOW_TEXT: 'buyNowText',
  TITLE_COLOR: 'titleColor',
  LINK_COLOR: 'linkColor',
  FONT_FAMILY: 'fontFamily',
  FONT_URL: 'fontUrl',
  FONT_COLOR: 'fontColor',
  PRICE_COLOR: 'priceColor',
  PRICE_FONT_COLOR: 'priceFontColor',
  MARGIN_BOTTOM: 'marginBottom',
  CARD_WIDTH: 'cardWidth',
  OVERLAY_TITLE: 'overlayTitle',
  COLORS: 'colors',
  CSS: 'css',
  WATERMARK: 'watermark',
  WATERMARK_TITLE: 'watermarkTitle',

  // Ad zones
  BANNER_ZID: 'bannerZid',
  BOTTOM_BANNER_ZID: 'bottomBannerZid',
  MOBILE_BANNER_ZID: 'mobileBannerZid',
  MOBILE_ZID: 'mobileZids',
  DISPLAY_ZID: 'displayZids',
  HIDE_BANNER_TOP: 'hideBannerTop',
  HIDE_BANNER_BOTTOM: 'hideBannerBottom',
  GAM: 'gamTag',
  DISABLE_GPT: 'disableGpt',
  AD_UNITS: 'adUnits',
  SAFE_FRAME: 'safeFrame',
  AD_DISABLE_DISPLAY: 'adDisableDisplay',

  // Ad-stack segmentation (GAM vs Prebid)
  AD_STACK: 'adStack',
  AD_STACK_BY_ZONE: 'adStackByZone',

  // Ad refresh
  AD_REFRESH_MAX: 'adRefreshMax',
  AD_REFRESH_MAX_MOBILE: 'adRefreshMaxMobile',
  AD_REFRESH_INTERVAL: 'adRefreshInterval',
  MAX_FAILED_AUCTIONS: 'maxFailedAuctions',
  PREBID_DEFER: 'prebidDefer',
  PREBID_SRC: 'prebidSrc',

  // Geo
  AD_GEO_BLOCK: 'adGeoBlock',
  AD_GEO_BLOCK_REFRESH: 'adGeoBlockRefresh',

  // Compliance
  GPP_ENABLED: 'gppEnabled',
  TCF_VERSION: 'tcfVersion',
  CONSENT_MANAGEMENT: 'consentManagement',
  SCHAIN_SID: 'schainSid',
  S2S_CONFIG: 's2sConfig',
  IAB_CATS: 'iabCats',

  // Ad network objects — mapped as-is (lowercase key)
  IX: 'ix',
  OPENX: 'openx',
  PUBMATIC: 'pubmatic',
  APPNEXUS: 'appnexus',
  RUBICON: 'rubicon',
  APSTAG: 'apstag',

  // Waterfall partners
  PUB_VENTURES: 'pubVentures',
  SAAMBAA: 'saambaa',
  OPSCO: 'opsco',
  BIDSTREAM: 'bidstream',

  // Third-party
  BOLTIVE: 'boltive',
  BOLTIVE_CLIENT_ID: 'boltiveClientId',
  LOTAME: 'lotame',
  AUDIGENT: 'audigent',
  IDENTITY_HUB: 'identityHub',
  GROWTHCODE: 'growthcode',
  BH_TAG: 'bhTag',

  // Mobile app identity
  APP_BUNDLE_ID: 'appBundleId',
  APP_STORE_URL: 'appStoreUrl',

  // Mobile ad controls
  ENABLE_INTERSTITIAL: 'enableInterstitial',
  ENABLE_FULLSCREEN_VIDEO: 'enableFullscreenVideo',
  INTERSTITIALS_PER_SESSION: 'interstitialsPerSession',
  VIDEO_TAKEOVERS_PER_SESSION: 'videoTakeoversPerSession',
}

// ── Transform ───��───────────────────────────────────────────────────────────

/**
 * Maps a CDN JSON object (CONSTANT_CASE keys) to a partial SellwildConfig (camelCase).
 *
 * Behavior:
 *  - Known CONSTANT_CASE keys are mapped to their typed camelCase counterparts.
 *  - The raw payload is stashed on `remote` so unknown / forward-compatible
 *    keys (e.g. new bidders the CMS adds after the SDK ships) flow through to
 *    the WebView attribute serializer without an SDK release.
 */
export function mapRemoteConfig(raw: Record<string, unknown>): Partial<SellwildConfig> {
  const mapped: Record<string, unknown> = { remote: raw }

  for (const [cdnKey, value] of Object.entries(raw)) {
    const configKey = KEY_MAP[cdnKey]
    if (configKey !== undefined && value !== undefined && value !== null && value !== '') {
      mapped[configKey] = coerceConfigValue(configKey, value)
    }
  }

  return mapped as Partial<SellwildConfig>
}

/**
 * Coerce CDN values into the shape SellwildConfig expects.
 *
 * The CMS sometimes ships scalar values where the SDK type is an array (e.g.
 * `IAB_CATS: "IAB15"` instead of `["IAB15"]`). Normalize at the boundary so
 * downstream code can rely on the typed contract.
 */
function coerceConfigValue(configKey: string, value: unknown): unknown {
  if (configKey === 'iabCats') {
    if (Array.isArray(value)) return value
    if (typeof value === 'string') {
      return value.split(',').map((s) => s.trim()).filter(Boolean)
    }
    return []
  }
  if (configKey === 'adStack') {
    return parseAdStack(value)
  }
  if (configKey === 'adStackByZone') {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      const out: Record<string, AdStack> = {}
      for (const [zone, mode] of Object.entries(value as Record<string, unknown>)) {
        const parsed = parseAdStack(mode)
        if (parsed) out[String(zone)] = parsed
      }
      return out
    }
    return undefined
  }
  return value
}

/**
 * Normalize a CDN ad-stack string into the typed {@link AdStack} union.
 * Tolerant of casing and common aliases. Returns `undefined` for unknown
 * values so callers can fall back to their default.
 */
export function parseAdStack(value: unknown): AdStack | undefined {
  if (typeof value !== 'string') return undefined
  switch (value.trim().toLowerCase().replace(/[\s_-]/g, '')) {
    case 'both':
    case 'all':
    case 'default':
      return 'both'
    case 'gam':
    case 'gamonly':
    case 'google':
    case 'gads':
    case 'googleads':
      return 'gamOnly'
    case 'prebid':
    case 'prebidonly':
    case 'prebidsdk':
      return 'prebidOnly'
    default:
      return undefined
  }
}

/**
 * Resolve the effective ad stack for a placement.
 *
 * Precedence (matches all native platforms):
 *   1. Global `adStack` (CDN `AD_STACK`) — hard-wins for every placement.
 *   2. Per-zone `adStackByZone[zoneId]` (CDN `AD_STACK_BY_ZONE`).
 *   3. `both` (today's default behavior).
 */
export function resolveAdStack(
  config: Pick<SellwildConfig, 'adStack' | 'adStackByZone'>,
  zoneId?: number | string | null,
): AdStack {
  if (config.adStack) return config.adStack
  if (zoneId !== undefined && zoneId !== null) {
    const perZone = config.adStackByZone?.[String(zoneId)]
    if (perZone) return perZone
  }
  return 'both'
}

// ── Fetch ────────────��──────────────────────────────────────────────────────

export interface RemoteConfigOptions {
  /** Override the base URL (default: https://widget.sellwild.com) */
  baseUrl?: string
  /** Abort signal */
  signal?: AbortSignal
  /** Timeout in ms (default: 5000) */
  timeout?: number
}

/** Cache of fetched remote configs keyed by slug */
const remoteConfigCache = new Map<string, Partial<SellwildConfig>>()

/**
 * Fetches the app config JSON from the CDN and returns a partial SellwildConfig.
 *
 * URL pattern: {baseUrl}/app/{partnerCode}/{slug}.json
 *
 * Example: fetchRemoteConfig('realgm', 'realgm-realgm')
 *   → https://widget.sellwild.com/app/realgm/realgm-realgm.json
 *
 * On failure (network error, 404, timeout) returns an empty object so the SDK
 * falls back to its static defaults — remote config is additive, never blocking.
 */
export async function fetchRemoteConfig(
  partnerCode: string,
  slug: string,
  options: RemoteConfigOptions = {}
): Promise<Partial<SellwildConfig>> {
  const cacheKey = `${partnerCode}/${slug}`
  if (remoteConfigCache.has(cacheKey)) {
    return remoteConfigCache.get(cacheKey)!
  }

  const baseUrl = options.baseUrl || WIDGET_BASE_URL
  const url = `${baseUrl}/app/${partnerCode}/${slug}.json`
  const timeout = options.timeout ?? 5000

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeout)

  // Combine external signal with timeout
  if (options.signal) {
    options.signal.addEventListener('abort', () => controller.abort())
  }

  try {
    const res = await fetch(url, { signal: controller.signal })
    if (!res.ok) return {}

    const raw = await res.json() as Record<string, unknown>
    const config = mapRemoteConfig(raw)
    remoteConfigCache.set(cacheKey, config)
    return config
  } catch {
    // Network error or timeout — fall back to static config
    return {}
  } finally {
    clearTimeout(timer)
  }
}

/**
 * Clears the remote config cache. Call on app foreground or session refresh
 * to pick up CMS changes.
 */
export function clearRemoteConfigCache(): void {
  remoteConfigCache.clear()
}
