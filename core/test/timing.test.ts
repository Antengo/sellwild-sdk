import { describe, expect, it, vi } from 'vitest'
import * as core from '../src/timing/core'
import type { SdkTimingEvent, TimingContext, TimingInput, TimingState } from '../src/timing/core'
import {
  getTimingInternalErrors,
  monotonicMs,
  recordTiming,
  setTimingContext,
  startTiming,
} from '../src/timing'
import { configure, SDK_VERSION } from '../src/config'
import { setFailureContext } from '../src/failures'
import { clearRemoteConfigCache } from '../src/remote-config'
import { appConfig } from './factories'
import { contract } from './support/contracts'
import { takeFailureEvents } from './support/failures'
import { validate } from './support/schemas'
import { takeTimingEvents } from './support/timing'

// contracts/FAILURES.md section 18.1: the timing core reproduces
// golden/sdk-timing.vectors.json, and the shell sends what it decides and
// logs `*.slow` for a step over its budget.

interface Vector {
  name: string
  input: TimingInput
  context: TimingContext & { uid: unknown; now: number }
  stateBefore: TimingState
  expected: { event: SdkTimingEvent | null; reason: string | null; stateAfter: TimingState }
}

interface GoldenFile {
  limits: Record<string, number>
  budgets: Record<string, number>
  budgetKeys: Record<string, string>
  slowCodes: Record<string, string>
  steps: string[]
  vectors: Vector[]
  units: Record<string, Array<{ input: unknown; expected: unknown }>>
}

const golden = contract<GoldenFile>('golden/sdk-timing.vectors.json')

describe('sdk-timing.vectors.json', () => {
  it('has the limits, budgets, keys, codes and steps the port uses', () => {
    expect(golden.limits).toEqual(core.TIMING_LIMITS)
    expect(golden.budgets).toEqual(core.BUDGETS)
    expect(golden.budgetKeys).toEqual(core.BUDGET_KEYS)
    expect(golden.slowCodes).toEqual(core.SLOW_CODES)
    expect(golden.steps).toEqual(core.STEPS)
  })

  it.each(golden.vectors.map((v) => [v.name, v] as const))('%s', (_name, v) => {
    const r = core.decideTiming(v.stateBefore, v.input, v.context, v.context.uid, v.context.now)
    expect({ event: r.event, reason: r.reason, stateAfter: r.state }).toStrictEqual(v.expected)
    expect(JSON.stringify(r.event)).toBe(JSON.stringify(v.expected.event))
    if (r.event) {
      const check = validate('sdk-timing-event', r.event)
      expect(check.ok, check.text).toBe(true)
    }
  })

  it.each(golden.units.budgetFor.map((row) => [JSON.stringify(row.input), row] as const))('budgetFor %s', (_n, row) => {
    const [step, remote] = row.input as [string, unknown]
    expect(core.budgetFor(step, remote)).toBe(row.expected)
  })

  it.each(golden.units.isSlow.map((row) => [JSON.stringify(row.input), row] as const))('isSlow %s', (_n, row) => {
    const [step, ms, remote] = row.input as [string, number, unknown]
    expect(core.isSlow(step, ms, remote)).toBe(row.expected)
  })

  it.each(golden.units.timingRate.map((row) => [JSON.stringify(row.input), row] as const))('timingRate %s', (_n, row) => {
    expect(core.timingRate(row.input)).toBe(row.expected)
  })

  it('has a test for every unit table', () => {
    expect(Object.keys(golden.units).sort()).toEqual(['budgetFor', 'isSlow', 'timingRate'])
  })

  it('handles numbers JSON cannot carry and a uid that is not text', () => {
    expect(core.parseBudgetMs(Number.NaN)).toBeNull()
    expect(core.timingRate(Number.POSITIVE_INFINITY)).toBe(0.1)
    expect(core.isTimingSampled(7, 0.01)).toBe(false)
    expect(core.isSlow('config.fetch', Number.NaN, null)).toBe(false)
  })

  it('treats null state, input and context as empty, and a non-string uid as none', () => {
    expect(core.decideTiming(null, null, null, 7, 1).reason).toBe('invalid_step')
    const r = core.decideTiming(undefined, { step: 'config.fetch', ms: 1 }, { timingSampleRate: 1 }, 7, 1)
    expect(r.event?.uid).toBe('')
  })
})

