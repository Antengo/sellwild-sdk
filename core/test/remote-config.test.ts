import { beforeEach, describe, expect, it, vi } from 'vitest'
import accessDenied from '../../contracts/samples/app-config/realgm_realgm-realgm.403.xml?raw'
import { configure, SDK_VERSION } from '../src/config'
import { logFailure, setFailureContext } from '../src/failures'
import {
  buildRemoteConfigUrl,
  classifyFetchError,
  clearRemoteConfigCache,
  fetchRemoteConfig,
  fetchRemoteConfigWithIssues,
  mapRemoteConfig,
  mapRemoteConfigWithIssues,
  parseAdStack,
  remoteConfigHeaders,
  resolveAdStack,
} from '../src/remote-config'
import { appConfig, appConfigVariants, type AppConfigPayload } from './factories'
import { expectInvalid, expectValid } from './support/factory-checks'
import { countLogFailureCalls, takeFailureEvents, takeRecordedFailures } from './support/failures'

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

// A CMS value core has to ignore or coerce: the minimal fixture plus one
// override. `schema` says whether the app-config contract allows it (the CMS
// can ship it) or rejects it (at which key).
function cmsConfig(overrides: Partial<AppConfigPayload>, schema: 'valid' | { invalidAt: string }): AppConfigPayload {
  const raw = appConfig(overrides, 'minimal')
  if (schema === 'valid') expectValid('app-config', raw)
  else expectInvalid('app-config', raw, { instancePath: schema.invalidAt })
  return raw
}

