import { SellwildConfig, SellwildListingsResponse, SellwildListing, SdkEvent } from './types'
import { EVENTS_URL, DEFAULT_LISTINGS_URL } from './config'

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

export async function fetchListings(
  config: SellwildConfig,
  options: FetchOptions = {}
): Promise<SellwildListingsResponse> {
  const url = resolveListingsUrl(config)

  if (listingCache.has(url)) {
    return listingCache.get(url)!
  }

  const promise = fetch(url, {
    signal: options.signal,
    headers: options.headers,
  })
    .then(res => res.json())
    .then(data => {
      const result = data.result || data
      const listings: SellwildListing[] = result.rs || result.listings || []
      return {
        listings,
        config: result.config || {},
        widgetCacheVersionId: result.widgetCacheVersionId || '0',
      } as SellwildListingsResponse
    })
    .catch(err => {
      listingCache.delete(url)
      throw err
    })

  listingCache.set(url, promise)
  return promise
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

// Event analytics queue
class EventQueue {
  private events: Array<SdkEvent & { uid: string; createdTime: number }> = []
  private timer: ReturnType<typeof setTimeout> | null = null
  private readonly url = EVENTS_URL
  private readonly interval = 10000
  private readonly maxBatch = 100
  // Hard cap so a persistently-failing endpoint can't grow the queue unbounded.
  private readonly maxQueue = 1000
  private uid: string = ''
  // Kill switch. Defaults on; call setEnabled(config.eventsEnabled) after
  // configure() to honor the CMS EVENTS_ENABLED flag. When off, events are
  // neither queued nor sent (and any pending batch is dropped on flush).
  private enabled = true

  /** Toggle event sending. Pass `config.eventsEnabled` from a resolved config. */
  setEnabled(enabled: boolean): void {
    this.enabled = enabled
  }

  getUid(): string {
    if (this.uid) return this.uid
    try {
      this.uid = crypto.randomUUID()
    } catch {
      this.uid = Math.random().toString(36).slice(2)
    }
    return this.uid
  }

  push(event: SdkEvent): void {
    if (!this.enabled) return
    this.events.push({ ...event, uid: this.getUid(), createdTime: Date.now() })
    if (this.events.length > this.maxQueue) {
      this.events.splice(0, this.events.length - this.maxQueue) // drop oldest over the cap
    }
    this.schedule()
  }

  pushNow(event: SdkEvent): void {
    this.push(event)
    this.flush()
  }

  private schedule(): void {
    if (this.timer) return
    this.timer = setTimeout(() => this.flush(), this.interval)
  }

  flush(): void {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    if (!this.enabled) {
      this.events.length = 0
      return
    }
    const batch = this.events.splice(0, this.maxBatch)
    if (!batch.length) return

    fetch(this.url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(batch),
    }).catch(() => {
      // Re-queue on failure, capped, and reschedule so a transient outage
      // recovers without waiting for the next push() — and can't grow unbounded.
      this.events.unshift(...batch)
      if (this.events.length > this.maxQueue) {
        this.events.splice(0, this.events.length - this.maxQueue) // drop oldest over the cap
      }
      this.schedule()
    })
  }
}

export const eventQueue = new EventQueue()
