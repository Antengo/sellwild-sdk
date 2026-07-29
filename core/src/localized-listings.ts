// localized-listings.ts — geo-based secondary-listings integration (core logic).
//
// When enabled, the SDK loads a SECOND listings cache keyed by the user's state
// and disperses those listings into the primary feed at a configured frequency
// (every Nth slot). This module is the PLATFORM-NEUTRAL reference: config
// resolution, state resolution, URL templating, and the every-Nth de-duped
// merge. It performs no I/O. The native SDKs (iOS/Android) and the web widget
// mirror these functions with their own fetch/geo adapters.
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

import type { SellwildListing, SellwildConfig, LocalizedListingsConfig } from './types'

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

function safeParseObject(v: unknown): Record<string, unknown> | undefined {
  if (v && typeof v === 'object') return v as Record<string, unknown>
  if (typeof v === 'string') {
    try {
      const p = JSON.parse(v)
      if (p && typeof p === 'object') return p as Record<string, unknown>
    } catch {
      /* not JSON */
    }
  }
  return undefined
}

/**
 * Resolve the active integration: local `config.localizedListings` wins, else
 * the remote `LOCALIZED_LISTINGS` object (may be a JSON string), else null.
 * Returns null when disabled or missing a baseUrl/urlTemplate.
 */
export function resolveLocalizedListings(
  config: Pick<SellwildConfig, 'localizedListings' | 'remote'>,
): LocalizedListingsIntegration | null {
  const raw: Record<string, unknown> | undefined =
    (config.localizedListings as Record<string, unknown> | undefined) ??
    safeParseObject(config.remote?.['LOCALIZED_LISTINGS'])

  if (!raw) return null
  if (raw.enabled === false) return null // explicit off; absent = on (presence implies intent)

  const baseUrl = nonEmpty(raw.baseUrl)
  const urlTemplate = nonEmpty(raw.urlTemplate)
  if (!baseUrl || !urlTemplate) return null

  return {
    source: nonEmpty(raw.source),
    baseUrl,
    urlTemplate,
    frequency: numeric(raw.frequency) ?? 0,
    forceState: normState(raw.forceState),
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