describe('mapRemoteConfigWithIssues', () => {
  it('finds nothing wrong in the real samples and valid fixtures but one, and maps as mapRemoteConfig does', () => {
    for (const name of Object.keys(appConfigVariants)) {
      const raw = appConfig({}, name)
      const { config, issues } = mapRemoteConfigWithIssues(raw)
      // by-zone-maps-objects carries AD_STACK_BY_ZONE 999: 'bogus' on purpose.
      const expected =
        name === 'by-zone-maps-objects'
          ? [{ code: 'config.adstack.invalid', component: 'remoteConfig', severity: 'warn', message: 'AD_STACK_BY_ZONE has 1 of 3 zones with an unknown mode, dropped' }]
          : []
      expect(issues, name).toEqual(expected)
      expect(config, name).toEqual(mapRemoteConfig(raw))
    }
  })

  it.each([
    [{ EVENTS_ENABLED: {} as never }, { invalidAt: '/EVENTS_ENABLED' }, 'config.field.invalid', 'EVENTS_ENABLED is an object, read as on'],
    [{ FAILURES_ENABLED: [] as never }, { invalidAt: '/FAILURES_ENABLED' }, 'config.field.invalid', 'FAILURES_ENABLED is an array, read as on'],
    [{ FAILURES_SAMPLE_RATE: '50%' }, 'valid', 'config.field.invalid', 'FAILURES_SAMPLE_RATE is not a number or decimal text, read as 1'],
    [{ FAILURES_SAMPLE_RATE: true as never }, { invalidAt: '/FAILURES_SAMPLE_RATE' }, 'config.field.invalid', 'FAILURES_SAMPLE_RATE is not a number or decimal text, read as 1'],
    [{ IAB_CATS: 15 as never }, { invalidAt: '/IAB_CATS' }, 'config.field.invalid', 'IAB_CATS is a number, read as []'],
    [{ AD_STACK: 'weird' }, 'valid', 'config.adstack.invalid', 'AD_STACK is not a known mode, read as unset'],
    [{ AD_STACK: 42 as never }, { invalidAt: '/AD_STACK' }, 'config.adstack.invalid', 'AD_STACK is a number, read as unset'],
    [{ AD_STACK_BY_ZONE: { 43: 'prebid', 44: 'nope', 45: true } as never }, 'valid', 'config.adstack.invalid', 'AD_STACK_BY_ZONE has 2 of 3 zones with an unknown mode, dropped'],
    [{ AD_STACK_BY_ZONE: ['gam'] as never }, { invalidAt: '/AD_STACK_BY_ZONE' }, 'config.adstack.invalid', 'AD_STACK_BY_ZONE is an array, not a map, read as unset'],
    [{ AD_STACK_BY_ZONE: 'gam' as never }, { invalidAt: '/AD_STACK_BY_ZONE' }, 'config.adstack.invalid', 'AD_STACK_BY_ZONE is a string, not a map, read as unset'],
    [{ AD_STACK_BY_ZONE: false as never }, { invalidAt: '/AD_STACK_BY_ZONE' }, 'config.adstack.invalid', 'AD_STACK_BY_ZONE is a boolean, not a map, read as unset'],
  ] as const)('reports %j once', (overrides, schema, code, message) => {
    const raw = cmsConfig(overrides, schema)

    const { config, issues } = mapRemoteConfigWithIssues(raw)

    expect(issues).toEqual([{ code, component: 'remoteConfig', severity: 'warn', message }])
    // The value is read exactly as mapRemoteConfig always read it.
    expect(config).toEqual(mapRemoteConfig(raw))
  })

  it.each([
    [{ FAILURES_SAMPLE_RATE: ' .5 ' }], [{ EVENTS_ENABLED: 'nope' }], [{ IAB_CATS: '' }],
    [{ AD_STACK: '' }], [{ AD_STACK_BY_ZONE: {} }], [{ AD_STACK_BY_ZONE: '' as const }],
  ])('reads %j as sent (or as unset) without an issue', (overrides) => {
    expect(mapRemoteConfigWithIssues(cmsConfig(overrides, 'valid')).issues).toEqual([])
  })

  // The contract allows any number and says the client clamps it. Below 0
  // reads as 0, which would sample out a report of it anyway.
  it.each([
    [2, 1], [-3, 0],
  ])('clamps FAILURES_SAMPLE_RATE %j to %j without an issue', (rate, clamped) => {
    const { config, issues } = mapRemoteConfigWithIssues(cmsConfig({ FAILURES_SAMPLE_RATE: rate }, 'valid'))
    expect(config.failuresSampleRate).toBe(clamped)
    expect(issues).toEqual([])
  })

  it('reports each bad key once, in payload order', () => {
    const raw = cmsConfig({ AD_STACK: 'weird', IAB_CATS: 15 as never }, { invalidAt: '/IAB_CATS' })
    expect(mapRemoteConfigWithIssues(raw).issues.map((i) => i.message)).toEqual([
      'AD_STACK is not a known mode, read as unset',
      'IAB_CATS is a number, read as []',
    ])
  })
})

describe('buildRemoteConfigUrl and remoteConfigHeaders', () => {
  it('puts partner and slug under /app', () => {
    expect(buildRemoteConfigUrl('https://widget.sellwild.com', 'weatherbug', 'weatherbug-weatherbug')).toBe(CONFIG_URL)
  })

  it('sends the version beacon User-Agent', () => {
    expect(remoteConfigHeaders('9.8.7')).toEqual({ 'User-Agent': 'SellwildSDK/9.8.7 (react-native)' })
  })
})

