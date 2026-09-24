import { SellwildConfig, SellwildListingsResponse, SellwildListing } from './types'
import { DEFAULT_LISTINGS_URL } from './config'
import { logFailure } from './failures'

// The events queue lives in ./event-queue (it must not import logFailure).
// Re-exported here, where it has always been exported from.
export { createEventQueue, eventQueue, type EventQueue, type EventQueueDeps } from './event-queue'

// Cached listing fetches keyed by URL
const listingCache = new Map<string, Promise<SellwildListingsResponse>>()

export interface FetchOptions {
  signal?: AbortSignal
  headers?: Record<string, string>
}

/**
 * Resolves the effective listings URL for a config. Uses `config.listingsUrl`
 * when set, otherwise falls back to the general listings cache
 * (`DEFAULT_LISTINGS_URL`) so 1.2.0 callers using `configure(partnerCode, slug)`
 * don't have to set it.
 */
export function resolveListingsUrl(config: SellwildConfig): string {
  if (config.listingsUrl) return config.listingsUrl
  return DEFAULT_LISTINGS_URL
}

/**
 * Fetches the listings cache for a config. Concurrent and later calls for the
 * same URL share one request until it fails.
 *
 * Failures reject, as they always have, and are reported once with
 * logFailure: listings.fetch.network, listings.fetch.http,
 * listings.fetch.parse and listings.parse.invalid. The HTTP status is not
 * checked beyond that: a non-2xx JSON body still parses as an envelope. A
 * caller abort is not a failure and is not reported.
 */
export async function fetchListings(
  config: SellwildConfig,
  options: FetchOptions = {}
): Promise<SellwildListingsResponse> {
  const url = resolveListingsUrl(config)

  if (listingCache.has(url)) {
    return listingCache.get(url)!
  }

  const promise = loadListings(url, options)
    .catch(err => {
      listingCache.delete(url)
      throw err
    })

  listingCache.set(url, promise)
  return promise
}

async function loadListings(url: string, options: FetchOptions): Promise<SellwildListingsResponse> {
  const aborted = () => options.signal?.aborted === true
  let res: Response
  try {
    res = await fetch(url, {
      signal: options.signal,
      headers: options.headers,
    })
  } catch (error) {
    if (!aborted()) logFailure({ code: 'listings.fetch.network', component: 'listings', error, url })
    throw error
  }
  // A non-2xx answer is reported here and only here, even when its body
  // then fails to parse (S3 answers 403 with XML) or has no listings.
  if (!res.ok) {
    logFailure({ code: 'listings.fetch.http', component: 'listings', message: `HTTP ${res.status}`, httpStatus: res.status, url })
  }

  let data: unknown
  try {
    data = await res.json()
  } catch (error) {
    if (res.ok && !aborted()) logFailure({ code: 'listings.fetch.parse', component: 'listings', error, url })
    throw error
  }
  if (res.ok && !hasListingsArray(data)) {
    logFailure({ code: 'listings.parse.invalid', component: 'listings', message: 'no result.rs array', url })
  }
  return parseListingsResponse(data)
}

// The envelope unwrapping, unchanged: `result.rs`, else `result.listings`,
// else []. A null body still throws a TypeError here, as it always has.
function parseListingsResponse(data: unknown): SellwildListingsResponse {
  const body = data as { result?: unknown }
  const result = (body.result || body) as {
    rs?: SellwildListing[]
    listings?: SellwildListing[]
    config?: Record<string, unknown>
    widgetCacheVersionId?: string
  }
  const listings: SellwildListing[] = result.rs || result.listings || []
  return {
    listings,
    config: result.config || {},
    widgetCacheVersionId: result.widgetCacheVersionId || '0',
  }
}

// Whether parseListingsResponse will pick a real array.
function hasListingsArray(data: unknown): boolean {
  if (data === null || typeof data !== 'object') return false
  const result = (data as { result?: unknown }).result || data
  if (result === null || typeof result !== 'object') return false
  const { rs, listings } = result as { rs?: unknown; listings?: unknown }
  return Array.isArray(rs || listings)
}

export function clearListingCache(): void {
  listingCache.clear()
}

export interface TagCacheOptions {
  keywords: string
  count: number
  signal?: AbortSignal
}

export async function fetchTagCacheListings(
  options: TagCacheOptions
): Promise<SellwildListing[]> {
  const { keywords, count } = options
  if (!keywords || !count) return []

  const url = `https://tbd4rmdvjk.execute-api.us-east-1.amazonaws.com/dev/listings?keywords=${encodeURIComponent(keywords)}&count=${count}&v=1`

  return fetch(url, { signal: options.signal })
    .then(res => res.json())
    .then(data => Array.isArray(data) ? data.slice(0, count) : [])
    .catch(() => [])
}
