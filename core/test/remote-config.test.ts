import { beforeEach, describe, expect, it, vi } from 'vitest'
import accessDenied from '../../contracts/samples/app-config/realgm_realgm-realgm.403.xml?raw'
import { SDK_VERSION } from '../src/config'
import {
  clearRemoteConfigCache,
  fetchRemoteConfig,
  mapRemoteConfig,
  parseAdStack,
  resolveAdStack,
} from '../src/remote-config'
import { appConfig } from './factories'
import { takeFailureEvents } from './support/failures'

const CONFIG_URL = 'https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json'

type FetchImpl = (url: string, init: RequestInit) => Promise<Response>

function stubFetch(impl: FetchImpl) {
  const fetchMock = vi.fn(impl)
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

const json = (body: unknown, status = 200) => async () => new Response(JSON.stringify(body), { status })

// A fetch that only settles when its signal aborts, as a hung request does.
const hang: FetchImpl = (_url, init) =>
  new Promise((_resolve, reject) => {
    init.signal!.addEventListener('abort', () => reject(new DOMException('This operation was aborted', 'AbortError')))
  })

describe('mapRemoteConfig', () => {
  it('maps CONSTANT_CASE keys and keeps the raw payload on remote', () => {
    const raw = appConfig()
    const mapped = mapRemoteConfig(raw)

    expect(mapped).toMatchObject({
      partnerCode: 'weatherbug',
      slug: 'weatherbug-weatherbug',
      mobileZids: ['weatherbug-mobile-300x250'],
      adRefreshInterval: 30000,
      iabCats: ['IAB15'],
      adStack: 'prebidOnly',
      adStackByZone: { 43: 'gamOnly', 280: 'prebidOnly' },
    })
    // The sample has no EVENTS_ENABLED or FAILURES_*: they stay unset (defaults apply later).
    expect(mapped).not.toHaveProperty('eventsEnabled')
    expect(mapped).not.toHaveProperty('failuresEnabled')
    expect(mapped.remote).toBe(raw)
  })

  it('skips null, undefined and empty values and unknown keys', () => {
    expect(mapRemoteConfig({ TITLE: '', GAM: null, LINK_TEXT: undefined, NOT_A_KEY: 'x' })).toEqual({
      remote: { TITLE: '', GAM: null, LINK_TEXT: undefined, NOT_A_KEY: 'x' },
    })
  })

  it.each([
    [true, true], [false, false], [0, false], [1, true], [0.5, true],
    ['false', false], [' OFF ', false], ['No', false], ['0', false], ['yes', true], ['nope', true],
    [{}, true], [[], true],
    // ASCII trim only (FAILURES.md 5.3): a no-break space is not trimmed.
    ['\u00a0false', true],
  ])('coerces EVENTS_ENABLED and FAILURES_ENABLED %j to %j', (value, expected) => {
    expect(mapRemoteConfig({ EVENTS_ENABLED: value, FAILURES_ENABLED: value })).toMatchObject({
      eventsEnabled: expected,
      failuresEnabled: expected,
    })
  })

  it.each([
    [0.25, 0.25], ['0.5', 0.5], [' .5 ', 0.5], ['+1', 1], [5, 1], [-1, 0], ['50%', 1], [true, 1], [{}, 1], [Number.NaN, 1],
  ])('coerces FAILURES_SAMPLE_RATE %j to %j', (value, expected) => {
    expect(mapRemoteConfig({ FAILURES_SAMPLE_RATE: value }).failuresSampleRate).toBe(expected)
  })

  it('coerces IAB_CATS, AD_STACK and AD_STACK_BY_ZONE', () => {
    expect(mapRemoteConfig({ IAB_CATS: ['IAB1'] }).iabCats).toEqual(['IAB1'])
    expect(mapRemoteConfig({ IAB_CATS: 'IAB15, IAB15-10 ,,IAB7' }).iabCats).toEqual(['IAB15', 'IAB15-10', 'IAB7'])
    expect(mapRemoteConfig({ IAB_CATS: 15 }).iabCats).toEqual([])
    expect(mapRemoteConfig({ AD_STACK: 'GAM' }).adStack).toBe('gamOnly')
    expect(mapRemoteConfig({ AD_STACK: 'weird' }).adStack).toBeUndefined()
    expect(mapRemoteConfig({ AD_STACK_BY_ZONE: { 43: 'prebid', 44: 'nope' } }).adStackByZone).toEqual({ 43: 'prebidOnly' })
    expect(mapRemoteConfig({ AD_STACK_BY_ZONE: ['gam'] }).adStackByZone).toBeUndefined()
  })
})

describe('parseAdStack and resolveAdStack', () => {
  it.each([
    ['BOTH', 'both'], ['all', 'both'], ['default', 'both'],
    ['gam', 'gamOnly'], ['GAM_ONLY', 'gamOnly'], ['google', 'gamOnly'], ['gads', 'gamOnly'], ['Google Ads', 'gamOnly'],
    ['prebid', 'prebidOnly'], ['prebid-only', 'prebidOnly'], ['PrebidSDK', 'prebidOnly'],
    ['xyz', undefined], [42, undefined],
  ])('parses %j as %j', (value, expected) => {
    expect(parseAdStack(value)).toBe(expected)
  })

  it('lets the global stack win, then the zone, then both', () => {
    expect(resolveAdStack({ adStack: 'gamOnly', adStackByZone: { 43: 'prebidOnly' } }, 43)).toBe('gamOnly')
    expect(resolveAdStack({ adStackByZone: { 43: 'prebidOnly' } }, 43)).toBe('prebidOnly')
    expect(resolveAdStack({ adStackByZone: { 43: 'prebidOnly' } }, '44')).toBe('both')
    expect(resolveAdStack({ adStackByZone: { 43: 'prebidOnly' } }, null)).toBe('both')
    expect(resolveAdStack({})).toBe('both')
  })
})

describe('fetchRemoteConfig', () => {
  beforeEach(() => {
    clearRemoteConfigCache()
  })

  it('fetches the CDN config with the version beacon, maps it and caches it', async () => {
    const fetchMock = stubFetch(json(appConfig()))

    const first = await fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')
    const second = await fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(fetchMock.mock.calls[0][0]).toBe(CONFIG_URL)
    expect(fetchMock.mock.calls[0][1]).toMatchObject({ headers: { 'User-Agent': `SellwildSDK/${SDK_VERSION} (react-native)` } })
    expect(first).toMatchObject({ partnerCode: 'weatherbug', adStack: 'prebidOnly' })
    expect(second).toBe(first)

    clearRemoteConfigCache()
    await fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('uses baseUrl and leaves no timer behind', async () => {
    vi.useFakeTimers()
    const fetchMock = stubFetch(json(appConfig({}, 'minimal')))

    await fetchRemoteConfig('minimal', 'minimal', { baseUrl: 'https://cdn.invalid' })

    expect(fetchMock.mock.calls[0][0]).toBe('https://cdn.invalid/app/minimal/minimal.json')
    expect(vi.getTimerCount()).toBe(0)
  })

  it('reports a non-2xx answer (a missing config is S3 403 XML) and does not cache it', async () => {
    const fetchMock = stubFetch(async () => new Response(accessDenied, { status: 403, headers: { 'Content-Type': 'application/xml' } }))

    await expect(fetchRemoteConfig('realgm', 'realgm-realgm')).resolves.toEqual({})
    await expect(fetchRemoteConfig('realgm', 'realgm-realgm')).resolves.toEqual({})

    expect(fetchMock).toHaveBeenCalledTimes(2)
    // The second report is folded by the gate (same failure within a minute).
    expect(takeFailureEvents()).toMatchObject([
      {
        action: 'config.fetch.http',
        label: 'remoteConfig',
        attributes: { severity: 'error', msg: 'HTTP 403', httpStatus: '403', host: 'widget.sellwild.com' },
      },
    ])
  })

  it('reports a network error', async () => {
    stubFetch(async () => {
      throw new TypeError('Network request failed')
    })

    await expect(fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')).resolves.toEqual({})

    expect(takeFailureEvents()).toMatchObject([
      { action: 'config.fetch.network', attributes: { errName: 'TypeError', msg: 'Network request failed', host: 'widget.sellwild.com' } },
    ])
  })

  it('reports a timeout, not a network error, when the request hangs', async () => {
    vi.useFakeTimers()
    stubFetch(hang)

    const result = fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug', { timeout: 1500 })
    await vi.advanceTimersByTimeAsync(1500)

    await expect(result).resolves.toEqual({})
    expect(takeFailureEvents()).toMatchObject([
      { action: 'config.fetch.timeout', attributes: { msg: 'no answer in 1500 ms', host: 'widget.sellwild.com' } },
    ])
  })

  it('reports a timeout that fires while the body is read', async () => {
    vi.useFakeTimers()
    stubFetch(async (_url, init) => {
      const res = new Response('{}')
      vi.spyOn(res, 'json').mockImplementation(() => hang('', init))
      return res
    })

    const result = fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')
    await vi.advanceTimersByTimeAsync(5000)

    await expect(result).resolves.toEqual({})
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['config.fetch.timeout'])
  })

  it('does not report a caller abort', async () => {
    stubFetch(hang)
    const controller = new AbortController()

    const result = fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug', { signal: controller.signal })
    controller.abort()

    await expect(result).resolves.toEqual({})
    expect(takeFailureEvents()).toEqual([])
  })

  it('does not report a caller abort while the body is read', async () => {
    const controller = new AbortController()
    stubFetch(async () => {
      const res = new Response('{}')
      vi.spyOn(res, 'json').mockImplementation(async () => {
        controller.abort()
        throw new DOMException('This operation was aborted', 'AbortError')
      })
      return res
    })

    await expect(fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug', { signal: controller.signal })).resolves.toEqual({})
    expect(takeFailureEvents()).toEqual([])
  })

  it('reports a body that is not JSON', async () => {
    stubFetch(async () => new Response('<html>502 Bad Gateway</html>', { status: 200 }))

    await expect(fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')).resolves.toEqual({})

    expect(takeFailureEvents()).toMatchObject([{ action: 'config.fetch.parse', attributes: { errName: 'SyntaxError' } }])
  })

  it('reports JSON null and falls back to {} without caching, as before', async () => {
    const fetchMock = stubFetch(json(null))

    await expect(fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')).resolves.toEqual({})
    await fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')

    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(takeFailureEvents()).toMatchObject([{ action: 'config.parse.invalid', attributes: { msg: 'config JSON is null' } }])
  })

  it.each([
    [['a'], 'an array'],
    ['text', 'a string'],
    [7, 'a number'],
  ])('reports JSON %j that is not an object, and still maps it as before', async (body, kind) => {
    stubFetch(json(body))

    const result = await fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')

    expect(result).toEqual(mapRemoteConfig(body as unknown as Record<string, unknown>))
    expect(takeFailureEvents()).toMatchObject([{ action: 'config.parse.invalid', attributes: { msg: `config JSON is ${kind}` } }])
  })
})