describe('classifyFetchError', () => {
  it('reports the timeout when it fired, nothing for a caller abort, else the code', () => {
    expect(classifyFetchError('config.fetch.network', true, true)).toBe('config.fetch.timeout')
    expect(classifyFetchError('config.fetch.parse', true, false)).toBe('config.fetch.timeout')
    expect(classifyFetchError('config.fetch.network', false, true)).toBeNull()
    expect(classifyFetchError('config.fetch.network', false, false)).toBe('config.fetch.network')
    expect(classifyFetchError('config.fetch.parse', false, false)).toBe('config.fetch.parse')
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

    const first = await countLogFailureCalls(async () => {
      await expect(fetchRemoteConfig('realgm', 'realgm-realgm')).resolves.toEqual({})
    })
    const second = await countLogFailureCalls(async () => {
      await expect(fetchRemoteConfig('realgm', 'realgm-realgm')).resolves.toEqual({})
    })

    expect(first).toEqual({ 'config.fetch.http': 1 })
    expect(second).toEqual({ 'config.fetch.http': 1 })
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

  it.each([500, 503])('reports a %i answer once, does not read its body and does not cache it', async (status) => {
    // A config body a server error must not be taken from.
    const body = appConfig()
    expectValid('app-config', body)
    const fetchMock = stubFetch(json(body, status))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')).resolves.toEqual({})
    })

    expect(calls).toEqual({ 'config.fetch.http': 1 })
    expect(takeFailureEvents()).toMatchObject([
      {
        action: 'config.fetch.http',
        label: 'remoteConfig',
        attributes: { severity: 'error', msg: `HTTP ${status}`, httpStatus: String(status), host: 'widget.sellwild.com' },
      },
    ])
    await fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('reports a network error once', async () => {
    stubFetch(async () => {
      throw new TypeError('Network request failed')
    })

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')).resolves.toEqual({})
    })

    expect(calls).toEqual({ 'config.fetch.network': 1 })
    expect(takeFailureEvents()).toMatchObject([
      { action: 'config.fetch.network', attributes: { errName: 'TypeError', msg: 'Network request failed', host: 'widget.sellwild.com' } },
    ])
  })

  it('reports a timeout once, not a network error, when the request hangs', async () => {
    vi.useFakeTimers()
    stubFetch(hang)

    const calls = await countLogFailureCalls(async () => {
      const result = fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug', { timeout: 1500 })
      await vi.advanceTimersByTimeAsync(1500)
      await expect(result).resolves.toEqual({})
    })

    expect(calls).toEqual({ 'config.fetch.timeout': 1 })
    expect(takeFailureEvents()).toMatchObject([
      { action: 'config.fetch.timeout', attributes: { msg: 'no answer in 1500 ms', host: 'widget.sellwild.com' } },
    ])
  })

  it('reports a timeout that fires while the body is read, once', async () => {
    vi.useFakeTimers()
    stubFetch(async (_url, init) => {
      const res = new Response('{}')
      vi.spyOn(res, 'json').mockImplementation(() => hang('', init))
      return res
    })

    const calls = await countLogFailureCalls(async () => {
      const result = fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')
      await vi.advanceTimersByTimeAsync(5000)
      await expect(result).resolves.toEqual({})
    })

    expect(calls).toEqual({ 'config.fetch.timeout': 1 })
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

  it('reports a body that is not JSON once, by the error name only', async () => {
    stubFetch(async () => new Response('<html>502 Bad Gateway</html>', { status: 200 }))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')).resolves.toEqual({})
    })

    expect(calls).toEqual({ 'config.fetch.parse': 1 })
    const [event] = takeFailureEvents()
    expect(event).toMatchObject({ action: 'config.fetch.parse', attributes: { errName: 'SyntaxError', msg: 'config body is not JSON', host: 'widget.sellwild.com' } })
    // FAILURES.md 7.6: V8 quotes the start of the body; none of it is sent.
    expect(JSON.stringify(event)).not.toMatch(/html|Bad Gateway/)
  })

  it('reports JSON null and falls back to {} without caching, as before', async () => {
    const fetchMock = stubFetch(json(null))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')).resolves.toEqual({})
    })
    await fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')

    expect(calls).toEqual({ 'config.parse.invalid': 1 })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(takeFailureEvents()).toMatchObject([{ action: 'config.parse.invalid', attributes: { msg: 'config JSON is null' } }])
  })

  it('reports each CMS value it had to ignore or coerce once, with the config host, and caches the result', async () => {
    const raw = cmsConfig({ AD_STACK: 'weird', EVENTS_ENABLED: {} as never }, { invalidAt: '/EVENTS_ENABLED' })
    const fetchMock = stubFetch(json(raw))

    let first = {}
    let second = {}
    const calls = await countLogFailureCalls(async () => {
      first = await fetchRemoteConfig('minimal', 'minimal')
      second = await fetchRemoteConfig('minimal', 'minimal')
    })

    expect(second).toBe(first)
    expect(first).toMatchObject({ adStack: undefined, eventsEnabled: true })
    expect(fetchMock).toHaveBeenCalledOnce()
    expect(calls).toEqual({ 'config.adstack.invalid': 1, 'config.field.invalid': 1 })
    expect(takeRecordedFailures()).toMatchObject([
      {
        event: {
          action: 'config.adstack.invalid',
          label: 'remoteConfig',
          attributes: { severity: 'warn', msg: 'AD_STACK is not a known mode, read as unset', host: 'widget.sellwild.com', seq: '1' },
        },
        flushed: true,
      },
      {
        event: {
          action: 'config.field.invalid',
          attributes: { severity: 'warn', msg: 'EVENTS_ENABLED is an object, read as on', host: 'widget.sellwild.com', seq: '2' },
        },
        flushed: false,
      },
    ])
  })

  it.each([
    [['a'], 'an array'],
    ['text', 'a string'],
    [7, 'a number'],
  ])('reports JSON %j that is not an object, and still maps it as before', async (body, kind) => {
    stubFetch(json(body))

    let result = {}
    const calls = await countLogFailureCalls(async () => {
      result = await fetchRemoteConfig('weatherbug', 'weatherbug-weatherbug')
    })

    expect(result).toEqual(mapRemoteConfig(body as unknown as Record<string, unknown>))
    expect(calls).toEqual({ 'config.parse.invalid': 1 })
    expect(takeFailureEvents()).toMatchObject([{ action: 'config.parse.invalid', attributes: { msg: `config JSON is ${kind}` } }])
  })

  // FAILURES.md 10.1: a config that turns events or failures off (or samples
  // every session out) sends no report about its own values.
  it.each([
    [{ EVENTS_ENABLED: false }],
    [{ FAILURES_ENABLED: 'off' }],
    [{ FAILURES_SAMPLE_RATE: 0 }],
  ])('reports nothing about its values when the config sets %j, and leaves later reports alone', async (flag) => {
    stubFetch(json(cmsConfig({ ...flag, AD_STACK: 'weird' }, 'valid')))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchRemoteConfig('minimal', 'minimal')).resolves.toMatchObject({ adStack: undefined })
    })
    logFailure({ code: 'listings.fetch.network', component: 'listings' })

    // The issue was still handed to logFailure, once, and dropped by the gate.
    expect(calls).toEqual({ 'config.adstack.invalid': 1 })
    // The fetched config's switch applied to its own report only.
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.fetch.network'])
  })

  // FAILURES.md 3.2 item 3: a local failuresEnabled override wins over the
  // remote value, and a standalone fetch of the same config does not undo it.
  it('keeps a host override that turned failures on, even when a fetched config turns them off', async () => {
    stubFetch(json(cmsConfig({ FAILURES_ENABLED: false }, 'valid')))
    await configure('minimal', 'minimal', { overrides: { failuresEnabled: true } })
    clearRemoteConfigCache()
    stubFetch(json(cmsConfig({ FAILURES_ENABLED: false, AD_STACK: 'weird' }, 'valid')))

    const calls = await countLogFailureCalls(() => fetchRemoteConfig('minimal', 'minimal'))
    logFailure({ code: 'listings.fetch.http', component: 'listings' })

    expect(calls).toEqual({ 'config.adstack.invalid': 1 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.fetch.http'])
  })

  // FAILURES.md 10.1: the active config's kill switch holds, for the fetched
  // config's own reports and for every later one.
  it.each([
    ['FAILURES_ENABLED', { FAILURES_ENABLED: false }, { FAILURES_ENABLED: true }],
    ['EVENTS_ENABLED', { EVENTS_ENABLED: 'off' }, { EVENTS_ENABLED: 'on' }],
    ['FAILURES_SAMPLE_RATE', { FAILURES_SAMPLE_RATE: 0 }, { FAILURES_SAMPLE_RATE: 1 }],
  ] as const)('keeps the active config\'s %s off when a fetched config turns it on', async (_key, active, fetched) => {
    stubFetch(json(cmsConfig(active, 'valid')))
    await configure('minimal', 'minimal')
    stubFetch(json(cmsConfig({ ...fetched, AD_STACK: 'weird' }, 'valid')))

    const calls = await countLogFailureCalls(() => fetchRemoteConfig('minimal', 'other-slug'))
    logFailure({ code: 'listings.fetch.http', component: 'listings' })

    expect(calls).toEqual({ 'config.adstack.invalid': 1 })
    expect(takeFailureEvents()).toEqual([])
  })

  it('keeps a flag the config does not set, such as failures already turned off', async () => {
    setFailureContext({ failuresEnabled: false })
    stubFetch(json(cmsConfig({ AD_STACK: 'weird' }, 'valid')))

    await fetchRemoteConfig('minimal', 'minimal')
    logFailure({ code: 'listings.fetch.http', component: 'listings' })

    expect(takeFailureEvents()).toEqual([])
  })

  it('reports its values at the lower of the two sample rates', async () => {
    // fnv1a32('uid-d:failures') / 2^32 is about 0.519 (contracts golden unit table).
    setFailureContext({ uid: () => 'uid-d', failuresSampleRate: 0.6 })
    stubFetch(json(cmsConfig({ FAILURES_SAMPLE_RATE: 0.5, AD_STACK: 'weird' }, 'valid')))
    await fetchRemoteConfig('minimal', 'minimal')
    expect(takeFailureEvents()).toEqual([])

    setFailureContext({ failuresSampleRate: 0.5 })
    stubFetch(json(cmsConfig({ FAILURES_SAMPLE_RATE: 0.6, AD_STACK: 'weird' }, 'valid')))
    await fetchRemoteConfig('minimal', 'rate-0.6')
    expect(takeFailureEvents()).toEqual([])

    setFailureContext({ failuresSampleRate: 0.6 })
    await fetchRemoteConfig('minimal', 'rate-0.6-again')
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['config.adstack.invalid'])
  })

  it('leaves the failure context alone when a config has nothing to report', async () => {
    stubFetch(json(cmsConfig({ FAILURES_ENABLED: false }, 'valid')))

    await fetchRemoteConfig('minimal', 'minimal')
    logFailure({ code: 'listings.fetch.network', component: 'listings' })

    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.fetch.network'])
  })
})

