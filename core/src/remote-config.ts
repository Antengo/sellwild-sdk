import { SellwildConfig, AdStack } from './types'
import { WIDGET_BASE_URL, SDK_VERSION } from './config'
import { logFailure, logFailuresWithFlags, type LogFailureInput } from './failures'
import { coerceFlag, coerceRate, parseRate } from './failures/core'
import { jsonKind, parseErrorName } from './json-kind'

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

  // OpenRTB app.publisher.id (== sellers.json seller id / schain sid). Ships as
  // a top-level CDN key; native resolvers read it directly for oRTB injection.
  // Mapped here for typed parity with the native mappers.
  PUBLISHER_ID: 'appPublisherId',

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

  // Analytics kill switch
  EVENTS_ENABLED: 'eventsEnabled',

  // clientFailure kill switch and session sample rate (contracts/FAILURES.md 10)
  FAILURES_ENABLED: 'failuresEnabled',
  FAILURES_SAMPLE_RATE: 'failuresSampleRate',
}

// ── Transform ───��───────────────────────────────────────────────────────────

/**
 * Maps a CDN JSON object (CONSTANT_CASE keys) to a partial SellwildConfig (camelCase).
 *
 * Behavior:
 *  - Known CONSTANT_CASE keys are mapped to their typed camelCase counterparts.
 *  - The raw payload is stashed on `remote` so unknown / forward-compatible
 *    keys (e.g. new bidders the CMS adds after the SDK ships) stay readable
 *    without an SDK release.
 *
 * Pure: it does not report the values it had to ignore or coerce.
 * mapRemoteConfigWithIssues returns those too, and fetchRemoteConfig reports
 * them.
 */
export function mapRemoteConfig(raw: Record<string, unknown>): Partial<SellwildConfig> {
  return mapRemoteConfigWithIssues(raw).config
}

/** A mapped remote config and the failures found while mapping it. */
export interface RemoteConfigMapping {
  config: Partial<SellwildConfig>
  /**
   * One report per CDN key whose value was ignored or coerced:
   * config.adstack.invalid (AD_STACK, AD_STACK_BY_ZONE) and
   * config.field.invalid (IAB_CATS, EVENTS_ENABLED, FAILURES_ENABLED,
   * FAILURES_SAMPLE_RATE). For the caller to report under the config's own
   * EVENTS_ENABLED, FAILURES_ENABLED and FAILURES_SAMPLE_RATE
   * (FAILURES.md 10.1).
   */
  issues: LogFailureInput[]
}

/** mapRemoteConfig, plus the values it had to ignore or coerce. Pure. */
export function mapRemoteConfigWithIssues(raw: Record<string, unknown>): RemoteConfigMapping {
  const mapped: Record<string, unknown> = { remote: raw }
  const issues: LogFailureInput[] = []

  for (const [cdnKey, value] of Object.entries(raw)) {
    const configKey = KEY_MAP[cdnKey]
    if (configKey !== undefined && value !== undefined && value !== null && value !== '') {
      const problem = configValueProblem(configKey, value)
      if (problem) issues.push({ code: problem.code, component: 'remoteConfig', severity: 'warn', message: `${cdnKey} ${problem.text}` })
      mapped[configKey] = coerceConfigValue(configKey, value)
    }
  }

  return { config: mapped as Partial<SellwildConfig>, issues }
}

type ConfigValueProblem = { code: 'config.adstack.invalid' | 'config.field.invalid'; text: string }

