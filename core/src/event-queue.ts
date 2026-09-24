import type { SdkEvent } from './types'
import { EVENTS_URL, SDK_VERSION } from './config'

// Event analytics queue: batches SdkEvents and POSTs them to EVENTS_URL.
//
// Transport never reports itself (contracts/FAILURES.md 8.4, amendment A7):
// nothing in this file may call logFailure. A failure event would be queued
// for the same endpoint that just failed. test/event-queue.test.ts checks it.
//
// Import cycle: config → remote-config → failures → event-queue → config. So
// this module reads EVENTS_URL and SDK_VERSION when a method runs, never while
// it loads.

/**
 * What the queue needs from its host. createEventQueue fills every field left
 * out with the global of the same name, looked up on each call (so test
 * stubs and fake timers still apply), and `url` with EVENTS_URL.
 */
export interface EventQueueDeps {
  fetch: (url: string, init: RequestInit) => Promise<unknown>
  now: () => number
  setTimeout: (callback: () => void, ms: number) => unknown
  clearTimeout: (handle: unknown) => void
  randomUUID: () => string
  random: () => number
  url: string
}

type QueuedEvent = SdkEvent & { uid: string; createdTime: number }

export class EventQueue {
  private events: QueuedEvent[] = []
  private timer: unknown = null
  private readonly interval = 10000
  private readonly maxBatch = 100
  // Hard cap so a persistently-failing endpoint can't grow the queue unbounded.
  private readonly maxQueue = 1000
  private uid: string = ''
  // Kill switch. Defaults on; configure() calls setEnabled with the CMS
  // EVENTS_ENABLED flag. When off, events are neither queued nor sent (and any
  // pending batch is dropped on flush).
  private enabled = true
  // Host platform, stamped into every event's `attributes` bag for an
  // installed-base census. Empty until the host calls setPlatform(); when unset
  // the platform key is omitted (only sdkVersion is added).
  private platform = ''
  // Partner code, stamped as `attributes.code` when the event has none: the
  // events pipeline keys partners on it. Set by configure() before its fetch.
  private partnerCode = ''

  constructor(private readonly deps: Omit<EventQueueDeps, 'url'> & { url?: string }) {}

  /** Toggle event sending. Pass `config.eventsEnabled` from a resolved config. */
  setEnabled(enabled: boolean): void {
    this.enabled = enabled
  }

  /**
   * Set the host platform stamped into every event's `attributes` bag (e.g.
   * `'web'` or `'react-native'`). Call once at host startup — the web host
   * passes `'web'`, the RN host passes `'react-native'`.
   */
  setPlatform(platform: string): void {
    this.platform = platform
  }

  /** Set the partner code stamped as `attributes.code`. `''` stops stamping. */
  setPartnerCode(partnerCode: string): void {
    this.partnerCode = partnerCode
  }

  getUid(): string {
    if (this.uid) return this.uid
    try {
      this.uid = this.deps.randomUUID()
    } catch {
      // No crypto.randomUUID (Hermes): a non-RFC id still keys the session.
      this.uid = this.deps.random().toString(36).slice(2)
    }
    return this.uid
  }

  push(event: SdkEvent): void {
    if (!this.enabled) return
    // Stamp platform + sdkVersion into the free-form `attributes` passthrough
    // bag (queryable in BigQuery, no server change). `type` is the platform
    // discriminator the events view reads (JSON_EXTRACT(attributes,'type') →
    // the `type` column); `sdkVersion` is an installed-base census field. Both
    // are SDK-reserved, so they are applied last and always present. The
    // partner `code` goes first, so a caller's own code (logFailure's cleaned
    // one) wins.
    const attributes = {
      ...(this.partnerCode ? { code: this.partnerCode } : {}),
      ...event.attributes,
      ...(this.platform ? { type: this.platform } : {}),
      sdkVersion: SDK_VERSION,
    }
    this.events.push({ ...event, attributes, uid: this.getUid(), createdTime: this.deps.now() })
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
    if (this.timer !== null) return
    this.timer = this.deps.setTimeout(() => this.flush(), this.interval)
  }

  flush(): void {
    if (this.timer !== null) {
      this.deps.clearTimeout(this.timer)
      this.timer = null
    }
    if (!this.enabled) {
      this.events.length = 0
      return
    }
    const batch = this.events.splice(0, this.maxBatch)
    if (!batch.length) return

    this.deps.fetch(this.deps.url ?? EVENTS_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(batch),
    }).catch(() => {
      // Re-queue on failure, capped, and reschedule so a transient outage
      // recovers without waiting for the next push() — and can't grow unbounded.
      // Not reported: see the note at the top of this file.
      this.events.unshift(...batch)
      if (this.events.length > this.maxQueue) {
        this.events.splice(0, this.events.length - this.maxQueue) // drop oldest over the cap
      }
      this.schedule()
    })
  }
}

/**
 * Build an event queue. Every dependency left out uses the global of the same
 * name; `url` defaults to EVENTS_URL.
 */
export function createEventQueue(deps: Partial<EventQueueDeps> = {}): EventQueue {
  return new EventQueue({
    fetch: deps.fetch ?? ((url, init) => fetch(url, init)),
    now: deps.now ?? (() => Date.now()),
    setTimeout: deps.setTimeout ?? ((callback, ms) => setTimeout(callback, ms)),
    clearTimeout: deps.clearTimeout ?? ((handle) => clearTimeout(handle as ReturnType<typeof setTimeout>)),
    randomUUID: deps.randomUUID ?? (() => crypto.randomUUID()),
    random: deps.random ?? (() => Math.random()),
    url: deps.url,
  })
}

/** The SDK's shared queue. Hosts and logFailure push to it. */
export const eventQueue = createEventQueue()
