import { describe, expect, it, vi } from 'vitest'
import eventQueueSource from '../src/event-queue.ts?raw'
import { EVENTS_URL, SDK_VERSION } from '../src/config'
import {
  capQueue,
  createEventQueue,
  eventQueue,
  globalRandomUUID,
  requeueFailedBatch,
  resolveUid,
  stampEventAttributes,
  takeBatch,
  type EventQueueDeps,
} from '../src/event-queue'
import { getFailureInternalErrors, logFailure, setFailureContext } from '../src/failures'
import type { SdkEvent } from '../src/types'
import { sdkEvent, wireEvents } from './factories'
import { takeFailureEvents } from './support/failures'
import { validate } from './support/schemas'

// The events queue: batching, the kill switch, stamping, requeue, and
// contract A7 (transport never reports itself).

type FetchResult = 'ok' | 'reject' | number

// A queue with every dependency injected: fetch answers from `results` (the
// last one repeats), timers run only when the test says so.
function harness(results: FetchResult[] = ['ok'], extra: Partial<EventQueueDeps> = {}) {
  const timers: Array<{ id: number; callback: () => void; ms: number }> = []
  let nextId = 1
  let calls = 0
  const fetch = vi.fn(async (_url: string, _init: RequestInit) => {
    const r = results[Math.min(calls++, results.length - 1)]
    if (r === 'reject') throw new TypeError('Network request failed')
    return new Response(null, { status: r === 'ok' ? 204 : r })
  })
  const deps: Partial<EventQueueDeps> = {
    fetch,
    now: () => 1790000000000 + calls,
    setTimeout: vi.fn((callback: () => void, ms: number) => {
      const id = nextId++
      timers.push({ id, callback, ms })
      return id
    }),
    clearTimeout: vi.fn((id: unknown) => {
      const i = timers.findIndex((t) => t.id === id)
      if (i >= 0) timers.splice(i, 1)
    }),
    randomUUID: () => 'queue-uid',
    random: () => 0.5,
    url: 'https://events.invalid/queue',
    ...extra,
  }
  const queue = createEventQueue(deps)
  const bodies = () => fetch.mock.calls.map(([, init]) => JSON.parse(String(init.body)) as Sent[])
  const runTimers = () => {
    for (const t of timers.splice(0)) t.callback()
  }
  return { queue, fetch, deps, timers, bodies, runTimers }
}

type Sent = SdkEvent & { uid: string; createdTime: number }
const flat = (batches: Sent[][]): Sent[] => ([] as Sent[]).concat(...batches)

// Let rejected sends settle their .catch.
const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

// A minimal host event: the flutter-minimal fixture's click, numbered by
// label, with no attributes of its own (the queue stamps them).
const click = (n: number): SdkEvent => sdkEvent({ label: String(n), attributes: undefined }, 'flutter-minimal')

