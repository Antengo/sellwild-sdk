// sdkTiming pure core: a TS port of contracts/reference/sdk-timing.mjs
// (contracts/FAILURES.md section 18). Every platform reproduces
// contracts/golden/sdk-timing.vectors.json.

import { cleanText, coerceFlag, fnv1a32, trimAscii, truncateUnicode } from '../failures/core'

export const TIMING_EVENT = 'sdkTiming'
export const TIMING_LABEL = 'timing'
export const TIMING_VERSION = '1'

export const STEPS = ['config.fetch', 'listings.fetch', 'listings.decode', 'feed.firstListing', 'ad.firstLoad'] as const
export type TimingStep = (typeof STEPS)[number]

export const TIMING_ATTRIBUTE_KEYS = [
  'code', 'client', 'clientVersion', 'tv', 'step', 'ms', 'zoneId', 'appId', 'appVersion', 'os', 'device', 'net', 'seq',
] as const
export type TimingAttributeKey = (typeof TIMING_ATTRIBUTE_KEYS)[number]

export const TIMING_LIMITS = {
  defaultRate: 0.1,
  sessionTimings: 50,
  maxMs: 600000,
  field: 64,
  zoneId: 32,
} as const

type BudgetStep = 'config.fetch' | 'listings.fetch' | 'ad.firstLoad'

export const BUDGETS: Readonly<Record<BudgetStep, number>> = { 'config.fetch': 3000, 'listings.fetch': 4000, 'ad.firstLoad': 6000 }
export const BUDGET_KEYS: Readonly<Record<BudgetStep, string>> = {
  'config.fetch': 'TIMING_BUDGET_CONFIG_MS',
  'listings.fetch': 'TIMING_BUDGET_LISTINGS_MS',
  'ad.firstLoad': 'TIMING_BUDGET_AD_MS',
}
export const SLOW_CODES = {
  'config.fetch': 'config.fetch.slow',
  'listings.fetch': 'listings.fetch.slow',
  'ad.firstLoad': 'ad.load.slow',
} as const

export interface TimingInput {
  step?: unknown
  ms?: unknown
  zoneId?: unknown
}

export interface TimingContext {
  partnerCode?: unknown
  client?: unknown
  clientVersion?: unknown
  appId?: unknown
  appVersion?: unknown
  os?: unknown
  device?: unknown
  net?: unknown
  eventsEnabled?: unknown
  timingEnabled?: unknown
  timingSampleRate?: unknown
}

export interface TimingState {
  sessionCount: number
}

export interface SdkTimingEvent {
  event: 'sdkTiming'
  action: string
  label: 'timing'
  attributes: Partial<Record<TimingAttributeKey, string>>
  uid: string
  createdTime: number
}

export type TimingDropReason = 'events_disabled' | 'timing_disabled' | 'invalid_step' | 'invalid_ms' | 'sampled_out' | 'session_capped'

export interface TimingDecision {
  state: TimingState
  event: SdkTimingEvent | null
  reason: TimingDropReason | null
}

const MS_RE = /^\+?[0-9]+$/
const RATE_RE = /^\+?([0-9]+(\.[0-9]*)?|\.[0-9]+)$/

function hasBudget(step: unknown): step is BudgetStep {
  return step === 'config.fetch' || step === 'listings.fetch' || step === 'ad.firstLoad'
}

/** A positive whole number of ms from a remote value, else null. */
export function parseBudgetMs(v: unknown): number | null {
  let n: number | null = null
  if (typeof v === 'number') n = Number.isFinite(v) ? Math.floor(v) : null
  else if (typeof v === 'string') {
    const t = trimAscii(v)
    if (MS_RE.test(t)) n = Number(t)
  }
  return n !== null && n >= 1 ? n : null
}

/** The budget (ms) of `step`: the remote override, else the default; null for a step without one. */
export function budgetFor(step: unknown, remote: unknown): number | null {
  if (!hasBudget(step)) return null
  const raw = remote !== null && typeof remote === 'object' ? (remote as Record<string, unknown>)[BUDGET_KEYS[step]] : undefined
  return parseBudgetMs(raw) ?? BUDGETS[step]
}

