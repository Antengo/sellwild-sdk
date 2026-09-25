import { describe, expect, it } from 'vitest'
import * as core from '../src/failures/core'
import type { ClientFailureEvent, CoreFailureContext, CoreFailureInput, FailureState } from '../src/failures/core'
import { contract } from './support/contracts'
import { validate } from './support/schemas'

// contracts/FAILURES.md section 12: the pure core reproduces every golden
// vector exactly (the same wire JSON, flushNow, reason and state), and every
// unit table. TS runs the UTF-16 file too.

interface Vector {
  name: string
  input: CoreFailureInput
  context: CoreFailureContext & { uid: unknown; now: number }
  stateBefore: FailureState
  expected: { event: ClientFailureEvent | null; flushNow: boolean; reason: string | null; stateAfter: FailureState }
}

interface GoldenFile {
  limits: Record<string, number>
  vectors: Vector[]
  units: Record<string, Array<{ input: unknown; expected: unknown }>>
}

const files = {
  'log-failure.vectors.json': contract<GoldenFile>('golden/log-failure.vectors.json'),
  'log-failure.utf16.vectors.json': contract<GoldenFile>('golden/log-failure.utf16.vectors.json'),
}

// One entry per unit table in the vector files. A new table fails the
// coverage check below until it is wired here.
const units: Record<string, (input: never) => unknown> = {
  fnv1a32: (s: string) => core.fnv1a32(s),
  truncateUnicode: ([s, max]: [string, number]) => core.truncateUnicode(s, max),
  hostOf: (u: unknown) => core.hostOf(u),
  sanitizeMessage: (s: unknown) => core.sanitizeMessage(s),
  coerceFlag: (v: unknown) => core.coerceFlag(v),
  coerceRate: (v: unknown) => core.coerceRate(v),
  normalizeCode: (v: unknown) => core.normalizeCode(v),
  normalizeHttpStatus: (v: unknown) => core.normalizeHttpStatus(v),
}

describe.each(Object.entries(files))('%s', (_file, golden) => {
  it('has the limits the port uses', () => {
    expect(golden.limits).toEqual(core.LIMITS)
  })

  it.each(golden.vectors.map((v) => [v.name, v] as const))('%s', (_name, v) => {
    const before = JSON.stringify(v.stateBefore)
    const r = core.decideFailure(v.stateBefore, v.input, v.context, v.context.uid, v.context.now)

    expect({ event: r.event, flushNow: r.flushNow, reason: r.reason, stateAfter: r.state }).toStrictEqual(v.expected)
    // Same wire JSON: attribute order included.
    expect(JSON.stringify(r.event)).toBe(JSON.stringify(v.expected.event))
    // State is never changed in place.
    expect(JSON.stringify(v.stateBefore)).toBe(before)
  })

  it('has a runner for every unit table', () => {
    expect(Object.keys(units)).toEqual(expect.arrayContaining(Object.keys(golden.units)))
  })

  it.each(Object.entries(golden.units))('unit table %s', (name, rows) => {
    const run = units[name]
    for (const row of rows) {
      expect(run(row.input as never), `${name}(${JSON.stringify(row.input)})`).toEqual(row.expected)
    }
  })
})

describe('golden coverage', () => {
  it('replays every rule family and every drop reason', () => {
    const vectors = files['log-failure.vectors.json'].vectors
    const families = new Set(vectors.map((v) => v.name.split('.')[0]))
    for (const f of ['basic', 'sanitize', 'truncate', 'code', 'component', 'severity', 'dedupe', 'keycap', 'lru', 'session', 'sampling', 'flags', 'budget', 'attrs', 'stack']) {
      expect(families, f).toContain(f)
    }
    const reasons = new Set(vectors.map((v) => v.expected.reason))
    expect([...reasons].sort()).toEqual([null, 'deduped', 'events_disabled', 'failures_disabled', 'key_capped', 'sampled_out', 'session_capped'].sort())
  })

  it('emits only events the client-failure-event schema accepts', () => {
    for (const [file, golden] of Object.entries(files)) {
      for (const v of golden.vectors) {
        const r = core.decideFailure(v.stateBefore, v.input, v.context, v.context.uid, v.context.now)
        if (!r.event) continue
        const check = validate('client-failure-event', r.event)
        expect(check.ok, `${file} ${v.name}: ${check.text}`).toBe(true)
      }
    }
  })
})

