import { describe, expect, it, vi } from 'vitest'
import {
  buildCacheUrl,
  everyNth,
  localizedCacheUrl,
  mergeEveryNth,
  normState,
  resolveLocalizedListings,
  resolveLocalizedListingsWithIssues,
  resolveState,
  type LocalizedListingsIntegration,
} from '../src/localized-listings'
import type { LocalizedListingsConfig, SellwildListing } from '../src/types'
import {
  appConfig,
  invalidLocalizedListingsConfig,
  listing,
  listingsResponse,
  localizedListingsConfig,
  localizedListingsResponse,
  type AppConfigPayload,
  type LocalizedListingsConfigPayload,
} from './factories'
import { expectInvalid, expectValid } from './support/factory-checks'
import { countLogFailureCalls, takeFailureEvents, takeRecordedFailures } from './support/failures'

const BASE = 'https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/'
const TEMPLATE = 'sports-img-data-sm-webp-{state}.json'

// The CMS config with LOCALIZED_LISTINGS set, checked against the app-config
// contract (`invalidAt` when the contract rejects the value).
function remoteWith(value: AppConfigPayload['LOCALIZED_LISTINGS'] | number | unknown[], invalidAt?: string): { remote: AppConfigPayload } {
  const raw = appConfig({ LOCALIZED_LISTINGS: value as AppConfigPayload['LOCALIZED_LISTINGS'] }, 'minimal')
  if (invalidAt) expectInvalid('app-config', raw, { instancePath: invalidAt })
  else expectValid('app-config', raw)
  return { remote: raw }
}

// A local config.localizedListings, checked against its contract.
function local(config: LocalizedListingsConfigPayload): { localizedListings: LocalizedListingsConfig } {
  expectValid('localized-listings-config', config)
  return { localizedListings: config as LocalizedListingsConfig }
}

// A local config the contract rejects (at `invalidAt`).
function badLocal(config: LocalizedListingsConfigPayload, invalidAt: string): { localizedListings: LocalizedListingsConfig } {
  expectInvalid('localized-listings-config', config, { instancePath: invalidAt })
  return { localizedListings: config as LocalizedListingsConfig }
}

function without<T extends object>(value: T, key: keyof T): T {
  const copy = { ...value }
  delete copy[key]
  return copy
}

const listings = (rs: unknown[]) => rs as SellwildListing[]

describe('normState', () => {
  it.each([
    ['ga', 'GA'], [' al ', 'AL'], ['US-GA', 'GA'], ['us ga', 'GA'], ['Georgia1', 'GEORGIA1'], ['', undefined], ['  ', undefined], [42, undefined], [null, undefined],
  ])('reads %j as %j', (value, expected) => {
    expect(normState(value)).toBe(expected)
  })
})