describe('createEventQueue', () => {
  it('builds its test events from the contract', () => {
    const check = validate('events-batch', wireEvents([click(1), click(2)]))
    expect(check.ok, check.text).toBe(true)
  })

  it('drops an event pushed while off, so turning it back on does not send it', () => {
    const h = harness()
    h.queue.setEnabled(false)
    h.queue.push(click(1))
    h.queue.setEnabled(true)
    h.queue.flush()
    expect(h.fetch).not.toHaveBeenCalled()
  })

  it('stamps sdkVersion, the platform and the partner code, and keeps the caller attributes', () => {
    const h = harness()
    h.queue.push({ event: 'adError', action: 'No fill', label: '43', attributes: { zone: 43 } })
    h.queue.setPlatform('react-native')
    h.queue.setPartnerCode('weatherbug')
    h.queue.push({ event: 'click', attributes: { code: 'caller' } })
    h.queue.push({ event: 'click' })
    h.queue.flush()

    expect(h.bodies()).toEqual([
      [
        { event: 'adError', action: 'No fill', label: '43', attributes: { zone: 43, sdkVersion: SDK_VERSION }, uid: 'queue-uid', createdTime: 1790000000000 },
        { event: 'click', attributes: { code: 'caller', type: 'react-native', sdkVersion: SDK_VERSION }, uid: 'queue-uid', createdTime: 1790000000000 },
        { event: 'click', attributes: { code: 'weatherbug', type: 'react-native', sdkVersion: SDK_VERSION }, uid: 'queue-uid', createdTime: 1790000000000 },
      ],
    ])
    expect(h.fetch.mock.calls[0][0]).toBe('https://events.invalid/queue')
    expect(h.fetch.mock.calls[0][1]).toMatchObject({ method: 'POST', headers: { 'Content-Type': 'application/json' } })
  })

  it('stops stamping the partner code when it is set to empty', () => {
    const h = harness()
    h.queue.setPartnerCode('weatherbug')
    h.queue.setPartnerCode('')
    h.queue.pushNow({ event: 'click' })
    expect(h.bodies()[0][0].attributes).toEqual({ sdkVersion: SDK_VERSION })
  })

  it('sends the batch 10 s after the first push, with one timer for all pushes', () => {
    const h = harness()
    h.queue.push(click(1))
    h.queue.push(click(2))

    expect(h.deps.setTimeout).toHaveBeenCalledOnce()
    expect(h.timers.map((t) => t.ms)).toEqual([10000])
    expect(h.fetch).not.toHaveBeenCalled()

    h.runTimers()

    expect(h.bodies().map((b) => b.map((e) => e.label))).toEqual([['1', '2']])
  })

  it('pushNow sends at once and cancels the pending timer', () => {
    const h = harness()
    h.queue.push(click(1))
    h.queue.pushNow(click(2))

    expect(h.deps.clearTimeout).toHaveBeenCalledWith(1)
    expect(h.timers).toEqual([])
    expect(h.bodies().map((b) => b.map((e) => e.label))).toEqual([['1', '2']])
  })

  it('sends at most 100 events per request', () => {
    const h = harness()
    for (let i = 0; i < 150; i++) h.queue.push(click(i))
    h.queue.flush()
    h.queue.flush()

    expect(h.bodies().map((b) => [b.length, b[0].label])).toEqual([
      [100, '0'],
      [50, '100'],
    ])
  })

  it('keeps at most 1000 events, dropping the oldest', () => {
    const h = harness()
    for (let i = 0; i < 1005; i++) h.queue.push(click(i))
    for (let i = 0; i < 10; i++) h.queue.flush()
    h.queue.flush()

    const sent = flat(h.bodies())
    expect(sent).toHaveLength(1000)
    expect(sent[0].label).toBe('5')
    expect(h.fetch).toHaveBeenCalledTimes(10)
  })

  it('does not send an empty batch', () => {
    const h = harness()
    h.queue.flush()
    expect(h.fetch).not.toHaveBeenCalled()
  })

  it('requeues a failed batch in front and sends it again on the next timer', async () => {
    const h = harness(['reject', 'ok'])
    h.queue.pushNow(click(1))
    await settle()
    h.queue.push(click(2))

    expect(h.timers).toHaveLength(1)
    h.runTimers()

    expect(h.bodies().map((b) => b.map((e) => e.label))).toEqual([['1'], ['1', '2']])
  })

  it('caps the queue when a requeued batch would overflow it', async () => {
    const h = harness(['reject', 'ok'])
    for (let i = 0; i < 1000; i++) h.queue.push(click(i))
    h.queue.flush() // sends 0..99, which fails
    for (let i = 1000; i < 1100; i++) h.queue.push(click(i))
    await settle() // 0..99 go back in front: 1100 events, the oldest 100 dropped
    for (let i = 0; i < 10; i++) h.queue.flush()

    const resent = flat(h.bodies().slice(1))
    expect(resent).toHaveLength(1000)
    expect(resent[0].label).toBe('100')
    expect(resent[resent.length - 1].label).toBe('1099')
  })

  it('treats a non-2xx answer as sent (the endpoint status is not checked)', async () => {
    const h = harness([500])
    h.queue.pushNow(click(1))
    await settle()
    h.queue.flush()
    expect(h.fetch).toHaveBeenCalledOnce()
    expect(h.timers).toEqual([])
  })

  it('drops everything while disabled and resumes when enabled again', () => {
    const h = harness()
    h.queue.push(click(1))
    h.queue.setEnabled(false)
    h.queue.push(click(2))
    h.queue.flush()
    expect(h.fetch).not.toHaveBeenCalled()

    h.queue.setEnabled(true)
    h.queue.flush()
    expect(h.fetch).not.toHaveBeenCalled()
    h.queue.pushNow(click(3))
    expect(h.bodies().map((b) => b.map((e) => e.label))).toEqual([['3']])
  })

  it('creates the uid once, and falls back to a random id without crypto.randomUUID', () => {
    const uuid = vi.fn(() => 'fixed-uuid')
    expect(harness(['ok'], { randomUUID: uuid }).queue.getUid()).toBe('fixed-uuid')

    const h = harness(['ok'], { randomUUID: () => { throw new ReferenceError('crypto is not defined') }, random: () => 0.123456789 })
    expect(h.queue.getUid()).toBe((0.123456789).toString(36).slice(2))
    expect(h.queue.getUid()).toBe(h.queue.getUid())

    const once = harness(['ok'], { randomUUID: uuid })
    once.queue.getUid()
    once.queue.getUid()
    expect(uuid).toHaveBeenCalledTimes(2) // one per queue above
  })

  it('posts batches the events-batch schema accepts', () => {
    const h = harness()
    h.queue.setPlatform('react-native')
    h.queue.setPartnerCode('weatherbug')
    h.queue.push(sdkEvent())
    h.queue.push(sdkEvent({}, 'web-winning-bid'))
    h.queue.flush()

    const check = validate('events-batch', h.bodies()[0])
    expect(check.ok, check.text).toBe(true)
  })
})

