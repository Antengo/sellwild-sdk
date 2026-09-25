// localized-listings.ts — geo-based secondary-listings integration (core logic).
//
// When enabled, the SDK loads a SECOND listings cache keyed by the user's state
// and disperses those listings into the primary feed at a configured frequency
// (every Nth slot). This module is the PLATFORM-NEUTRAL reference: config
// resolution, state resolution, URL templating, and the every-Nth de-duped
// merge. It does no fetching or geo lookup of its own. The native SDKs
// (iOS/Android) and the web widget mirror these functions with their own
// fetch/geo adapters.
//
// State resolution order (highest first):
//   1. integration.forceState  (remote/CMS force — a known-Alabama site, etc.)
//   2. partner/browser geo state (config.geo.state, or a CloudFront
//      viewer-country-region header captured off the primary listings fetch)
//   3. none → skip the localized cache entirely
//
// Cache format is identical to the primary feed (`result.rs` of listings), so
// the existing listing parser is reused verbatim; a 404 on the templated URL
// (state we have no data for) is a normal skip.
//
// Failures (contracts/FAILURES.md): resolveLocalizedListingsWithIssues is pure
// and returns what is wrong with the config next to the integration, and so
// are the state, URL and merge helpers. resolveLocalizedListings is a thin
// shell over it that reports each issue once with logFailure
// (localized.config.parse, localized.config.invalid), which queues an events
// POST. No state, an empty pool, an unset frequency and an explicit
// `enabled: false` are not failures.

import type { SellwildListing, SellwildConfig, LocalizedListingsConfig } from './types'
import { logFailure, type LogFailureInput } from './failures'
import { jsonKind, parseErrorName } from './json-kind'

/** A fully-resolved localized-listings integration (config validated). */
export interface LocalizedListingsIntegration {
  source?: string
  baseUrl: string
  urlTemplate: string
  /** Dispersion percent (25 → every 4th slot). */
  frequency: number
  /** Forced state (2-letter upper), or undefined. */
  forceState?: string
}

function nonEmpty(v: unknown): string | undefined {
  return typeof v === 'string' && v.trim().length > 0 ? v.trim() : undefined
}

function numeric(v: unknown): number | undefined {
  if (typeof v === 'number' && Number.isFinite(v)) return v
  if (typeof v === 'string') {
    const n = Number(v)
    if (Number.isFinite(n)) return n
  }
  return undefined
}

/** Normalize to a 2-letter uppercase state/region code, or undefined. */
export function normState(v: unknown): string | undefined {
  const s = nonEmpty(v)
  if (!s) return undefined
  // CloudFront viewer-country-region can be "GA" or a longer subdivision; take
  // the trailing 2-letter alpha token when present, else the raw upper value.
  const code = s.toUpperCase()
  return /^[A-Z]{2}$/.test(code) ? code : (code.match(/[A-Z]{2}$/)?.[0] ?? code)
}

// The integration config object: the local config (an object), or
// LOCALIZED_LISTINGS (an object or its JSON text, `jsonText`). Absent, null
// and '' (the CMS "unset") give nothing and no issue.
function readConfigObject(v: unknown, name: string, jsonText: boolean): { raw?: Record<string, unknown>; issue?: LogFailureInput } {
  if (v === undefined || v === null) return {}
  let value = v
  if (jsonText && typeof v === 'string') {
    if (v.trim() === '') return {}
    try {
      value = JSON.parse(v)
    } catch (error) {
      // Only the error's name: its message quotes the config text.
      return { issue: { code: 'localized.config.parse', component: 'localized', severity: 'warn', message: `${name} is not JSON`, error: parseErrorName(error) } }
    }
  }
  if (value && typeof value === 'object' && !Array.isArray(value)) return { raw: value as Record<string, unknown> }
  const text = value !== v ? `${name} JSON text is ${jsonKind(value)}` : `${name} is ${jsonKind(value)}`
  return { issue: invalid(`${text}, not an object`) }
}

function invalid(message: string): LogFailureInput {
  return { code: 'localized.config.invalid', component: 'localized', severity: 'warn', message }
}

/**
 * Resolve the active integration: local `config.localizedListings` wins, else
 * the remote `LOCALIZED_LISTINGS` object (may be a JSON string), else null.
 * Returns null when disabled or missing a baseUrl/urlTemplate. A config that
 * cannot be used is reported (see resolveLocalizedListingsWithIssues).
 */
export function resolveLocalizedListings(
  config: Pick<SellwildConfig, 'localizedListings' | 'remote'>,
): LocalizedListingsIntegration | null {
  const { integration, issues } = resolveLocalizedListingsWithIssues(config)
  for (const issue of issues) logFailure(issue)
  return integration
}

