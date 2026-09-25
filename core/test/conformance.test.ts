import { beforeEach, describe, expect, it, vi } from 'vitest'
import { clearListingCache, fetchListings } from '../src/api'
import { buildConfig, configure } from '../src/config'
import { buildCacheUrl, everyNth, resolveLocalizedListings } from '../src/localized-listings'
import { clearRemoteConfigCache, mapRemoteConfig, resolveAdStack } from '../src/remote-config'
import type { SellwildConfig } from '../src/types'
import { contract } from './support/contracts'
import { takeFailureCodes } from './support/failures'

// contracts/README.md "Conformance": every app-config and listings input
// (real samples and valid fixtures) goes through core's real parser and must
// give the expected typed result for each field core is held to. A field
// named in core's drift entry for the case (contracts/expectations/drift/
// core.json) may differ, and must: the entry is removed in the change that
// fixes the drift.

interface ExpectationFile {
  zones: string[]
  fields: Record<string, { platforms: string[] }>
  cases: Array<{ file: string; expected: Record<string, unknown> }>
}

type ExpectationName = 'app-config' | 'listings-response'

/** contracts/expectations/drift/<platform>.json: drift text per expectations file and case. */
interface DriftFile {
  platform: string
  expectations: Record<ExpectationName, Record<string, string>>
  other: Record<string, string>
}

const coreDrift = contract<DriftFile>('expectations/drift/core.json')

function coreFields(doc: ExpectationFile): string[] {
  return Object.keys(doc.fields).filter((f) => doc.fields[f].platforms.includes('core'))
}

// Fields a drift text names: "field:" anywhere, or the text starts with it.
function driftFields(doc: ExpectationFile, text: string | undefined): string[] {
  if (!text) return []
  return Object.keys(doc.fields).filter((f) => text.includes(`${f}:`) || text.startsWith(f))
}

// Per-field view of the expected value for core, where it has more than core
// is held to.
type Views = Record<string, (expected: unknown) => unknown>

function checkCase(doc: ExpectationFile, drift: Record<string, string>, c: ExpectationFile['cases'][number], actual: Record<string, unknown>, views: Views = {}): void {
  const driftNamed = driftFields(doc, drift[c.file])
  for (const field of coreFields(doc)) {
    const expected = views[field] ? views[field](c.expected[field]) : c.expected[field]
    if (driftNamed.includes(field)) {
      expect(actual[field], `${c.file} ${field} is listed as known drift, so it must differ`).not.toEqual(expected)
    } else {
      expect(actual[field], `${c.file} ${field}`).toEqual(expected)
    }
  }
}

function stubJson(body: unknown): void {
  vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify(body))))
}

describe('drift handling', () => {
  // Core has no drift entries today; this pins how one is treated when added.
  const doc: ExpectationFile = {
    zones: [],
    fields: { iabCats: { platforms: ['core'] }, slug: { platforms: ['core'] }, publisherId: { platforms: ['ios'] } },
    cases: [],
  }
  const drifting = { file: 'x.json', expected: { iabCats: ['IAB15'], slug: 's', publisherId: '1' } }
  const drift = { 'x.json': 'iabCats: core reads only a list' }

  it('lets a named field differ, and still checks the others', () => {
    expect(() => checkCase(doc, drift, drifting, { iabCats: [], slug: 's' })).not.toThrow()
    expect(() => checkCase(doc, drift, drifting, { iabCats: [], slug: 'other' })).toThrow('x.json slug')
  })

  it('fails once the drift is fixed, so the entry gets removed', () => {
    expect(() => checkCase(doc, drift, drifting, { iabCats: ['IAB15'], slug: 's' })).toThrow('listed as known drift')
  })

  it('checks every field when the case has no entry', () => {
    expect(() => checkCase(doc, {}, drifting, { iabCats: [], slug: 's' })).toThrow('x.json iabCats')
  })

  it('reads core drift from contracts/expectations/drift/core.json, which has no entries today', () => {
    expect(coreDrift.platform).toBe('core')
    expect(coreDrift.expectations).toEqual({ 'app-config': {}, 'listings-response': {} })
    for (const file of ['expectations/app-config.expected.json', 'expectations/listings-response.expected.json']) {
      const cases = contract<ExpectationFile>(file).cases
      expect(cases.filter((c) => 'knownDrift' in c).map((c) => c.file), file).toEqual([])
    }
  })
})