describe('createEventQueue defaults', () => {
  it('uses the global fetch, timers, clock and crypto, and EVENTS_URL', () => {
    vi.useFakeTimers({ now: 1790000000123 })
    const fetchMock = vi.fn(async (_url: string, _init: RequestInit) => new Response(null, { status: 204 }))
    vi.stubGlobal('fetch', fetchMock)
    const queue = createEventQueue()

    queue.push(click(1))
    vi.advanceTimersByTime(9999)
    expect(fetchMock).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1)

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(fetchMock.mock.calls[0][0]).toBe(EVENTS_URL)
    const [sent] = JSON.parse(String(fetchMock.mock.calls[0][1].body))
    expect(sent.createdTime).toBe(1790000000123)
    expect(sent.uid).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)

    queue.push(click(2))
    queue.flush()
    expect(vi.getTimerCount()).toBe(0)
  })

  it('falls back to Math.random when crypto is missing (Hermes)', () => {
    vi.stubGlobal('crypto', undefined)
    vi.spyOn(Math, 'random').mockReturnValue(0.25)
    expect(createEventQueue().getUid()).toBe((0.25).toString(36).slice(2))
  })

  it('falls back to Math.random when crypto has no randomUUID (older RN)', () => {
    vi.stubGlobal('crypto', {})
    vi.spyOn(Math, 'random').mockReturnValue(0.75)
    expect(createEventQueue().getUid()).toBe((0.75).toString(36).slice(2))
  })

  it('is what the package exports as eventQueue', async () => {
    const api = await import('../src/api')
    expect(api.eventQueue).toBe(eventQueue)
    expect(api.createEventQueue).toBe(createEventQueue)
  })
})

