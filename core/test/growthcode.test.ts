import { describe, expect, it } from 'vitest'
import {
  buildSyncBody,
  buildSyncUrl,
  GROWTHCODE_DEFAULT_ENDPOINT,
  GROWTHCODE_DEFAULT_TTL_HOURS,
  mergeEids,
  parseEidBlob,
  parseEidBlobWithIssues,
  parseGrowthCodeResponse,
  parseGrowthCodeResponseWithIssues,
  resolveGrowthCode,
  resolveGrowthCodeWithIssues,
  shouldSync,
} from '../src/growthcode'
import type { SellwildEid } from '../src/types'
import {
  appConfig,
  eidBlob,
  eidEntry,
  growthCodeSyncResponse,
  invalidEidBlob,
  invalidGrowthCodeSyncResponse,
  type AppConfigPayload,
} from './factories'
import { expectInvalid, expectValid } from './support/factory-checks'
import { countLogFailureCalls, takeFailureEvents, takeRecordedFailures } from './support/failures'

// The CMS config GrowthCode reads its GROWTHCODE_* keys from: the minimal
// fixture plus overrides, checked against the app-config contract.
function remote(overrides: Partial<AppConfigPayload>): AppConfigPayload {
  const raw = appConfig(overrides, 'minimal')
  expectValid('app-config', raw)
  return raw
}

const ON = { GROWTHCODE_ENABLED: true, GROWTHCODE_PARTNER_ID: 'W347H328D', GROWTHCODE_SYNC_URL: 'https://weatherbug.com' }