// Paths the vectors do not reach: null arguments and the canonical JSON
// escapes (vector text is cleaned before it is measured).
describe('parseRate', () => {
  // The number coerceRate clamps, or null where coerceRate falls back to 1.
  // remote-config uses it to tell a sent rate from one it had to ignore.
  it('agrees with every coerceRate row of the golden unit table', () => {
    const table = files['log-failure.vectors.json'].units.coerceRate
    expect(table.length).toBeGreaterThan(5)
    for (const { input, expected } of table) {
      const parsed = core.parseRate(input)
      expect(parsed === null ? 1 : Math.min(1, Math.max(0, parsed)), JSON.stringify(input)).toBe(expected)
    }
  })

  it.each([
    [0.25, 0.25], [2, 2], [-1, -1], [' +.5 ', 0.5], ['3.', 3], ['', null], ['50%', null], [Number.NaN, null], [Infinity, null], [true, null], [null, null], [{}, null],
  ])('reads %j as %j', (input, expected) => {
    expect(core.parseRate(input)).toBe(expected)
  })
})

describe('pure core edges', () => {
  const NOW = 1790000000000

  it('treats null state, input and context as empty', () => {
    const r = core.decideFailure(null, null, null, 'u', NOW)
    expect(r.reason).toBeNull()
    expect(r.event).toMatchObject({
      action: 'client.code.invalid',
      label: 'unknown',
      attributes: { code: 'unknown', client: 'unknown', clientVersion: 'unknown', severity: 'error', seq: '1' },
      uid: 'u',
    })
    expect(r.state.sessionCount).toBe(1)
    expect(core.buildFailureEvent({
      action: 'a.b.c', label: 'listings', severity: 'warn', errName: null, msg: null, stack: null,
      httpStatus: null, host: null, zoneId: null, seq: 2, repeat: 1, capped: false,
    }, null, 42, NOW)).toEqual({
      event: 'clientFailure',
      action: 'a.b.c',
      label: 'listings',
      attributes: { code: 'unknown', client: 'unknown', clientVersion: 'unknown', severity: 'warn', fv: '1', seq: '2', repeat: '1' },
      uid: '',
      createdTime: NOW,
    })
  })

  it('escapes the canonical JSON like JSON.stringify, but leaves / and non-ASCII literal', () => {
    const event: ClientFailureEvent = {
      event: 'clientFailure',
      action: 'a.b.c',
      label: 'x',
      attributes: { msg: 'q" b\\ \b\f\n\r\t \u0001 / é 😀' },
      uid: 'u',
      createdTime: NOW,
    }
    const json = core.canonicalJson(event)
    expect(json).toBe(
      '{"event":"clientFailure","action":"a.b.c","label":"x","attributes":{"msg":"q\\" b\\\\ \\b\\f\\n\\r\\t \\u0001 / é 😀"},"uid":"u","createdTime":1790000000000}',
    )
    expect(JSON.parse(json)).toEqual(event)
    // é is 2 bytes and 😀 is 4 in UTF-8.
    expect(core.eventByteSize(event)).toBe(json.length - 'é😀'.length + 2 + 4)
  })

  it('counts a lone surrogate as the 3 bytes of U+FFFD', () => {
    const event: ClientFailureEvent = { event: 'clientFailure', action: 'a.b.c', label: 'x', attributes: {}, uid: '\ud800', createdTime: 1 }
    expect(core.eventByteSize(event)).toBe(core.canonicalJson(event).length - 1 + 3)
    expect(core.fnv1a32('\ud800')).toBe(core.fnv1a32('\ufffd'))
    expect(core.fnv1a32(7)).toBe(core.fnv1a32(''))
  })

  it('cleans text that is not a string to empty', () => {
    expect(core.cleanText(undefined)).toBe('')
    expect(core.cleanText(12)).toBe('')
    expect(core.sanitizeStack(undefined, null)).toBeNull()
  })

  it('treats a non-string uid as empty when sampling', () => {
    expect(core.isSampled(undefined, 0.5)).toBe(core.isSampled('', 0.5))
  })

  it('keeps tag and supplementary variation-selector sequences whole when cutting', () => {
    // England flag: U+1F3F4 then tags U+E0067 … U+E007F.
    const england = '\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}'
    expect(core.truncateUnicode(`ab${england}cd`, 5)).toBe('ab…')
    expect(core.truncateUnicode('ab\u{845B}\u{E0100}cd', 4)).toBe('ab…')
  })

  it('handles hosts and stack URLs the vectors do not', () => {
    expect(core.hostOf('http://[::1/x')).toBeNull()
    expect(core.sanitizeStack('at a (file:///app/main.js?v=2:1:1)\nat b (file:///)', null)).toBe('at a (main.js)\nat b (<url>)')
  })

  it('builds a dedupe key without an error name or message', () => {
    expect(core.dedupeKey('a.b.c', 'listings', null, null)).toBe('a.b.c|listings||')
  })
})
