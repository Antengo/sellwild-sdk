import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  buildConfig,
  buildConfigWithRemote,
  configure,
  currencyToSymbol,
  getMainUrl,
  DEFAULT_LISTINGS_URL,
  EVENTS_URL,
} from '../src/config'
import { isDebugLogging } from '../src/debug-log'
import { eventQueue } from '../src/event-queue'
import { logFailure } from '../src/failures'
import { clearRemoteConfigCache } from '../src/remote-config'
import { resolveListingsUrl } from '../src/api'
import { appConfig } from './factories'
import { takeFailureEvents } from './support/failures'

type Call = [string, RequestInit]

// Answers the config URL with `config`, or fails it; records event POSTs.
function stubNetwork(config: unknown | Error) {
  const events: unknown[][] = []
  const fetchMock = vi.fn(async (url: string, init: RequestInit) => {
    if (url === EVENTS_URL) {
      events.push(JSON.parse(String(init.body)))
      return new Response(null, { status: 204 })
    }
    if (config instanceof Error) throw config
    return new Response(JSON.stringify(config))
  })
  vi.stubGlobal('fetch', fetchMock)
  return { fetchMock, events, configCalls: () => (fetchMock.mock.calls as Call[]).filter(([url]) => url !== EVENTS_URL) }
}

const probe = { code: 'listings.fetch.network', component: 'listings' } as const

describe('configure', () => {
  beforeEach(() => {
    clearRemoteConfigCache()
  })

  it('merges defaults, partner and slug, the remote config and overrides, in that order', async () => {
    stubNetwork(appConfig({ TITLE: 'From CDN', GAM: '/1/cdn' }))

    const config = await configure('weatherbug', 'weatherbug-weatherbug', { overrides: { gamTag: '/1/app', appBundleId: 'com.aws.android' } })

    expect(config).toMatchObject({
      partnerCode: 'weatherbug',
      slug: 'weatherbug-weatherbug',
      title: 'From CDN',
      gamTag: '/1/app',
      appBundleId: 'com.aws.android',
      linkText: 'View all',
      eventsEnabled: true,
      failuresEnabled: true,
      failuresSampleRate: 1,
    })
    expect(resolveListingsUrl(config)).toBe('https://cache.sellwild.com/listings-img-data-sm-avif-weatherbug')
  })

  it('attributes a failed config fetch to the partner, and reports it once', async () => {
    stubNetwork(new TypeError('Network request failed'))

    const config = await configure('newpartner', 'newpartner-main')

    expect(config).toMatchObject({ partnerCode: 'newpartner', slug: 'newpartner-main', listingsUrl: undefined })
    expect(resolveListingsUrl(config)).toBe(DEFAULT_LISTINGS_URL)
    expect(takeFailureEvents()).toMatchObject([{ action: 'config.fetch.network', attributes: { code: 'newpartner' } }])
  })

  it('stamps the partner on queued events before the fetch', async () => {
    const net = stubNetwork(appConfig())
    let codeDuringFetch: unknown
    net.fetchMock.mockImplementationOnce(async () => {
      eventQueue.pushNow({ event: 'probe' })
      codeDuringFetch = (net.events[0][0] as { attributes: { code: string } }).attributes.code
      return new Response(JSON.stringify(appConfig()))
    })

    await configure('weatherbug', 'weatherbug-weatherbug')

    expect(codeDuringFetch).toBe('weatherbug')
  })

  it('applies EVENTS_ENABLED to the events queue and the failure gate', async () => {
    const net = stubNetwork(appConfig({ EVENTS_ENABLED: 'false' }))

    const config = await configure('weatherbug', 'weatherbug-weatherbug')
    eventQueue.pushNow({ event: 'click' })
    logFailure(probe)

    expect(config.eventsEnabled).toBe(false)
    expect(net.events).toEqual([])
    expect(takeFailureEvents()).toEqual([])
  })

  it('applies FAILURES_ENABLED and FAILURES_SAMPLE_RATE to the failure gate only', async () => {
    const net = stubNetwork(appConfig({ FAILURES_ENABLED: 'off' }))
    await configure('weatherbug', 'weatherbug-weatherbug')
    logFailure(probe)
    eventQueue.pushNow({ event: 'click' })
    expect(takeFailureEvents()).toEqual([])
    expect(net.events).toHaveLength(1)

    clearRemoteConfigCache()
    stubNetwork(appConfig({ FAILURES_SAMPLE_RATE: 0 }))
    const config = await configure('weatherbug', 'weatherbug-weatherbug')
    logFailure(probe)
    expect(config).toMatchObject({ failuresEnabled: true, failuresSampleRate: 0 })
    expect(takeFailureEvents()).toEqual([])
  })

  it('lets local overrides win over the remote flags, and turns debug on from them', async () => {
    stubNetwork(appConfig({ FAILURES_ENABLED: false }))
    vi.spyOn(console, 'log').mockImplementation(() => undefined)

    await configure('weatherbug', 'weatherbug-weatherbug', { overrides: { failuresEnabled: true, debug: true } })
    logFailure(probe)

    expect(isDebugLogging()).toBe(true)
    expect(takeFailureEvents()).toHaveLength(1)
  })

  it('keeps events on when an override passes eventsEnabled: undefined', async () => {
    const net = stubNetwork(appConfig())

    await configure('weatherbug', 'weatherbug-weatherbug', { overrides: { eventsEnabled: undefined } })
    eventQueue.pushNow({ event: 'click' })

    expect(net.events).toHaveLength(1)
  })

  it('turns debug off again on a later configure without it', async () => {
    stubNetwork(appConfig())
    await configure('weatherbug', 'weatherbug-weatherbug', { overrides: { debug: true } })
    await configure('weatherbug', 'weatherbug-weatherbug')
    expect(isDebugLogging()).toBe(false)
  })
})

