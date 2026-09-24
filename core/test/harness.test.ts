import { beforeEach, describe, expect, it, vi } from 'vitest'
// A real CDN response, captured read-only (contracts/samples/SOURCES.json).
import appConfigSample from '../../contracts/samples/app-config/antengo_antengo-sellwild-tv.json'
import * as core from '../src/index'
import { takeFailureEvents } from './support/failures'
import { takeBlockedNetworkCalls } from './setup'

describe('package index', () => {
  it('exports the runtime API that hosts and the React Native package use', () => {
    const functions = [
      'configure',
      'buildConfig',
      'buildConfigWithRemote',
      'mapRemoteConfig',
      'fetchRemoteConfig',
      'clearRemoteConfigCache',
      'fetchListings',
      'clearListingCache',
      'fetchTagCacheListings',
      'resolveListingsUrl',
      'resolveAdStack',
      'getAdPlacements',
      'buildPrebidAdUnit',
      'currencyToSymbol',
      'resolveGrowthCode',
      'resolveLocalizedListings',
      'logFailure',
      'setFailureContext',
      'resetFailuresForTests',
      'getFailureInternalErrors',
      'createEventQueue',
      'debugLog',
      'setDebugLogging',
      'isDebugLogging',
    ] as const
    for (const name of functions) {
      expect(core[name], name).toBeTypeOf('function')
    }
    expect(core.eventQueue).toMatchObject({
      push: expect.any(Function),
      pushNow: expect.any(Function),
      flush: expect.any(Function),
      setEnabled: expect.any(Function),
      setPlatform: expect.any(Function),
      setPartnerCode: expect.any(Function),
    })
    expect(core.FAILURE_CODES).toContain('config.fetch.network')
    expect(core.WIDGET_BASE_URL).toBe('https://widget.sellwild.com')
    expect(core.EVENTS_URL).toBe('https://events.sellwild.com/events/queue')
    expect(core.SDK_VERSION).toMatch(/^\d+\.\d+\.\d+$/)
  })
})

describe('network block (contract A8)', () => {
  // Every probe below uses a reserved .invalid host (RFC 2606), never a
  // Sellwild one. If the blocker ever breaks, the probes fail to resolve
  // instead of sending real requests to production.
  const PROBE = 'https://blocked.invalid/events/queue'

  // fetchRemoteConfig caches by slug, so each test starts with an empty cache.
  beforeEach(() => {
    core.clearRemoteConfigCache()
  })

  it('makes fetch reject and records the call', async () => {
    await expect(fetch(PROBE)).rejects.toThrow(`network blocked in tests: ${PROBE}`)
    await expect(fetch(new URL('https://blocked.invalid/x'))).rejects.toThrow(
      'network blocked in tests: https://blocked.invalid/x',
    )
    expect(takeBlockedNetworkCalls()).toEqual([`fetch ${PROBE}`, 'fetch https://blocked.invalid/x'])
  })

  it('fails fetch the way a real network error does, so a caller\'s .catch runs', async () => {
    let request: Promise<unknown> | undefined
    expect(() => {
      request = fetch(PROBE, { method: 'POST' })
    }).not.toThrow()

    const caught = await request!.catch((error: Error) => error.message)

    expect(caught).toBe(`network blocked in tests: ${PROBE}`)
    expect(takeBlockedNetworkCalls()).toEqual([`fetch ${PROBE}`])
  })

  it('blocks XMLHttpRequest and WebSocket too', () => {
    const xhr = new XMLHttpRequest()
    expect(() => xhr.open('POST', PROBE)).toThrow(`network blocked in tests: ${PROBE}`)
    expect(() => new WebSocket('wss://blocked.invalid/socket')).toThrow(
      'network blocked in tests: wss://blocked.invalid/socket',
    )
    expect(takeBlockedNetworkCalls()).toEqual([
      `XMLHttpRequest ${PROBE}`,
      'WebSocket wss://blocked.invalid/socket',
    ])
  })

  it('records a blocked call even when source code catches the error', async () => {
    // fetchRemoteConfig catches every fetch error and returns {}, so only
    // the record shows that it tried the CDN. The URL comes from source, so
    // it is a Sellwild host. Check the blocker first, so a broken blocker
    // fails here instead of letting the source call out.
    await expect(fetch(PROBE)).rejects.toThrow(`network blocked in tests: ${PROBE}`)
    await expect(core.fetchRemoteConfig('harness', 'harness-app')).resolves.toEqual({})
    expect(takeBlockedNetworkCalls()).toEqual([
      `fetch ${PROBE}`,
      'fetch https://widget.sellwild.com/app/harness/harness-app.json',
    ])
    // It reports the failure to the test recorder (setup.ts), not to the
    // events endpoint: that would have been a third blocked call.
    expect(takeFailureEvents()).toMatchObject([
      { action: 'config.fetch.network', label: 'remoteConfig', attributes: { host: 'widget.sellwild.com' } },
    ])
  })

  it('lets a test install its own fetch', async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify(appConfigSample)))
    vi.stubGlobal('fetch', fetchMock)

    const remote = await core.fetchRemoteConfig('antengo', 'antengo-sellwild-tv')

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(fetchMock.mock.calls[0]).toEqual([
      'https://widget.sellwild.com/app/antengo/antengo-sellwild-tv.json',
      expect.objectContaining({ headers: { 'User-Agent': `SellwildSDK/${core.SDK_VERSION} (react-native)` } }),
    ])
    expect(remote.remote).toEqual(appConfigSample)
    expect(takeBlockedNetworkCalls()).toEqual([])
  })

  it('puts the blocker back after a test stubs fetch', async () => {
    await expect(fetch(PROBE)).rejects.toThrow('network blocked in tests')
    expect(takeBlockedNetworkCalls()).toEqual([`fetch ${PROBE}`])
  })

  // These two run in order. vi.unstubAllGlobals only undoes vi.stubGlobal,
  // so a plain assignment stays until setup's afterEach reinstalls the
  // blocker.
  it('lets a test assign fetch directly', async () => {
    globalThis.fetch = async () => new Response('assigned')

    await expect(fetch(PROBE).then((r) => r.text())).resolves.toBe('assigned')
  })

  it('puts the blocker back after a test assigns fetch directly', async () => {
    await expect(fetch(PROBE)).rejects.toThrow(`network blocked in tests: ${PROBE}`)
    expect(takeBlockedNetworkCalls()).toEqual([`fetch ${PROBE}`])
  })
})