// Why coerceConfigValue has to ignore or coerce a value, or null when it
// reads it as sent. The text follows the CDN key in the report and never
// holds the value itself.
function configValueProblem(configKey: string, value: unknown): ConfigValueProblem | null {
  const field = (text: string): ConfigValueProblem => ({ code: 'config.field.invalid', text })
  const adstack = (text: string): ConfigValueProblem => ({ code: 'config.adstack.invalid', text })
  switch (configKey) {
    case 'eventsEnabled':
    case 'failuresEnabled':
      return ['boolean', 'number', 'string'].includes(typeof value) ? null : field(`is ${jsonKind(value)}, read as on`)
    case 'failuresSampleRate':
      // A number outside 0..1 is not an issue: the app-config contract allows
      // it and says the client clamps it (FAILURES.md 5.4). Above 1 reads as
      // 1, every session. Below 0 reads as 0, which samples out every
      // non-fatal report, this one included, so it could never be sent.
      return parseRate(value) === null ? field('is not a number or decimal text, read as 1') : null
    case 'iabCats':
      return Array.isArray(value) || typeof value === 'string' ? null : field(`is ${jsonKind(value)}, read as []`)
    case 'adStack':
      return parseAdStack(value) ? null : adstack(typeof value === 'string' ? 'is not a known mode, read as unset' : `is ${jsonKind(value)}, read as unset`)
    case 'adStackByZone': {
      if (!value || typeof value !== 'object' || Array.isArray(value)) return adstack(`is ${jsonKind(value)}, not a map, read as unset`)
      const modes = Object.values(value as Record<string, unknown>)
      const unknown = modes.filter((mode) => !parseAdStack(mode)).length
      return unknown === 0 ? null : adstack(`has ${unknown} of ${modes.length} zones with an unknown mode, dropped`)
    }
    default:
      return null
  }
}

/**
 * Coerce CDN values into the shape SellwildConfig expects.
 *
 * The CMS sometimes ships scalar values where the SDK type is an array (e.g.
 * `IAB_CATS: "IAB15"` instead of `["IAB15"]`). Normalize at the boundary so
 * downstream code can rely on the typed contract.
 */