/**
 * resolveLocalizedListings, plus why a present config cannot be used:
 * localized.config.parse (JSON text that does not parse) and
 * localized.config.invalid (not an object, or no baseUrl or urlTemplate while
 * not disabled, or a frequency that is not a number, which reads as 0: no
 * localized listings are mixed in). Pure.
 */
export function resolveLocalizedListingsWithIssues(
  config: Pick<SellwildConfig, 'localizedListings' | 'remote'>,
): { integration: LocalizedListingsIntegration | null; issues: LogFailureInput[] } {
  // The local config wins whenever it is set, as it always has.
  const local = config.localizedListings as unknown
  const name = local !== undefined && local !== null ? 'localizedListings' : 'LOCALIZED_LISTINGS'
  const { raw, issue } =
    name === 'localizedListings'
      ? readConfigObject(local, name, false)
      : readConfigObject(config.remote?.['LOCALIZED_LISTINGS'], name, true)

  if (!raw) return { integration: null, issues: issue ? [issue] : [] }
  if (raw.enabled === false) return { integration: null, issues: [] } // explicit off; absent = on (presence implies intent)

  const baseUrl = nonEmpty(raw.baseUrl)
  const urlTemplate = nonEmpty(raw.urlTemplate)
  if (!baseUrl || !urlTemplate) {
    const missing = [baseUrl ? '' : 'baseUrl', urlTemplate ? '' : 'urlTemplate'].filter(Boolean).join(' or ')
    return { integration: null, issues: [invalid(`${name} has no ${missing}, so it is off`)] }
  }

  // Absent or null is an unset frequency (0), and so is '' (Number('') is 0).
  const frequency = numeric(raw.frequency)
  return {
    integration: {
      source: nonEmpty(raw.source),
      baseUrl,
      urlTemplate,
      frequency: frequency ?? 0,
      forceState: normState(raw.forceState),
    },
    issues: frequency === undefined && raw.frequency != null ? [invalid(`${name} frequency is ${jsonKind(raw.frequency)}, not a number, read as 0`)] : [],
  }
}

/** Forced state wins, then the resolved geo state, else null. */
export function resolveState(
  integration: LocalizedListingsIntegration,
  geoState: string | null | undefined,
): string | null {
  return integration.forceState ?? normState(geoState) ?? null
}

/** Build the cache URL by filling `{state}` (lowercased) into the template. */
export function buildCacheUrl(integration: LocalizedListingsIntegration, state: string): string {
  const path = integration.urlTemplate.replace(/\{state\}/gi, state.toLowerCase())
  const base = integration.baseUrl
  if (base.endsWith('/') && path.startsWith('/')) return base + path.slice(1)
  if (!base.endsWith('/') && !path.startsWith('/')) return base + '/' + path
  return base + path
}

/**
 * Slots between localized listings for a given percent. 25 → 4 (every 4th slot).
 * 0/absent → 0 (disabled); >=100 → 1 (every slot).
 */
export function everyNth(frequencyPercent: number): number {
  if (!frequencyPercent || frequencyPercent <= 0) return 0
  if (frequencyPercent >= 100) return 1
  return Math.max(1, Math.round(100 / frequencyPercent))
}

/** Fisher-Yates shuffle using an injectable RNG (deterministic in tests). */
function shuffle<T>(arr: T[], rng: () => number): T[] {
  const a = arr.slice()
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

/**
 * Replace every Nth slot of `primary` with a localized listing, keeping the
 * total count unchanged. Secondary listings are first de-duped against primary
 * `id`s, then shuffled (random pick "from whatever was returned"), then cycled
 * so every Nth slot is filled. Returns `primary` unchanged when there's nothing
 * to disperse.
 */
export function mergeEveryNth(
  primary: SellwildListing[],
  secondary: SellwildListing[],
  everyN: number,
  rng: () => number = Math.random,
): SellwildListing[] {
  if (everyN <= 0 || secondary.length === 0 || primary.length === 0) return primary
  const primaryIds = new Set(primary.map((l) => String(l.id)))
  const pool = shuffle(
    secondary.filter((l) => l && l.id != null && !primaryIds.has(String(l.id))),
    rng,
  )
  if (pool.length === 0) return primary

  const out: SellwildListing[] = []
  let s = 0
  for (let i = 0; i < primary.length; i++) {
    if ((i + 1) % everyN === 0) {
      out.push(pool[s % pool.length])
      s++
    } else {
      out.push(primary[i])
    }
  }
  return out
}

/** Convenience: resolve state, and if resolvable, produce the cache URL. */
export function localizedCacheUrl(
  integration: LocalizedListingsIntegration,
  geoState: string | null | undefined,
): string | null {
  const state = resolveState(integration, geoState)
  if (!state) return null
  return buildCacheUrl(integration, state)
}
