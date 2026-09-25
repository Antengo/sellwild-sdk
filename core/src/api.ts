import { SellwildConfig, SellwildListingsResponse, SellwildListing } from './types'
import { DEFAULT_LISTINGS_URL } from './config'
import { logFailure } from './failures'
import { jsonKind, parseErrorName } from './json-kind'

// The events queue lives in ./event-queue (it must not import logFailure).
// Re-exported here, where it has always been exported from.
export {
  capQueue,
  createEventQueue,
  eventQueue,
  requeueFailedBatch,
  resolveUid,
  stampEventAttributes,
  takeBatch,
  type EventQueue,
  type EventQueueDeps,
  type EventStamp,
} from './event-queue'

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
    // Only the error's name is sent: its message quotes part of the body.
    if (res.ok && !aborted()) logFailure({ code: 'listings.fetch.parse', component: 'listings', message: 'listings body is not JSON', error: parseErrorName(error), url })
    throw error
  }
  if (res.ok && !hasListingsArray(data)) {
    logFailure({ code: 'listings.parse.invalid', component: 'listings', message: 'no result.rs array', url })
  }
  return parseListingsResponse(data)
}

/**
 * Unwraps a listings cache body: `result.rs`, else `result.listings`, else
 * []. Pure. A value there that is not an array gives [] (it used to come back
 * as `listings`, and React Native's useSellwildListings crashed mapping over
 * it). A null body still throws a TypeError, as it always has; fetchListings
 * rejects with it.
 */
export function parseListingsResponse(data: unknown): SellwildListingsResponse {
  const body = data as { result?: unknown }
  const result = (body.result || body) as {
    rs?: unknown
    listings?: unknown
    config?: Record<string, unknown>
    widgetCacheVersionId?: string
  }
  const picked = result.rs || result.listings
  return {
    listings: Array.isArray(picked) ? (picked as SellwildListing[]) : [],
    config: result.config || {},
    widgetCacheVersionId: result.widgetCacheVersionId || '0',
  }
}

/** Whether parseListingsResponse finds a real array in `data`. Pure. */
export function hasListingsArray(data: unknown): boolean {
  if (data === null || typeof data !== 'object') return false
  const result = (data as { result?: unknown }).result || data
  if (result === null || typeof result !== 'object') return false
  const { rs, listings } = result as { rs?: unknown; listings?: unknown }
  return Array.isArray(rs || listings)
}

export function clearListingCache(): void {
  listingCache.clear()
}

/** The tag cache (a hard-coded API Gateway dev stage, as it always was). */
const TAG_CACHE_URL = 'https://tbd4rmdvjk.execute-api.us-east-1.amazonaws.com/dev/listings'

export interface TagCacheOptions {
  keywords: string
  count: number
  signal?: AbortSignal
}

/**
 * The tag-cache request URL. Pure. The keywords ride the query string.
 * Throws URIError, as encodeURIComponent does, for keywords that hold a lone
 * UTF-16 surrogate (for example an emoji cut in half).
 */
export function buildTagCacheUrl(keywords: string, count: number): string {
  return `${TAG_CACHE_URL}?keywords=${encodeURIComponent(keywords)}&count=${count}&v=1`
}

/** The first `count` listings of a tag-cache body, or null when it is not an array. Pure. */
export function parseTagCacheResponse(data: unknown, count: number): SellwildListing[] | null {
  return Array.isArray(data) ? (data.slice(0, count) as SellwildListing[]) : null
}

/**
 * Fetches up to `count` listings for `keywords` from the tag cache. Never
 * rejects: empty keywords or a zero count ask nothing and give [], and every
 * failure gives [] too. Failures are reported once with logFailure:
 * listings.tag_cache_url.invalid (keywords that cannot be URL-encoded),
 * listings.tag_cache.network, .http, .parse and .invalid. A caller abort is
 * not a failure and is not reported. Only the host of the URL is ever sent,
 * never the keywords.
 */
export async function fetchTagCacheListings(
  options: TagCacheOptions
): Promise<SellwildListing[]> {
  const { keywords, count } = options
  if (!keywords || !count) return []

  let url: string
  try {
    url = buildTagCacheUrl(keywords, count)
  } catch (error) {
    // Only the error's name, and only the base URL's host: never the keywords.
    logFailure({ code: 'listings.tag_cache_url.invalid', component: 'listings', message: 'tag cache keywords cannot be URL-encoded', error: parseErrorName(error), url: TAG_CACHE_URL })
    return []
  }
  const aborted = () => options.signal?.aborted === true

  let res: Response
  try {
    res = await fetch(url, { signal: options.signal })
  } catch (error) {
    if (!aborted()) logFailure({ code: 'listings.tag_cache.network', component: 'listings', severity: 'warn', error, url })
    return []
  }
  // A non-2xx answer is reported here and only here, like fetchListings.
  if (!res.ok) {
    logFailure({ code: 'listings.tag_cache.http', component: 'listings', message: `HTTP ${res.status}`, httpStatus: res.status, url })
  }

  let data: unknown
  try {
    data = await res.json()
  } catch (error) {
    // Only the error's name is sent: its message quotes part of the body.
    if (res.ok && !aborted()) logFailure({ code: 'listings.tag_cache.parse', component: 'listings', message: 'tag cache body is not JSON', error: parseErrorName(error), url })
    return []
  }
  const listings = parseTagCacheResponse(data, count)
  if (listings === null) {
    if (res.ok) logFailure({ code: 'listings.tag_cache.invalid', component: 'listings', message: `tag cache JSON is ${jsonKind(data)}`, url })
    return []
  }
  return listings
}