function coerceConfigValue(configKey: string, value: unknown): unknown {
  if (configKey === 'eventsEnabled' || configKey === 'failuresEnabled') {
    // Kill switches: enabled unless the CMS ships an explicitly falsy value.
    // The CMS may store booleans as real JSON booleans OR strings, so coerce
    // both (contracts/FAILURES.md 5.3: false/0/no/off, ASCII trim and case).
    // Anything else (unexpected shape) leaves them ON.
    return coerceFlag(value, true)
  }
  if (configKey === 'failuresSampleRate') {
    // A number or decimal text clamped to 0..1; anything else is 1 (FAILURES.md 5.4).
    return coerceRate(value)
  }
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

/** The CDN URL of an app config: `{baseUrl}/app/{partnerCode}/{slug}.json`. Pure. */
export function buildRemoteConfigUrl(baseUrl: string, partnerCode: string, slug: string): string {
  return `${baseUrl}/app/${partnerCode}/${slug}.json`
}

/**
 * The config fetch headers: the `SellwildSDK/<version> (react-native)`
 * User-Agent version beacon (see fetchRemoteConfig). Pure.
 */
export function remoteConfigHeaders(sdkVersion: string): Record<string, string> {
  return { 'User-Agent': `SellwildSDK/${sdkVersion} (react-native)` }
}

/**
 * Which failure a config fetch or body read that rejected reports: the
 * timeout when it fired, nothing (null) for a caller abort, which is not a
 * failure, else `code`. Pure.
 */
export function classifyFetchError<C extends 'config.fetch.network' | 'config.fetch.parse'>(
  code: C,
  timedOut: boolean,
  callerAborted: boolean,
): C | 'config.fetch.timeout' | null {
  if (timedOut) return 'config.fetch.timeout'
  return callerAborted ? null : code
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
 * Each failure is reported once with logFailure (config.fetch.*,
 * config.parse.invalid), and so is each CDN value that had to be ignored or
 * coerced (config.adstack.invalid, config.field.invalid; see
 * mapRemoteConfigWithIssues). A caller abort is not a failure and is not
 * reported.
 *
 * The value reports honor the fetched config's own EVENTS_ENABLED,
 * FAILURES_ENABLED and FAILURES_SAMPLE_RATE (FAILURES.md 10.1) as well as
 * the failure context's: each goes out only when both allow it
 * (logFailuresWithFlags). The failure context does not change, so fetching a
 * config never turns reports on or off for anything else. configure() does
 * not call this; it applies the whole config, overrides included, to the
 * context and then reports the same issues.
 */
export async function fetchRemoteConfig(
  partnerCode: string,
  slug: string,
  options: RemoteConfigOptions = {}
): Promise<Partial<SellwildConfig>> {
  const { config, issues } = await fetchRemoteConfigWithIssues(partnerCode, slug, options)
  logFailuresWithFlags(
    { eventsEnabled: config.eventsEnabled, failuresEnabled: config.failuresEnabled, failuresSampleRate: config.failuresSampleRate },
    issues,
  )
  return config
}

/**
 * fetchRemoteConfig, but the CMS values it had to ignore or coerce come back
 * as `issues` (each with the config URL) instead of being reported, so the
 * caller can report them once the config's own kill switches are applied
 * (FAILURES.md 10.1). A failure to load the config is still reported here:
 * no config flags exist yet, and unset flags mean on (FAILURES.md 3.2).
 * A cached config comes back with no issues: they went out with the fetch
 * that loaded it.
 */
export async function fetchRemoteConfigWithIssues(
  partnerCode: string,
  slug: string,
  options: RemoteConfigOptions = {}
): Promise<RemoteConfigMapping> {
  const cacheKey = `${partnerCode}/${slug}`
  if (remoteConfigCache.has(cacheKey)) {
    return { config: remoteConfigCache.get(cacheKey)!, issues: [] }
  }

  const url = buildRemoteConfigUrl(options.baseUrl || WIDGET_BASE_URL, partnerCode, slug)
  const timeout = options.timeout ?? 5000

  const controller = new AbortController()
  let timedOut = false
  const timer = setTimeout(() => {
    timedOut = true
    controller.abort()
  }, timeout)

  // Combine external signal with timeout
  if (options.signal) {
    options.signal.addEventListener('abort', () => controller.abort())
  }

  // A fetch or body read that rejected, reported as classifyFetchError says.
  const failed = (failure: { code: 'config.fetch.network' | 'config.fetch.parse'; error: unknown; message?: string }): void => {
    const code = classifyFetchError(failure.code, timedOut, options.signal?.aborted === true)
    if (code === 'config.fetch.timeout') {
      logFailure({ code, component: 'remoteConfig', message: `no answer in ${timeout} ms`, url })
    } else if (code !== null) {
      logFailure({ ...failure, code, component: 'remoteConfig', url })
    }
  }
  const empty = (): RemoteConfigMapping => ({ config: {}, issues: [] })

  try {
    // Version beacon: a `SellwildSDK/<version> (react-native)` User-Agent fires
    // on every config fetch (independent of the events kill switch) and lands in
    // CloudFront cs(User-Agent) logs for an installed-base census. RN honors the
    // custom UA; browsers ignore it (web is out of scope for app census). No
    // query params — that would fragment the CloudFront cache.
    let res: Response
    try {
      res = await fetch(url, {
        signal: controller.signal,
        headers: remoteConfigHeaders(SDK_VERSION),
      })
    } catch (error) {
      // Network error, timeout or caller abort — fall back to static config
      failed({ code: 'config.fetch.network', error })
      return empty()
    }
    if (!res.ok) {
      // A missing config answers 403 AccessDenied XML (contracts/samples).
      logFailure({ code: 'config.fetch.http', component: 'remoteConfig', message: `HTTP ${res.status}`, httpStatus: res.status, url })
      return empty()
    }

    let raw: unknown
    try {
      raw = await res.json()
    } catch (error) {
      // Only the error's name is sent: its message quotes part of the body.
      failed({ code: 'config.fetch.parse', message: 'config body is not JSON', error: parseErrorName(error) })
      return empty()
    }
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      logFailure({ code: 'config.parse.invalid', component: 'remoteConfig', message: `config JSON is ${jsonKind(raw)}`, url })
      // mapRemoteConfig(null) throws, which always fell back to {}. Other
      // values still map as they always have.
      if (raw === null) return empty()
    }
    const { config, issues } = mapRemoteConfigWithIssues(raw as Record<string, unknown>)
    // Values the CMS sent that had to be ignored or coerced, for the caller
    // to report. Once per fetch: the mapped config is cached.
    remoteConfigCache.set(cacheKey, config)
    return { config, issues: issues.map((issue) => ({ ...issue, url })) }
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