describe('resolveLocalizedListings', () => {
  it('resolves the full local config, with no report', () => {
    expect(resolveLocalizedListings(local(localizedListingsConfig()))).toEqual({
      source: 'sportserver',
      baseUrl: BASE,
      urlTemplate: TEMPLATE,
      frequency: 25,
      forceState: 'AL',
    })
    expect(takeFailureEvents()).toEqual([])
  })

  it('resolves the remote object or its JSON text, reading a text frequency', () => {
    const text = JSON.stringify(localizedListingsConfig({}, 'frequency-text'))
    expect(resolveLocalizedListings(remoteWith(text))).toEqual({ source: undefined, baseUrl: BASE, urlTemplate: TEMPLATE, frequency: 12.5, forceState: undefined })
    expect(resolveLocalizedListings(remoteWith(localizedListingsConfig({}, 'minimal')))).toMatchObject({ frequency: 0 })
    expect(takeFailureEvents()).toEqual([])
  })

  it('lets a set local config win over the remote one', () => {
    const remote = remoteWith(localizedListingsConfig({ source: 'remote' }))
    expect(resolveLocalizedListings({ ...remote, ...local(localizedListingsConfig({ source: 'local' })) })?.source).toBe('local')
    expect(resolveLocalizedListings({ ...remote, localizedListings: undefined })?.source).toBe('remote')
    // A null local config is unset too, as `??` always read it.
    expect(resolveLocalizedListings({ ...remote, localizedListings: null as never })?.source).toBe('remote')
    expect(takeFailureEvents()).toEqual([])
  })

  it('is off with no report when nothing is set, or the CMS sent its empty unset value', () => {
    expect(resolveLocalizedListings({})).toBeNull()
    expect(resolveLocalizedListings(remoteWith(''))).toBeNull()
    expect(resolveLocalizedListings(remoteWith('   '))).toBeNull()
    expect(resolveLocalizedListings(remoteWith(null as never, '/LOCALIZED_LISTINGS'))).toBeNull()
    expect(takeFailureEvents()).toEqual([])
  })

  it('is off with no report when it is disabled', () => {
    expect(resolveLocalizedListings(local(localizedListingsConfig({}, 'disabled-only')))).toBeNull()
    expect(resolveLocalizedListings(remoteWith(localizedListingsConfig({ enabled: false })))).toBeNull()
    expect(takeFailureEvents()).toEqual([])
  })

  it('reads a long forceState as it always has, with no report', () => {
    const forced = invalidLocalizedListingsConfig('force-state-long')
    expect(resolveLocalizedListings(badLocal(forced as LocalizedListingsConfigPayload, '/forceState'))?.forceState).toBe('MA')
    expect(takeFailureEvents()).toEqual([])
  })

  it('reads a frequency that is null or empty text as unset (0), with no report', () => {
    expect(resolveLocalizedListings(badLocal(localizedListingsConfig({ frequency: null as never }, 'minimal'), '/frequency'))?.frequency).toBe(0)
    expect(resolveLocalizedListings(badLocal(localizedListingsConfig({ frequency: '' }, 'minimal'), '/frequency'))?.frequency).toBe(0)
    expect(takeFailureEvents()).toEqual([])
  })

  it.each([
    ['a word', () => badLocal(localizedListingsConfig({ frequency: 'often' }, 'minimal'), '/frequency'), 'localizedListings frequency is a string, not a number, read as 0'],
    ['a boolean', () => remoteWith(localizedListingsConfig({ frequency: true as never }, 'minimal'), '/LOCALIZED_LISTINGS'), 'LOCALIZED_LISTINGS frequency is a boolean, not a number, read as 0'],
  ])('reads a frequency that is %s as 0, as it always has, and reports localized.config.invalid once', async (_name, config, message) => {
    let integration = resolveLocalizedListings({})
    const calls = await countLogFailureCalls(() => {
      integration = resolveLocalizedListings(config())
    })

    expect(integration).toMatchObject({ baseUrl: BASE, urlTemplate: TEMPLATE, frequency: 0 })
    expect(calls).toEqual({ 'localized.config.invalid': 1 })
    expect(takeRecordedFailures()).toMatchObject([
      { event: { action: 'localized.config.invalid', label: 'localized', attributes: { severity: 'warn', msg: message } } },
    ])
  })

  it('reports localized.config.parse once for JSON text that does not parse, with the error name only', async () => {
    const calls = await countLogFailureCalls(() => {
      expect(resolveLocalizedListings(remoteWith('{"baseUrl": "https://private.example/'))).toBeNull()
    })

    expect(calls).toEqual({ 'localized.config.parse': 1 })
    const [recorded] = takeRecordedFailures()
    expect(recorded.event).toMatchObject({
      action: 'localized.config.parse',
      label: 'localized',
      attributes: { severity: 'warn', errName: 'SyntaxError', msg: 'LOCALIZED_LISTINGS is not JSON' },
    })
    expect(JSON.stringify(recorded.event)).not.toMatch(/private|baseUrl/)
  })

  it.each([
    ['JSON text of a number', () => remoteWith('5'), 'LOCALIZED_LISTINGS JSON text is a number, not an object'],
    ['JSON text of null', () => remoteWith('null'), 'LOCALIZED_LISTINGS JSON text is null, not an object'],
    ['JSON text of a list', () => remoteWith('[]'), 'LOCALIZED_LISTINGS JSON text is an array, not an object'],
    ['a number', () => remoteWith(5, '/LOCALIZED_LISTINGS'), 'LOCALIZED_LISTINGS is a number, not an object'],
    ['a list', () => remoteWith([], '/LOCALIZED_LISTINGS'), 'LOCALIZED_LISTINGS is an array, not an object'],
    ['a local text (never parsed)', () => badLocal(JSON.stringify(localizedListingsConfig()) as never, ''), 'localizedListings is a string, not an object'],
    ['an enabled config with no baseUrl', () => local(without(localizedListingsConfig({}, 'minimal'), 'baseUrl')), 'localizedListings has no baseUrl, so it is off'],
    ['a remote config with no urlTemplate', () => remoteWith(without(localizedListingsConfig(), 'urlTemplate')), 'LOCALIZED_LISTINGS has no urlTemplate, so it is off'],
    ['an enabled config with neither', () => local(localizedListingsConfig({ enabled: true }, 'disabled-only')), 'localizedListings has no baseUrl or urlTemplate, so it is off'],
    ['blank URL fields', () => badLocal(localizedListingsConfig({ baseUrl: ' ', urlTemplate: ' ' }, 'minimal'), '/baseUrl'), 'localizedListings has no baseUrl or urlTemplate, so it is off'],
  ])('reports localized.config.invalid once for %s, and is off', async (_name, config, message) => {
    const calls = await countLogFailureCalls(() => {
      expect(resolveLocalizedListings(config())).toBeNull()
    })
    expect(calls).toEqual({ 'localized.config.invalid': 1 })
    expect(takeRecordedFailures()).toMatchObject([
      { event: { action: 'localized.config.invalid', label: 'localized', attributes: { severity: 'warn', msg: message } } },
    ])
  })

  it('has a pure form that returns the issue instead of reporting it', () => {
    expect(resolveLocalizedListingsWithIssues(remoteWith('7'))).toEqual({
      integration: null,
      issues: [{ code: 'localized.config.invalid', component: 'localized', severity: 'warn', message: 'LOCALIZED_LISTINGS JSON text is a number, not an object' }],
    })
    expect(resolveLocalizedListingsWithIssues(local(localizedListingsConfig()))).toMatchObject({ issues: [] })
    expect(takeFailureEvents()).toEqual([])
  })
})