describe('transport never reports itself (contract A7)', () => {
  it('has no path to logFailure in its source', () => {
    const code = eventQueueSource.replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '')
    expect(code).not.toMatch(/logFailure|['"]\.\/failures/)
  })

  it('reports nothing when a send rejects, answers 500 or is disabled', async () => {
    setFailureContext({ partnerCode: 'weatherbug' })
    const h = harness(['reject', 500, 'reject'])

    h.queue.pushNow(click(1)) // rejects, requeued
    await settle()
    h.queue.pushNow(click(2)) // 1 and 2 answer 500
    await settle()
    h.queue.pushNow(click(3)) // rejects, requeued
    await settle()
    h.runTimers() // rejects again
    await settle()
    h.queue.setEnabled(false)
    h.queue.pushNow(click(4)) // dropped

    expect(h.fetch).toHaveBeenCalledTimes(4)
    expect(takeFailureEvents()).toEqual([])
    expect(getFailureInternalErrors()).toBe(0)
  })

  it('does not loop: a failure event whose send fails is requeued once, not reported again', async () => {
    const fetchMock = vi.fn(async (_url: string, _init: RequestInit): Promise<Response> => {
      throw new TypeError('Network request failed')
    })
    vi.stubGlobal('fetch', fetchMock)
    vi.useFakeTimers()
    setFailureContext({ sink: undefined, partnerCode: 'weatherbug' })

    logFailure({ code: 'listings.fetch.network', component: 'listings' })
    await vi.advanceTimersByTimeAsync(0)
    fetchMock.mockImplementation(async () => new Response(null, { status: 204 }))
    await vi.advanceTimersByTimeAsync(10000)

    const bodies = fetchMock.mock.calls.map(([, init]) => JSON.parse(String(init.body)) as SdkEvent[])
    expect(bodies.map((b) => b.map((e) => e.action))).toEqual([['listings.fetch.network'], ['listings.fetch.network']])
    expect(getFailureInternalErrors()).toBe(0)
  })
})

describe('stampEventAttributes', () => {
  it('puts the partner code first, the caller attributes next, then type and sdkVersion', () => {
    const stamp = { partnerCode: 'weatherbug', platform: 'react-native', sdkVersion: SDK_VERSION }
    expect(stampEventAttributes(sdkEvent({ attributes: { zone: 43 } }).attributes, stamp)).toEqual({
      code: 'weatherbug',
      zone: 43,
      type: 'react-native',
      sdkVersion: SDK_VERSION,
    })
    // A caller's own code wins; the SDK's type and sdkVersion always win.
    expect(stampEventAttributes({ code: 'caller', type: 'x', sdkVersion: '0' }, stamp)).toEqual({ code: 'caller', type: 'react-native', sdkVersion: SDK_VERSION })
  })

  it('leaves out an empty partner code and platform', () => {
    expect(stampEventAttributes(undefined, { partnerCode: '', platform: '', sdkVersion: '1.0.0' })).toEqual({ sdkVersion: '1.0.0' })
  })
})

describe('capQueue, takeBatch and requeueFailedBatch', () => {
  it('keeps the newest events up to the cap, as a new array', () => {
    const events = [1, 2, 3, 4]
    expect(capQueue(events, 2)).toEqual([3, 4])
    expect(capQueue(events, 4)).toEqual([1, 2, 3, 4])
    expect(capQueue(events, 9)).not.toBe(events)
    expect(capQueue(events, 0)).toEqual([])
    expect(events).toEqual([1, 2, 3, 4])
  })

  it('splits off the first batch and keeps the rest', () => {
    expect(takeBatch([1, 2, 3], 2)).toEqual({ batch: [1, 2], rest: [3] })
    expect(takeBatch([1], 2)).toEqual({ batch: [1], rest: [] })
    expect(takeBatch([], 2)).toEqual({ batch: [], rest: [] })
  })

  it('puts a failed batch back in front of newer events, dropping the oldest over the cap', () => {
    expect(requeueFailedBatch([3, 4], [1, 2], 10)).toEqual([1, 2, 3, 4])
    expect(requeueFailedBatch([3, 4], [1, 2], 3)).toEqual([2, 3, 4])
  })
})

describe('resolveUid', () => {
  it('uses randomUUID, and a base-36 id from random when it throws (Hermes has no crypto.randomUUID)', () => {
    const random = vi.fn(() => 0.5)
    expect(resolveUid(() => 'uuid-1', random)).toBe('uuid-1')
    expect(random).not.toHaveBeenCalled()
    expect(resolveUid(() => { throw new TypeError('crypto.randomUUID is not a function') }, () => 0.123456789)).toBe((0.123456789).toString(36).slice(2))
  })
})

// origin/main 37d432b (#82): getUid() reads crypto off globalThis with a
// guard, so no global `crypto` is assumed. It moved here with the queue.
describe('globalRandomUUID', () => {
  it('calls randomUUID on the crypto found on globalThis, on each call', () => {
    const fake = { randomUUID: vi.fn(function (this: unknown) { return this === fake ? 'global-uuid' : 'unbound' }) }
    vi.stubGlobal('crypto', fake)
    expect(globalRandomUUID()).toBe('global-uuid')
    vi.stubGlobal('crypto', { randomUUID: () => 'swapped-uuid' })
    expect(globalRandomUUID()).toBe('swapped-uuid')
    expect(fake.randomUUID).toHaveBeenCalledOnce()
  })

  it('works with the real Web Crypto (Node has it on globalThis)', () => {
    expect(globalRandomUUID()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
  })

  it('throws when there is no global crypto, or it has no randomUUID', () => {
    vi.stubGlobal('crypto', undefined)
    expect(() => globalRandomUUID()).toThrow('crypto.randomUUID unavailable')
    vi.stubGlobal('crypto', {})
    expect(() => globalRandomUUID()).toThrow('crypto.randomUUID unavailable')
  })

  it('is the default createEventQueue uses', () => {
    vi.stubGlobal('crypto', { randomUUID: () => 'default-dep-uuid' })
    expect(createEventQueue().getUid()).toBe('default-dep-uuid')
  })
})