describe('resolveGrowthCode', () => {
  it('uses the defaults when nothing is set, and is off', () => {
    expect(resolveGrowthCode({})).toEqual({
      enabled: false,
      partnerId: undefined,
      endpoint: GROWTHCODE_DEFAULT_ENDPOINT,
      syncUrl: undefined,
      sendMaid: true,
      ttlHours: GROWTHCODE_DEFAULT_TTL_HOURS,
    })
  })

  it('reads the remote GROWTHCODE_* keys', () => {
    const settings = resolveGrowthCode({
      remote: remote({ ...ON, GROWTHCODE_ENDPOINT: 'https://gc.invalid/sync', GROWTHCODE_SEND_MAID: 'no', GROWTHCODE_TTL_HOURS: '24' }),
    })
    expect(settings).toEqual({
      enabled: true,
      partnerId: 'W347H328D',
      endpoint: 'https://gc.invalid/sync',
      syncUrl: 'https://weatherbug.com',
      sendMaid: false,
      ttlHours: 24,
    })
  })

  it('lets the local config win over remote for every field', () => {
    const settings = resolveGrowthCode({
      growthCode: { enabled: false, partnerId: 'L1', endpoint: 'https://local.invalid', syncUrl: 'https://local.example', sendMaid: false, ttlHours: 1 },
      remote: remote({ ...ON, GROWTHCODE_SEND_MAID: true, GROWTHCODE_TTL_HOURS: 12 }),
    })
    expect(settings).toEqual({ enabled: false, partnerId: 'L1', endpoint: 'https://local.invalid', syncUrl: 'https://local.example', sendMaid: false, ttlHours: 1 })
    expect(resolveGrowthCode({ growthCode: { enabled: true, sendMaid: true, partnerId: 'L1', syncUrl: 'https://s' } })).toMatchObject({ enabled: true, sendMaid: true })
  })

  it.each([
    [true, true], [false, false], [1, true], [0, false], ['1', true], ['TRUE', true], ['Yes', true], ['on', true], ['off', false], ['2', false],
  ])('reads GROWTHCODE_ENABLED %j as %j', (value, enabled) => {
    const settings = resolveGrowthCode({ remote: remote({ ...ON, GROWTHCODE_ENABLED: value }) })
    expect(settings.enabled).toBe(enabled)
  })

  it('falls back to the per-zone map when the global flag is off', () => {
    const byZone = remote({ ...ON, GROWTHCODE_ENABLED: false, GROWTHCODE_ENABLED_BY_ZONE: { 43: 'true', 280: 0 } })
    expect(resolveGrowthCode({ remote: byZone }, 43).enabled).toBe(true)
    expect(resolveGrowthCode({ remote: byZone }, '280').enabled).toBe(false)
    expect(resolveGrowthCode({ remote: byZone }, 999).enabled).toBe(false)
    expect(resolveGrowthCode({ remote: byZone }).enabled).toBe(false)
    expect(resolveGrowthCode({ remote: byZone }, null).enabled).toBe(false)
    // The CMS writes '' when the map is unset.
    expect(resolveGrowthCode({ remote: remote({ ...ON, GROWTHCODE_ENABLED: false, GROWTHCODE_ENABLED_BY_ZONE: '' }) }, 43).enabled).toBe(false)
  })

  it('ignores remote text that is empty or not a number', () => {
    const settings = resolveGrowthCode({
      remote: remote({ GROWTHCODE_PARTNER_ID: '', GROWTHCODE_ENDPOINT: '', GROWTHCODE_TTL_HOURS: 'soon', GROWTHCODE_SEND_MAID: 1 }),
    })
    expect(settings).toMatchObject({ partnerId: undefined, endpoint: GROWTHCODE_DEFAULT_ENDPOINT, ttlHours: GROWTHCODE_DEFAULT_TTL_HOURS, sendMaid: true })
    const objectTtl = appConfig({ GROWTHCODE_TTL_HOURS: { hours: 2 } }, 'minimal')
    expectInvalid('app-config', objectTtl, { instancePath: '/GROWTHCODE_TTL_HOURS' })
    expect(resolveGrowthCode({ remote: objectTtl }).ttlHours).toBe(GROWTHCODE_DEFAULT_TTL_HOURS)
  })

  it('reports nothing when it is off, or on with a partner id and a sync URL', () => {
    resolveGrowthCode({ remote: remote({ GROWTHCODE_ENABLED: false }) })
    resolveGrowthCode({ remote: remote(ON) }, 43)
    expect(takeFailureEvents()).toEqual([])
  })

  it.each([
    [{ ...ON, GROWTHCODE_SYNC_URL: undefined }, 'sync URL'],
    [{ ...ON, GROWTHCODE_PARTNER_ID: '' }, 'partner id'],
    [{ GROWTHCODE_ENABLED: 'yes' }, 'partner id or sync URL'],
  ])('reports growthcode.config.missing once when it is on without a %s', async (overrides, missing) => {
    let settings = resolveGrowthCode({})
    const calls = await countLogFailureCalls(() => {
      settings = resolveGrowthCode({ remote: remote(overrides) }, 43)
    })

    expect(settings.enabled).toBe(true)
    expect(calls).toEqual({ 'growthcode.config.missing': 1 })
    expect(takeRecordedFailures()).toMatchObject([
      {
        event: {
          action: 'growthcode.config.missing',
          label: 'growthcode',
          attributes: { severity: 'warn', msg: `GrowthCode is on without a ${missing}, so it never syncs`, zoneId: '43' },
        },
      },
    ])
  })

  it('resolves the real weatherbug config on, with no report', () => {
    expect(resolveGrowthCode({ remote: appConfig() })).toEqual({
      enabled: true,
      partnerId: 'W347H328D',
      endpoint: GROWTHCODE_DEFAULT_ENDPOINT,
      syncUrl: 'https://weatherbug.com',
      sendMaid: true,
      ttlHours: 48,
    })
    expect(takeFailureEvents()).toEqual([])
  })

  it('leaves zoneId out of the report when no zone was asked for', () => {
    resolveGrowthCode({ remote: remote({ GROWTHCODE_ENABLED: 1 }) })
    const [event] = takeFailureEvents()
    expect(event.action).toBe('growthcode.config.missing')
    expect(event.attributes).not.toHaveProperty('zoneId')
  })

  it('has a pure form that returns the issue instead of reporting it', () => {
    const { settings, issues } = resolveGrowthCodeWithIssues({ growthCode: { enabled: true } })
    expect(settings.enabled).toBe(true)
    expect(issues).toEqual([
      { code: 'growthcode.config.missing', component: 'growthcode', severity: 'warn', message: 'GrowthCode is on without a partner id or sync URL, so it never syncs' },
    ])
    expect(takeFailureEvents()).toEqual([])
  })
})

describe('shouldSync', () => {
  const HOUR = 3_600_000
  it('syncs with no GCID or no last sync, and once the TTL has passed', () => {
    expect(shouldSync(null, 0, 48, 0)).toBe(true)
    expect(shouldSync('', 0, 48, 0)).toBe(true)
    expect(shouldSync('gc', null, 48, 0)).toBe(true)
    expect(shouldSync('gc', undefined, 48, 0)).toBe(true)
    expect(shouldSync('gc', 0, 48, 48 * HOUR - 1)).toBe(false)
    expect(shouldSync('gc', 0, 48, 48 * HOUR)).toBe(true)
  })
})