/** Whether `ms` is over the budget of `step`. */
export function isSlow(step: unknown, ms: unknown, remote: unknown): boolean {
  const budget = budgetFor(step, remote)
  return budget !== null && typeof ms === 'number' && Number.isFinite(ms) && ms > budget
}

/** TIMING_SAMPLE_RATE clamped to [0, 1]; unset or anything else → 0.1. */
export function timingRate(v: unknown): number {
  let n: number | null = null
  if (typeof v === 'number') n = Number.isFinite(v) ? v : null
  else if (typeof v === 'string') {
    const t = trimAscii(v)
    if (RATE_RE.test(t)) n = Number(t)
  }
  if (n === null) return TIMING_LIMITS.defaultRate
  return Math.min(1, Math.max(0, n))
}

/** fnv1a32(uid + ":timing") / 2^32 < rate. */
export function isTimingSampled(uid: unknown, rate: number): boolean {
  if (rate >= 1) return true
  if (rate <= 0) return false
  const u = typeof uid === 'string' ? uid : ''
  return fnv1a32(u + ':timing') / 4294967296 < rate
}

function cleanBounded(v: unknown, max: number): string | null {
  if (typeof v !== 'string') return null
  const t = cleanText(v)
  return t === '' ? null : truncateUnicode(t, max)
}

export function initialTimingState(): TimingState {
  return { sessionCount: 0 }
}

/** The whole decision as a pure function (FAILURES.md 18.1). */
export function decideTiming(
  state: TimingState | null | undefined,
  input: TimingInput | null | undefined,
  context: TimingContext | null | undefined,
  uid: unknown,
  now: number,
): TimingDecision {
  const st = state ?? initialTimingState()
  const ctx = context ?? {}
  const inp = input ?? {}
  const drop = (reason: TimingDropReason): TimingDecision => ({ state: st, event: null, reason })

  if (!coerceFlag(ctx.eventsEnabled, true)) return drop('events_disabled')
  if (!coerceFlag(ctx.timingEnabled, true)) return drop('timing_disabled')
  if (typeof inp.step !== 'string' || !(STEPS as readonly string[]).includes(inp.step)) return drop('invalid_step')
  if (typeof inp.ms !== 'number' || !Number.isFinite(inp.ms) || inp.ms < 0 || inp.ms > TIMING_LIMITS.maxMs) {
    return drop('invalid_ms')
  }
  if (!isTimingSampled(uid, timingRate(ctx.timingSampleRate))) return drop('sampled_out')
  if (st.sessionCount >= TIMING_LIMITS.sessionTimings) return drop('session_capped')

  const seq = st.sessionCount + 1
  const a: Record<TimingAttributeKey, string | undefined> = {
    code: cleanBounded(ctx.partnerCode, TIMING_LIMITS.field) ?? 'unknown',
    client: cleanBounded(ctx.client, TIMING_LIMITS.field) ?? 'unknown',
    clientVersion: cleanBounded(ctx.clientVersion, TIMING_LIMITS.field) ?? 'unknown',
    tv: TIMING_VERSION,
    step: inp.step,
    ms: String(Math.round(inp.ms)),
    zoneId: cleanBounded(inp.zoneId, TIMING_LIMITS.zoneId) ?? undefined,
    appId: cleanBounded(ctx.appId, TIMING_LIMITS.field) ?? undefined,
    appVersion: cleanBounded(ctx.appVersion, TIMING_LIMITS.field) ?? undefined,
    os: cleanBounded(ctx.os, TIMING_LIMITS.field) ?? undefined,
    device: cleanBounded(ctx.device, TIMING_LIMITS.field) ?? undefined,
    net: cleanBounded(ctx.net, TIMING_LIMITS.field) ?? undefined,
    seq: String(seq),
  }
  const attributes: Partial<Record<TimingAttributeKey, string>> = {}
  for (const k of TIMING_ATTRIBUTE_KEYS) if (a[k] !== undefined) attributes[k] = a[k]
  return {
    state: { sessionCount: seq },
    event: { event: TIMING_EVENT, action: inp.step, label: TIMING_LABEL, attributes, uid: typeof uid === 'string' ? uid : '', createdTime: now },
    reason: null,
  }
}
