import React from 'react'
import { describe, expect, it, vi } from 'vitest'
import { act, create, type ReactTestRenderer } from 'react-test-renderer'
import type { SellwildConfig } from '@sellwild/sdk-core'
import { useSellwildListings, type UseSellwildListingsResult } from '../src/useSellwildListings'
import { listingsResponse, sellwildConfig } from './factories'
import { expectValid } from './support/schemas'
import { recordFailures, takeFailureEvents } from './support/failures'

recordFailures()

// The hook's listings come through core's fetchListings, which caches per URL
// for the whole file: each test uses its own URL.
let urls = 0
const configWithOwnUrl = (): SellwildConfig =>
  sellwildConfig({ listingsUrl: `https://cache.sellwild.com/listings-hook-${++urls}` })

interface Probe {
  tree: ReactTestRenderer
  /** The hook's latest result. */
  current(): UseSellwildListingsResult
  /** Every result the hook rendered, in order. */
  history: UseSellwildListingsResult[]
  rerender(config: SellwildConfig): Promise<void>
}

async function flush(): Promise<void> {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0))
  })
}

async function mount(config: SellwildConfig): Promise<Probe> {
  const history: UseSellwildListingsResult[] = []
  function HookProbe({ config: c }: { config: SellwildConfig }) {
    history.push(useSellwildListings(c))
    return null
  }
  let tree: ReactTestRenderer | undefined
  await act(async () => {
    tree = create(<HookProbe config={config} />)
  })
  return {
    tree: tree!,
    current: () => history[history.length - 1],
    history,
    rerender: async (next) => {
      await act(async () => tree!.update(<HookProbe config={next} />))
    },
  }
}

const okResponse = () => {
  const body = listingsResponse()
  expectValid('listings-response', body)
  return new Response(JSON.stringify(body), { status: 200 })
}

describe('useSellwildListings', () => {
  it('starts loading, then holds the listings and the cache config', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => okResponse()))
    const probe = await mount(configWithOwnUrl())
    await flush()

    expect(probe.history[0]).toMatchObject({ loading: true, listings: [], error: null, config: {} })
    const body = listingsResponse()
    expect(probe.current()).toMatchObject({ loading: false, error: null, config: body.result.config ?? {} })
    expect(probe.current().listings).toHaveLength(body.result.rs.length)

    act(() => probe.tree.unmount())
  })

  it('refresh() clears the cache and fetches again', async () => {
    const fetchMock = vi.fn(async () => okResponse())
    vi.stubGlobal('fetch', fetchMock)
    const probe = await mount(configWithOwnUrl())
    await flush()
    expect(fetchMock).toHaveBeenCalledOnce()

    const seen = probe.history.length
    await act(async () => probe.current().refresh())
    await flush()

    // Loading again while the second fetch runs.
    expect(probe.history.slice(seen).some((r) => r.loading)).toBe(true)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(probe.current()).toMatchObject({ loading: false, error: null })

    act(() => probe.tree.unmount())
  })

  it('fetches again when the listings URL changes, and not for another config change', async () => {
    const fetchMock = vi.fn(async () => okResponse())
    vi.stubGlobal('fetch', fetchMock)
    const config = configWithOwnUrl()
    const probe = await mount(config)
    await flush()

    await probe.rerender({ ...config, title: 'Deals' })
    await flush()
    expect(fetchMock).toHaveBeenCalledOnce()

    await probe.rerender(configWithOwnUrl())
    await flush()
    expect(fetchMock).toHaveBeenCalledTimes(2)

    act(() => probe.tree.unmount())
  })

  it('aborts the fetch on unmount and then touches no state, and nothing is reported', async () => {
    let signal: AbortSignal | undefined
    vi.stubGlobal(
      'fetch',
      vi.fn((_url: string, init: RequestInit) => {
        signal = init.signal ?? undefined
        // Like a real fetch: pending until the signal aborts it.
        return new Promise<Response>((_resolve, reject) => {
          signal!.addEventListener('abort', () => reject(new DOMException('The operation was aborted.', 'AbortError')))
        })
      }),
    )
    const probe = await mount(configWithOwnUrl())
    const before = probe.current()

    act(() => probe.tree.unmount())
    await flush()

    expect(signal?.aborted).toBe(true)
    expect(probe.current()).toBe(before)
    // A caller abort is no failure (core checks the signal).
    expect(takeFailureEvents()).toEqual([])
  })

  it('drops a response that arrives after unmount', async () => {
    let resolve: ((r: Response) => void) | undefined
    vi.stubGlobal('fetch', vi.fn(() => new Promise<Response>((r) => { resolve = r })))
    const probe = await mount(configWithOwnUrl())
    const before = probe.current()

    act(() => probe.tree.unmount())
    await act(async () => resolve!(okResponse()))
    await flush()

    expect(probe.current()).toBe(before)
  })

  it('ignores a request for the old URL that fails after the URL changed', async () => {
    let failOld: ((error: Error) => void) | undefined
    let answerNew: ((response: Response) => void) | undefined
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        // A fetch that does not stop when its signal aborts, then fails.
        .mockImplementationOnce(() => new Promise<Response>((_resolve, reject) => { failOld = reject }))
        .mockImplementationOnce(() => new Promise<Response>((resolve) => { answerNew = resolve })),
    )
    const probe = await mount(configWithOwnUrl())
    await probe.rerender(configWithOwnUrl())

    await act(async () => failOld!(new TypeError('Network request failed')))
    await flush()
    // The new request is still loading, with no error from the old one.
    expect(probe.current()).toMatchObject({ loading: true, error: null, listings: [] })

    await act(async () => answerNew!(okResponse()))
    await flush()
    expect(probe.current()).toMatchObject({ loading: false, error: null })
    expect(probe.current().listings).toHaveLength(listingsResponse().result.rs.length)
    // Core saw the old signal abort, so the old failure is no report.
    expect(takeFailureEvents()).toEqual([])

    act(() => probe.tree.unmount())
  })

  it('keeps error null for an AbortError it did not cause; core reports the failed request once', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => {
      throw new DOMException('The operation was aborted.', 'AbortError')
    }))
    const probe = await mount(configWithOwnUrl())
    await flush()

    expect(probe.current()).toMatchObject({ loading: false, error: null, listings: [] })
    expect(takeFailureEvents().map((e) => [e.action, e.attributes.errName])).toEqual([['listings.fetch.network', 'AbortError']])

    act(() => probe.tree.unmount())
  })
})