describe('parseEidBlob', () => {
  const text = (value: unknown) => JSON.stringify(value)

  it('parses the full fixture: drops inserter/matcher, defaults atype to 0, keeps stype in ext', () => {
    expect(parseEidBlob(text(eidBlob()))).toEqual([
      { source: 'uidapi.com', uids: [{ id: 'A4AAAABj-fixture-uid2', atype: 3 }] },
      { source: 'id5-sync.com', uids: [{ id: 'ID5*fixture', atype: 1 }, { id: 'ppid-fixture', atype: 0, ext: { stype: 'ppuid' } }] },
    ])
    expect(takeFailureEvents()).toEqual([])
  })

  it('gives [] with no report for a missing blob', () => {
    expect(parseEidBlob(null)).toEqual([])
    expect(parseEidBlob(undefined)).toEqual([])
    expect(parseEidBlob('')).toEqual([])
    expect(takeFailureEvents()).toEqual([])
  })

  it('reports growthcode.eid.parse once for eb text that is not JSON, with the error name only', async () => {
    const body = growthCodeSyncResponse({ eb: '[{"source":' })
    expectValid('growthcode-sync-response', body)

    const calls = await countLogFailureCalls(() => {
      expect(parseEidBlob(body.eb)).toEqual([])
    })

    expect(calls).toEqual({ 'growthcode.eid.parse': 1 })
    const [recorded] = takeRecordedFailures()
    expect(recorded.event).toMatchObject({ action: 'growthcode.eid.parse', label: 'growthcode', attributes: { severity: 'warn', errName: 'SyntaxError', msg: 'eid blob is not JSON' } })
    expect(recorded.event.attributes).not.toHaveProperty('stack')
  })

  // FAILURES.md 7.6: eids are never sent. V8 quotes the start of the text it
  // could not parse in the SyntaxError message ("ID5*fixtu"...), so only the
  // error's name may reach the event.
  it('never sends any of the blob text', () => {
    const body = growthCodeSyncResponse({ eb: 'ID5*fixture-token-not-json' })
    expectValid('growthcode-sync-response', body)
    expect(() => JSON.parse(body.eb!)).toThrow(/ID5/)

    parseEidBlob(body.eb)

    const [event] = takeFailureEvents()
    expect(event.action).toBe('growthcode.eid.parse')
    expect(JSON.stringify(event)).not.toMatch(/ID5|fixture|token/)
  })

  it('reports growthcode.eid.invalid once for a blob that is not a list', async () => {
    const calls = await countLogFailureCalls(() => {
      expect(parseEidBlob(text(invalidEidBlob('not-an-array')))).toEqual([])
    })
    expect(calls).toEqual({ 'growthcode.eid.invalid': 1 })
    expect(takeFailureEvents()).toMatchObject([{ action: 'growthcode.eid.invalid', attributes: { msg: 'eid blob is an object, not a list' } }])
  })

  it('reports a blob that drops only a uid, and keeps its entry', () => {
    const blob = [eidEntry({ source: 'mixed.example', uids: [{ id: 'keep', atype: 1 }, { atype: 2 } as never] })]
    expectInvalid('eid-blob', blob, { instancePath: '/0/uids/1', keyword: 'required' })

    expect(parseEidBlob(text(blob))).toEqual([{ source: 'mixed.example', uids: [{ id: 'keep', atype: 1 }] }])

    expect(takeFailureEvents()).toMatchObject([
      { action: 'growthcode.eid.invalid', attributes: { msg: 'eid blob: dropped 0 of 1 entries and 1 uids without source, uids or id' } },
    ])
  })

  it.each([
    ['missing-source', 'dropped 1 of 1 entries and 0 uids'],
    ['uid-missing-id', 'dropped 1 of 1 entries and 1 uids'],
  ])('reports growthcode.eid.invalid once for the invalid fixture %s', (name, dropped) => {
    expect(parseEidBlob(text(invalidEidBlob(name)))).toEqual([])
    expect(takeFailureEvents()).toMatchObject([{ action: 'growthcode.eid.invalid', attributes: { msg: `eid blob: ${dropped} without source, uids or id` } }])
  })

  it('keeps the good entries and uids, and reports what it dropped once', () => {
    const blob = [
      ...eidBlob(),
      null,
      5,
      eidEntry({ source: 'no-uids.example', uids: 'x' as never }),
      eidEntry({ source: 'bad-uids.example', uids: [null, 7, { id: '' }] as never }),
      eidEntry({ source: 'mixed.example', uids: [{ id: 'keep', atype: '2' }, { atype: 1 } as never] }),
    ]
    expectInvalid('eid-blob', blob, { instancePath: '/2', keyword: 'type' })

    const eids = parseEidBlob(text(blob))

    expect(eids.map((e) => e.source)).toEqual(['uidapi.com', 'id5-sync.com', 'mixed.example'])
    expect(eids[2].uids).toEqual([{ id: 'keep', atype: 2 }])
    expect(takeFailureEvents()).toMatchObject([
      { action: 'growthcode.eid.invalid', attributes: { msg: 'eid blob: dropped 4 of 7 entries and 4 uids without source, uids or id' } },
    ])
  })

  it('reads a word atype as 0 without a report, as it always has', () => {
    expect(parseEidBlob(text(invalidEidBlob('atype-word')))).toEqual([{ source: 'uidapi.com', uids: [{ id: 'x', atype: 0 }] }])
    expect(takeFailureEvents()).toEqual([])
  })

  it('has a pure form that returns the issues instead of reporting them', () => {
    const { eids, issues } = parseEidBlobWithIssues('nope')
    expect(eids).toEqual([])
    expect(issues).toMatchObject([{ code: 'growthcode.eid.parse', component: 'growthcode', severity: 'warn', message: 'eid blob is not JSON' }])
    // The parse error cut down to its name: no message, no stack.
    expect(issues[0].error).toBeInstanceOf(Error)
    expect(issues[0].error).toMatchObject({ name: 'SyntaxError', message: '', stack: undefined })
    expect(parseEidBlobWithIssues(text(eidBlob()))).toMatchObject({ issues: [] })
    expect(takeFailureEvents()).toEqual([])
  })
})

