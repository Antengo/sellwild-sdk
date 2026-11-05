// Log once, at the lowest layer that sees the failure (contracts/FAILURES.md
// 9). React Native wraps two lower layers: the native SDKs, which report
// their own failures (ad no-fill is not one; the native adError event covers
// it), and core, which reports listings and remote-config failures. So the
// errors those layers hand React Native reach the host callbacks and are not
// reported again here.

import React from 'react'
import { describe, expect, it, vi } from 'vitest'
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer'
import type { SellwildConfig } from '@sellwild/sdk-core'
import { SellwildBanner } from '../src/SellwildBanner'
import { SellwildFeed } from '../src/SellwildFeed'
import { useSellwildListings, type UseSellwildListingsResult } from '../src/useSellwildListings'
import { listingsResponse, sellwildConfig } from './factories'
import { expectValid } from './support/schemas'
import { recordFailures, takeFailureEvents } from './support/failures'

recordFailures()

function render(element: React.ReactElement): ReactTestRenderer {
  let tree: ReactTestRenderer | undefined
  act(() => {
    tree = create(element)
  })
  return tree!
}

function host(tree: ReactTestRenderer, type: string): ReactTestInstance {
  return tree.root.find((node) => node.type === type)
}

describe('native failures React Native passes on', () => {
  it('SellwildBanner hands onAdFailed to onError and reports nothing', () => {
    const onError = vi.fn()
    const tree = render(<SellwildBanner config={sellwildConfig()} size="300x250" zoneId={43} onError={onError} />)
    const banner = host(tree, 'SellwildBannerView')

    act(() => banner.props.onAdFailed({ nativeEvent: { message: 'No fill' } }))
    act(() => banner.props.onAdFailed({ nativeEvent: {} }))

    expect(onError.mock.calls).toEqual([[new Error('No fill')], [new Error('Ad failed')]])
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })

  it('SellwildFeed hands onFeedError to onError and reports nothing', () => {
    const onError = vi.fn()
    const tree = render(<SellwildFeed config={sellwildConfig()} onError={onError} />)
    const feed = host(tree, 'SellwildFeedView')

    act(() => feed.props.onFeedError({ nativeEvent: { message: 'listings fetch failed' } }))
    act(() => feed.props.onFeedError({ nativeEvent: {} }))

    expect(onError.mock.calls).toEqual([[new Error('listings fetch failed')], [new Error('Feed failed')]])
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })
})

describe('useSellwildListings over core fetchListings', () => {
  // Renders the hook and waits for the fetch to settle.
  async function settle(config: SellwildConfig): Promise<{ tree: ReactTestRenderer; result: UseSellwildListingsResult }> {
    let result: UseSellwildListingsResult | undefined
    function Probe() {
      result = useSellwildListings(config)
      return null
    }
    let tree: ReactTestRenderer | undefined
    await act(async () => {
      tree = create(<Probe />)
    })
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 0))
    })
    return { tree: tree!, result: result! }
  }

  it('surfaces a network failure that core reported, once', async () => {
    const fetchMock = vi.fn(async (): Promise<Response> => {
      throw new TypeError('Network request failed')
    })
    vi.stubGlobal('fetch', fetchMock)
    const config = sellwildConfig({ listingsUrl: 'https://cache.sellwild.com/listings-log-once-network' })

    const { tree, result } = await settle(config)

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(result).toMatchObject({ loading: false, listings: [], error: new TypeError('Network request failed') })
    const events = takeFailureEvents()
    expect(events.map((e) => [e.action, e.label])).toEqual([['listings.fetch.network', 'listings']])
    expect(events[0].attributes).toMatchObject({
      client: 'react-native',
      errName: 'TypeError',
      msg: 'Network request failed',
      host: 'cache.sellwild.com',
    })
    expectValid('client-failure-event', events[0], 'rn-listings-fetch-network')

    act(() => tree.unmount())
  })

  it('surfaces an HTTP error page as one report, not one per symptom', async () => {
    // S3's answer for a missing cache: 403 with an XML body, which also
    // fails to parse. Core reports the status only; the hook reports nothing.
    const xml = '<?xml version="1.0" encoding="UTF-8"?><Error><Code>AccessDenied</Code></Error>'
    vi.stubGlobal('fetch', vi.fn(async () => new Response(xml, { status: 403 })))
    const config = sellwildConfig({ listingsUrl: 'https://cache.sellwild.com/listings-log-once-http' })

    const { tree, result } = await settle(config)

    expect(result.loading).toBe(false)
    expect(result.error).toBeInstanceOf(SyntaxError)
    const events = takeFailureEvents()
    expect(events.map((e) => [e.action, e.attributes.httpStatus, e.attributes.client])).toEqual([
      ['listings.fetch.http', '403', 'react-native'],
    ])

    act(() => tree.unmount())
  })

  it('reports nothing when the fetch succeeds', async () => {
    const body = listingsResponse()
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify(body), { status: 200 })))
    const config = sellwildConfig({ listingsUrl: 'https://cache.sellwild.com/listings-log-once-ok' })

    const { tree, result } = await settle(config)

    expect(result).toMatchObject({ loading: false, error: null })
    expect(result.listings).toHaveLength(body.result.rs.length)
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })
})