const appDoc = contract<ExpectationFile>('expectations/app-config.expected.json')

// The expectation fields, from core's typed config (and the mapped remote
// config, where "unset" must be told apart from core's default).
function appConfigResult(config: SellwildConfig, raw: Record<string, unknown>): Record<string, unknown> {
  const mapped = mapRemoteConfig(raw)
  const integration = resolveLocalizedListings(config)
  const state = integration?.forceState ?? 'AL'
  return {
    partnerCode: config.partnerCode,
    slug: config.slug,
    mobileZids: config.mobileZids,
    adRefreshIntervalMs: mapped.adRefreshInterval ?? null,
    iabCats: config.iabCats,
    adStack: {
      global: config.adStack ?? null,
      byZone: config.adStackByZone ?? {},
      resolved: Object.assign({}, ...appDoc.zones.map((z) => ({ [z]: resolveAdStack(config, z) }))),
    },
    eventsEnabled: config.eventsEnabled,
    failuresEnabled: config.failuresEnabled,
    failuresSampleRate: config.failuresSampleRate,
    s2sConfigText: config.s2sConfig || null,
    localizedListings: integration && {
      source: integration.source ?? null,
      baseUrl: integration.baseUrl,
      urlTemplate: integration.urlTemplate,
      frequency: integration.frequency,
      forceState: integration.forceState ?? null,
      cacheUrlForState: { state, url: buildCacheUrl(integration, state) },
      everyNth: everyNth(integration.frequency),
    },
  }
}

describe('app-config conformance (core)', () => {
  beforeEach(() => {
    clearRemoteConfigCache()
  })

  it('covers every case in the expectation file', () => {
    expect(appDoc.cases.length).toBeGreaterThanOrEqual(37)
    expect(coreFields(appDoc)).toEqual(expect.arrayContaining(['eventsEnabled', 'failuresEnabled', 'failuresSampleRate']))
  })

  // The failures configure() reports for a case. Every other sample and valid
  // fixture reports none.
  const reports: Record<string, string[]> = {
    // AD_STACK_BY_ZONE 999: 'bogus' is dropped (config.adstack.invalid).
    'fixtures/app-config/valid/by-zone-maps-objects.json': ['config.adstack.invalid'],
  }

  it.each(appDoc.cases.map((c) => [c.file, c] as const))('%s', async (_file, c) => {
    const raw = contract<Record<string, unknown>>(c.file)
    stubJson(raw)

    const config = await configure(String(raw.CODE), String(raw.SLUG))
    expect(takeFailureCodes()).toEqual(reports[c.file] ?? [])

    // mobileZids: core has no OS, so it is held to the shared value only.
    checkCase(appDoc, coreDrift.expectations['app-config'], c, appConfigResult(config, raw), { mobileZids: (v) => (v as { shared: unknown }).shared })
  })
})

const listingsDoc = contract<ExpectationFile>('expectations/listings-response.expected.json')

describe('listings conformance (core)', () => {
  beforeEach(() => {
    clearListingCache()
  })

  it.each(listingsDoc.cases.map((c) => [c.file, c] as const))('%s', async (_file, c) => {
    stubJson(contract(c.file))

    const result = await fetchListings(buildConfig({ partnerCode: 'conformance', listingsUrl: 'https://cache.sellwild.com/conformance' }))
    expect(takeFailureCodes()).toEqual([])

    checkCase(listingsDoc, coreDrift.expectations['listings-response'], c, {
      items: result.listings.length,
      ids: result.listings.map((l) => String(l.id)),
      widgetCacheVersionId: result.widgetCacheVersionId,
    })
  })
})