describe('resolveState, buildCacheUrl and localizedCacheUrl', () => {
  const integration = (overrides: Partial<LocalizedListingsIntegration> = {}): LocalizedListingsIntegration => ({
    baseUrl: BASE,
    urlTemplate: TEMPLATE,
    frequency: 25,
    ...overrides,
  })

  it('takes the forced state, then the geo state, else none', () => {
    expect(resolveState(integration({ forceState: 'AL' }), 'GA')).toBe('AL')
    expect(resolveState(integration(), 'us-ga')).toBe('GA')
    expect(resolveState(integration(), null)).toBeNull()
    expect(resolveState(integration(), undefined)).toBeNull()
  })

  it('fills {state} in lower case and joins base and path with one slash', () => {
    expect(buildCacheUrl(integration(), 'GA')).toBe(`${BASE}sports-img-data-sm-webp-ga.json`)
    expect(buildCacheUrl(integration({ urlTemplate: '/x-{STATE}-{state}.json' }), 'AL')).toBe(`${BASE}x-al-al.json`)
    expect(buildCacheUrl(integration({ baseUrl: 'https://c.example' }), 'AL')).toBe('https://c.example/sports-img-data-sm-webp-al.json')
    expect(buildCacheUrl(integration({ baseUrl: 'https://c.example', urlTemplate: '/{state}.json' }), 'AL')).toBe('https://c.example/al.json')
  })

  it('gives the cache URL for a resolvable state, else null (a skip, not a failure)', () => {
    expect(localizedCacheUrl(integration({ forceState: 'AL' }), null)).toBe(`${BASE}sports-img-data-sm-webp-al.json`)
    expect(localizedCacheUrl(integration(), '')).toBeNull()
    expect(takeFailureEvents()).toEqual([])
  })
})

describe('everyNth', () => {
  it.each([
    [0, 0], [-5, 0], [Number.NaN, 0], [25, 4], [33, 3], [10, 10], [99, 1], [100, 1], [250, 1],
  ])('gives %j percent every %j slots', (percent, n) => {
    expect(everyNth(percent)).toBe(n)
  })
})

describe('mergeEveryNth', () => {
  const primary = listings(listingsResponse().result.rs)
  const secondary = listings(localizedListingsResponse().result.rs)

  it('returns primary itself when there is nothing to disperse', () => {
    expect(mergeEveryNth(primary, secondary, 0)).toBe(primary)
    expect(mergeEveryNth(primary, [], 4)).toBe(primary)
    expect(mergeEveryNth([], secondary, 4)).toEqual([])
    // Every secondary listing is already in primary.
    expect(mergeEveryNth(primary, primary.slice(0, 3), 2)).toBe(primary)
  })

  it('puts a localized listing in every Nth slot and keeps the count', () => {
    const merged = mergeEveryNth(primary, secondary, 4, () => 0.5)
    const pool = new Set(secondary.map((l) => String(l.id)))

    expect(merged).toHaveLength(primary.length)
    merged.forEach((l, i) => {
      if ((i + 1) % 4 === 0) expect(pool.has(String(l.id)), `slot ${i}`).toBe(true)
      else expect(l).toBe(primary[i])
    })
  })

  it('shuffles the pool with the injected RNG and cycles it', () => {
    const [p1, p2, p3, p4, p5, p6] = primary
    const [s1, s2] = secondary
    expect(mergeEveryNth([p1, p2, p3, p4, p5, p6], [s1, s2], 2, () => 0)).toEqual([p1, s2, p3, s1, p5, s2])
    expect(mergeEveryNth([p1, p2, p3, p4], [s1, s2], 2, () => 0.99)).toEqual([p1, s1, p3, s2])
  })

  it('uses Math.random when no RNG is given', () => {
    const random = vi.spyOn(Math, 'random').mockReturnValue(0)
    const [p1, p2] = primary
    const [s1, s2] = secondary
    expect(mergeEveryNth([p1, p2], [s1, s2], 2)).toEqual([p1, s2])
    expect(random).toHaveBeenCalled()
  })

  it('drops empty slots, listings without an id, and ones already in primary from the pool', () => {
    const noId = listing({ id: null as never })
    expectInvalid('listing', noId, { instancePath: '/id' })
    const [p1, p2] = primary
    const [s1] = secondary

    const merged = mergeEveryNth([p1, p2], listings([null, noId, p1, s1]), 2, () => 0)

    expect(merged).toEqual([p1, s1])
  })
})
