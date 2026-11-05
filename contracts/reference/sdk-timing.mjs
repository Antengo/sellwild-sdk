// Reference implementation of the sdkTiming pure core (contracts/FAILURES.md
// section 18). Dependency-free and deterministic; every platform's timing core
// must reproduce golden/sdk-timing.vectors.json, which this file generates.
//
// A shell times each step with a monotonic clock and calls decideTiming once
// per measurement. Independently it asks isSlow and, when a step is over its
// budget, logs the step's `*.slow` clientFailure (SLOW_CODES) with the ms in
// its call-site context. The slow check is never sampled by timing sampling;
// the clientFailure gate samples it as any other failure.

import { cleanText, coerceFlag, fnv1a32, trimAscii, truncateUnicode } from './log-failure.mjs'

export const TIMING_EVENT = 'sdkTiming'
export const TIMING_LABEL = 'timing'
export const TIMING_VERSION = '1'

/** The steps a shell times, in the order they happen. */
export const STEPS = Object.freeze(['config.fetch', 'listings.fetch', 'listings.decode', 'feed.firstListing', 'ad.firstLoad'])

/** Wire order of attribute keys; also the allowlist. */
export const TIMING_ATTRIBUTE_KEYS = Object.freeze([
  'code', 'client', 'clientVersion', 'tv', 'step', 'ms', 'zoneId', 'appId', 'appVersion', 'os', 'device', 'net', 'seq',
])

export const TIMING_LIMITS = Object.freeze({
  defaultRate: 0.1,
  sessionTimings: 50,
  maxMs: 600000,
  field: 64,
  zoneId: 32,
})

/** Default budgets (ms) of the steps that have one. */
export const BUDGETS = Object.freeze({ 'config.fetch': 3000, 'listings.fetch': 4000, 'ad.firstLoad': 6000 })

/** The remote-config key that overrides each budget. */
export const BUDGET_KEYS = Object.freeze({
  'config.fetch': 'TIMING_BUDGET_CONFIG_MS',
  'listings.fetch': 'TIMING_BUDGET_LISTINGS_MS',
  'ad.firstLoad': 'TIMING_BUDGET_AD_MS',
})

/** The clientFailure code a step over its budget logs. */
export const SLOW_CODES = Object.freeze({
  'config.fetch': 'config.fetch.slow',
  'listings.fetch': 'listings.fetch.slow',
  'ad.firstLoad': 'ad.load.slow',
})

const MS_RE = /^\+?[0-9]+$/
const RATE_RE = /^\+?([0-9]+(\.[0-9]*)?|\.[0-9]+)$/

/**
 * A positive whole number of ms from a remote value: a finite number >= 1, or
 * a string of digits. Anything else → null (the default applies).
 */
export function parseBudgetMs(v) {
  let n = null
  if (typeof v === 'number') n = Number.isFinite(v) ? Math.floor(v) : null
  else if (typeof v === 'string') {
    const t = trimAscii(v)
    if (MS_RE.test(t)) n = Number(t)
  }
  return n !== null && n >= 1 ? n : null
}

/** The budget (ms) of `step`: the remote override, else the default; null for a step without one. */
export function budgetFor(step, remote) {
  if (!Object.hasOwn(BUDGETS, step)) return null
  const raw = remote !== null && typeof remote === 'object' ? remote[BUDGET_KEYS[step]] : undefined
  return parseBudgetMs(raw) ?? BUDGETS[step]
}

/** Whether `ms` is over the budget of `step`. Steps without a budget are never slow. */
export function isSlow(step, ms, remote) {
  const budget = budgetFor(step, remote)
  return budget !== null && typeof ms === 'number' && Number.isFinite(ms) && ms > budget
}

/**
 * TIMING_SAMPLE_RATE: a finite number or a plain decimal string, clamped to
 * [0, 1]. Unset or anything else → 0.1.
 */