describe('buildConfigWithRemote', () => {
  beforeEach(() => {
    clearRemoteConfigCache()
  })

  it('merges defaults, the partial and the remote config, with remote last', async () => {
    const net = stubNetwork(appConfig({ TITLE: 'From CDN' }))

    const config = await buildConfigWithRemote({ partnerCode: 'weatherbug', title: 'Local', linkText: 'More' }, 'weatherbug-weatherbug', {
      baseUrl: 'https://cdn.invalid',
    })

    expect(net.configCalls()[0][0]).toBe('https://cdn.invalid/app/weatherbug/weatherbug-weatherbug.json')
    expect(config).toMatchObject({ partnerCode: 'weatherbug', title: 'From CDN', linkText: 'More', buyNowText: 'Buy now' })
  })

  it('attributes a failed fetch to the partner and applies the flags', async () => {
    stubNetwork(new TypeError('offline'))

    const config = await buildConfigWithRemote({ partnerCode: 'realgm', eventsEnabled: false }, 'realgm-realgm')
    logFailure(probe)

    expect(config.eventsEnabled).toBe(false)
    // The fetch failure was reported before the kill switch arrived; the probe after it was not.
    expect(takeFailureEvents()).toMatchObject([{ action: 'config.fetch.network', attributes: { code: 'realgm' } }])
  })
})

describe('buildConfig', () => {
  it('merges defaults and the partial without touching runtime state', () => {
    const net = stubNetwork(new Error('unused'))

    const config = buildConfig({ partnerCode: 'static', eventsEnabled: false, debug: true })
    eventQueue.pushNow({ event: 'click' })

    expect(config).toMatchObject({ partnerCode: 'static', eventsEnabled: false, debug: true, failuresEnabled: true, failuresSampleRate: 1, colors: ['#333333'] })
    expect(isDebugLogging()).toBe(false)
    expect(net.events).toHaveLength(1)
  })
})

describe('getMainUrl and currencyToSymbol', () => {
  it('builds the Sellwild URL with the partner and source', () => {
    expect(getMainUrl(buildConfig({ partnerCode: 'weather bug' }), 'sell', 'feed')).toBe(
      'https://sellwild.com/sell?p=weather+bug&utm_source=feed&utm_medium=widget',
    )
  })

  it('maps known currencies, passes others through, and defaults to $', () => {
    expect(['USD', 'EUR', 'GBP', 'CAD', 'AUD', 'JPY', ''].map(currencyToSymbol)).toEqual(['$', '€', '£', 'CA$', 'A$', 'JPY', '$'])
  })
})