describe('fetchRemoteConfigWithIssues', () => {
  beforeEach(() => {
    clearRemoteConfigCache()
  })

  it('returns the value issues with the config URL instead of reporting them, and none from the cache', async () => {
    const raw = cmsConfig({ AD_STACK: 'weird' }, 'valid')
    const fetchMock = stubFetch(json(raw))

    const first = await fetchRemoteConfigWithIssues('minimal', 'minimal')
    const second = await fetchRemoteConfigWithIssues('minimal', 'minimal')

    expect(first).toEqual({
      config: mapRemoteConfig(raw),
      issues: [
        {
          code: 'config.adstack.invalid',
          component: 'remoteConfig',
          severity: 'warn',
          message: 'AD_STACK is not a known mode, read as unset',
          url: 'https://widget.sellwild.com/app/minimal/minimal.json',
        },
      ],
    })
    expect(second.config).toBe(first.config)
    expect(second.issues).toEqual([])
    expect(fetchMock).toHaveBeenCalledOnce()
    expect(takeFailureEvents()).toEqual([])
  })

  it('still reports a failure to load the config, and returns no issues', async () => {
    stubFetch(async () => new Response(accessDenied, { status: 403 }))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchRemoteConfigWithIssues('realgm', 'realgm-realgm')).resolves.toEqual({ config: {}, issues: [] })
    })

    expect(calls).toEqual({ 'config.fetch.http': 1 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['config.fetch.http'])
  })
})