describe('recordTiming', () => {
  const sampled = () => setTimingContext({ timingSampleRate: 1, uid: () => 'u-1', now: () => 1790000000000 })

  it('sends a sampled timing with the partner and app context', () => {
    sampled()
    setFailureContext({ partnerCode: 'weatherbug', appId: 'com.example', os: 'iOS 17.4' })

    recordTiming('listings.fetch', 812.4)

    const [event] = takeTimingEvents()
    expect(event).toEqual({
      event: 'sdkTiming',
      action: 'listings.fetch',
      label: 'timing',
      attributes: { code: 'weatherbug', client: 'core', clientVersion: SDK_VERSION, tv: '1', step: 'listings.fetch', ms: '812', appId: 'com.example', os: 'iOS 17.4', seq: '1' },
      uid: 'u-1',
      createdTime: 1790000000000,
    })
  })

  it('logs the slow step with its ms and budget, even when timing samples the session out', () => {
    setTimingContext({ timingSampleRate: 0, remote: { TIMING_BUDGET_LISTINGS_MS: '500' } })

    recordTiming('listings.fetch', 900.2)
    recordTiming('ad.firstLoad', 6500, '43')
    recordTiming('listings.decode', 99999)

    expect(takeTimingEvents()).toEqual([])
    const events = takeFailureEvents()
    expect(events.map((e) => [e.action, e.label, e.attributes.severity, e.attributes['ctx.ms'], e.attributes['ctx.budgetMs']])).toEqual([
      ['listings.fetch.slow', 'listings', 'warn', '900', '500'],
      ['ad.load.slow', 'banner', 'warn', '6500', '6000'],
    ])
    expect(events[1].attributes.zoneId).toBe('43')
    expect(events[0].attributes.msg).toBe('listings.fetch took 900 ms')
  })

  it('obeys TIMING_ENABLED and caps the session at 50', () => {
    setTimingContext({ timingSampleRate: 1, timingEnabled: 'off' })
    recordTiming('config.fetch', 1)
    expect(takeTimingEvents()).toEqual([])

    setTimingContext({ timingEnabled: true })
    for (let i = 0; i < 51; i++) recordTiming('listings.decode', i)
    expect(takeTimingEvents().map((e) => e.attributes.seq)).toEqual(Array.from({ length: 50 }, (_, i) => String(i + 1)))
  })

  it('uses the shared queue uid, Date.now and the queue itself by default', async () => {
    const { eventQueue } = await import('../src/event-queue')
    const push = vi.spyOn(eventQueue, 'push').mockImplementation(() => undefined)
    vi.spyOn(eventQueue, 'getUid').mockReturnValue('queue-uid')
    vi.spyOn(Date, 'now').mockReturnValue(1790000000123)
    setTimingContext({ timingSampleRate: 1, push: undefined, uid: undefined, now: undefined })

    recordTiming('config.fetch', 5)

    expect(push).toHaveBeenCalledOnce()
    expect(push.mock.calls[0][0]).toMatchObject({ event: 'sdkTiming', uid: 'queue-uid', createdTime: 1790000000123 })
  })

  it('counts its own failure instead of throwing', () => {
    setTimingContext({ timingSampleRate: 1, push: () => { throw new Error('queue') } })
    expect(() => recordTiming('config.fetch', 1)).not.toThrow()
    expect(getTimingInternalErrors()).toBe(1)
  })

  it('times a step with the monotonic clock', () => {
    let t = 100
    sampled()
    setTimingContext({ monotonic: () => t })
    const done = startTiming('ad.firstLoad', '43')
    t = 350
    expect(done()).toBe(250)
    expect(takeTimingEvents()[0].attributes).toMatchObject({ step: 'ad.firstLoad', ms: '250', zoneId: '43' })
  })

  it('reads performance.now when there is one, and Date.now otherwise', () => {
    setTimingContext({ monotonic: undefined }) // no test clock: the default one
    vi.stubGlobal('performance', { now: () => 42 })
    expect(monotonicMs()).toBe(42)
    vi.stubGlobal('performance', undefined)
    vi.spyOn(Date, 'now').mockReturnValue(7)
    expect(monotonicMs()).toBe(7)
  })
})

describe('configure timing', () => {
  it('records the config fetch once its own TIMING values apply', async () => {
    clearRemoteConfigCache()
    vi.stubGlobal('fetch', vi.fn(() => Promise.resolve(new Response(JSON.stringify(appConfig({ TIMING_SAMPLE_RATE: 1 }))))))

    await configure('weatherbug', 'weatherbug-weatherbug')

    const events = takeTimingEvents()
    expect(events.map((e) => e.action)).toEqual(['config.fetch'])
    expect(events[0].attributes.code).toBe('weatherbug')
    clearRemoteConfigCache()
  })

  it('sends nothing when the config turns timing off', async () => {
    clearRemoteConfigCache()
    vi.stubGlobal('fetch', vi.fn(() => Promise.resolve(new Response(JSON.stringify(appConfig({ TIMING_SAMPLE_RATE: 1, TIMING_ENABLED: false }))))))

    await configure('weatherbug', 'weatherbug-weatherbug')

    expect(takeTimingEvents()).toEqual([])
    clearRemoteConfigCache()
  })
})