describe('mergeEids', () => {
  it('keeps consumer eids first and drops GrowthCode sources the consumer set', () => {
    const consumer: SellwildEid[] = [{ source: 'id5-sync.com', uids: [{ id: 'mine', atype: 1 }] }]
    const growthcode = parseEidBlob(JSON.stringify(eidBlob()))
    expect(mergeEids(consumer, growthcode)).toEqual([consumer[0], growthcode[0]])
    expect(mergeEids([], growthcode)).toEqual(growthcode)
  })
})

describe('buildSyncUrl and buildSyncBody', () => {
  it('puts pid and u on the query string', () => {
    expect(buildSyncUrl(GROWTHCODE_DEFAULT_ENDPOINT, 'W3 4', 'https://a.example/?x=1')).toBe(
      'https://ids.api.gcprivacy.id/v4/sync/api?pid=W3%204&u=https%3A%2F%2Fa.example%2F%3Fx%3D1',
    )
    expect(buildSyncUrl('https://gc.invalid/sync?v=2', 'W', 'u')).toBe('https://gc.invalid/sync?v=2&pid=W&u=u')
  })

  it('form-encodes the set fields and leaves out empty ones', () => {
    expect(buildSyncBody({ gcid: 'g c', h: 'weatherbug.com', ref: '', maid: null, maidType: 'idfa' })).toBe('gcid=g%20c&h=weatherbug.com&maid_type=idfa')
    expect(buildSyncBody({ ref: 'r', maid: 'm' })).toBe('ref=r&maid=m')
    expect(buildSyncBody({})).toBe('')
  })
})

describe('parseGrowthCodeResponse', () => {
  it('reads the fields the SDK uses from the full fixture', () => {
    expect(parseGrowthCodeResponse(growthCodeSyncResponse())).toEqual({
      gcId: 'gc-fixture-0001',
      eidBlob: growthCodeSyncResponse().eb,
      idInject: true,
      version: 4,
    })
    expect(parseGrowthCodeResponse(growthCodeSyncResponse({}, 'gc-id-null'))).toEqual({
      gcId: undefined,
      eidBlob: undefined,
      idInject: undefined,
      version: undefined,
    })
    expect(parseGrowthCodeResponse(growthCodeSyncResponse({ idi: false, version: '5' as never }))).toMatchObject({ idInject: false, version: 5 })
    expect(takeFailureEvents()).toEqual([])
  })

  it.each([
    [null, 'null'],
    [undefined, 'undefined'],
    ['text', 'a string'],
    [7, 'a number'],
  ])('reports growthcode.sync.invalid once for %j and gives {}', async (json, kind) => {
    const calls = await countLogFailureCalls(() => {
      expect(parseGrowthCodeResponse(json as never)).toEqual({})
    })
    expect(calls).toEqual({ 'growthcode.sync.invalid': 1 })
    expect(takeRecordedFailures()).toMatchObject([
      { event: { action: 'growthcode.sync.invalid', label: 'growthcode', attributes: { severity: 'warn', msg: `sync response is ${kind}, not an object` } } },
    ])
  })

  it('reports the not-an-object fixture (an array) once, and still reads it as it always has', () => {
    const body = invalidGrowthCodeSyncResponse('not-an-object')
    expect(parseGrowthCodeResponse(body as never)).toEqual({ gcId: undefined, eidBlob: undefined, idInject: undefined, version: undefined })
    expect(takeFailureEvents()).toMatchObject([{ action: 'growthcode.sync.invalid', attributes: { msg: 'sync response is an array, not an object' } }])
  })

  it('has a pure form that returns the issue instead of reporting it', () => {
    expect(parseGrowthCodeResponseWithIssues(null)).toEqual({
      response: {},
      issues: [{ code: 'growthcode.sync.invalid', component: 'growthcode', severity: 'warn', message: 'sync response is null, not an object' }],
    })
    expect(takeFailureEvents()).toEqual([])
  })
})