export function timingRate(v) {
  let n = null
  if (typeof v === 'number') n = Number.isFinite(v) ? v : null
  else if (typeof v === 'string') {
    const t = trimAscii(v)
    if (RATE_RE.test(t)) n = Number(t)
  }
  if (n === null) return TIMING_LIMITS.defaultRate
  return Math.min(1, Math.max(0, n))
}

/** Session sampling for timings: fnv1a32(uid + ":timing") / 2^32 < rate. */
export function isTimingSampled(uid, rate) {
  if (rate >= 1) return true
  if (rate <= 0) return false
  const u = typeof uid === 'string' ? uid : ''
  return fnv1a32(u + ':timing') / 4294967296 < rate
}

function cleanBounded(v, max) {
  if (typeof v !== 'string') return null
  const t = cleanText(v)
  return t === '' ? null : truncateUnicode(t, max)
}

export function initialTimingState() {
  return { sessionCount: 0 }
}

/**
 * The whole decision as a pure function.
 *
 * input:   { step, ms, zoneId? }
 * context: { partnerCode, client, clientVersion, appId?, appVersion?, os?, device?, net?,
 *            eventsEnabled?, timingEnabled?, timingSampleRate? }
 * state:   { sessionCount }
 *
 * Returns { state, event, reason }. `event` is null when dropped and `reason`
 * names why (null when emitted).
 */
export function decideTiming(state, input, context, uid, now) {
  const st = state ?? initialTimingState()
  const ctx = context ?? {}
  const inp = input ?? {}
  const drop = (reason) => ({ state: st, event: null, reason })

  if (!coerceFlag(ctx.eventsEnabled, true)) return drop('events_disabled')
  if (!coerceFlag(ctx.timingEnabled, true)) return drop('timing_disabled')
  if (typeof inp.step !== 'string' || !STEPS.includes(inp.step)) return drop('invalid_step')
  if (typeof inp.ms !== 'number' || !Number.isFinite(inp.ms) || inp.ms < 0 || inp.ms > TIMING_LIMITS.maxMs) {
    return drop('invalid_ms')
  }
  if (!isTimingSampled(uid, timingRate(ctx.timingSampleRate))) return drop('sampled_out')
  if (st.sessionCount >= TIMING_LIMITS.sessionTimings) return drop('session_capped')

  const seq = st.sessionCount + 1
  const zoneId = typeof inp.zoneId === 'string' ? cleanBounded(inp.zoneId, TIMING_LIMITS.zoneId) : null
  const a = {
    code: cleanBounded(ctx.partnerCode, TIMING_LIMITS.field) ?? 'unknown',
    client: cleanBounded(ctx.client, TIMING_LIMITS.field) ?? 'unknown',
    clientVersion: cleanBounded(ctx.clientVersion, TIMING_LIMITS.field) ?? 'unknown',
    tv: TIMING_VERSION,
    step: inp.step,
    ms: String(Math.round(inp.ms)),
    zoneId: zoneId ?? undefined,
    appId: cleanBounded(ctx.appId, TIMING_LIMITS.field) ?? undefined,
    appVersion: cleanBounded(ctx.appVersion, TIMING_LIMITS.field) ?? undefined,
    os: cleanBounded(ctx.os, TIMING_LIMITS.field) ?? undefined,
    device: cleanBounded(ctx.device, TIMING_LIMITS.field) ?? undefined,
    net: cleanBounded(ctx.net, TIMING_LIMITS.field) ?? undefined,
    seq: String(seq),
  }
  const attributes = {}
  for (const k of TIMING_ATTRIBUTE_KEYS) if (a[k] !== undefined) attributes[k] = a[k]
  return {
    state: { sessionCount: seq },
    event: {
      event: TIMING_EVENT,
      action: inp.step,
      label: TIMING_LABEL,
      attributes,
      uid: typeof uid === 'string' ? uid : '',
      createdTime: now,
    },
    reason: null,
  }
}
