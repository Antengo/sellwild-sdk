// sdkTiming shell (contracts/FAILURES.md section 18.1): times a step with a
// monotonic clock, sends the sampled sdkTiming event through the events queue,
// and logs the step's `*.slow` clientFailure when it is over its budget. All
// decisions live in ./core. Never throws.

import { eventQueue } from '../event-queue'
import { getReportContext, logFailure, type FailureCode } from '../failures'
import {
  budgetFor,
  decideTiming,
  initialTimingState,
  isSlow,
  SLOW_CODES,
  type SdkTimingEvent,
  type TimingState,
  type TimingStep,
} from './core'

export {
  budgetFor,
  decideTiming,
  isSlow,
  timingRate,
  STEPS as TIMING_STEPS,
  type SdkTimingEvent,
  type TimingStep,
} from './core'

/** The remote values timing reads, set by configure() from the config it fetched. */
export interface TimingContextInput {
  timingEnabled?: unknown
  timingSampleRate?: unknown
  /** The remote config, for the TIMING_BUDGET_*_MS overrides. */
  remote?: Record<string, unknown>
  /** Tests: where events go, and the clock, uid and monotonic clock. */
  push?: (event: SdkTimingEvent) => void
  now?: () => number
  uid?: () => string
  monotonic?: () => number
}

let context: TimingContextInput = {}
let state: TimingState = initialTimingState()
let internalErrors = 0

/** Merge `partial` into the timing context. */
export function setTimingContext(partial: TimingContextInput): void {
  context = { ...context, ...partial }
}

/** Clear the timing state, context and error count. For tests. */
export function resetTimingForTests(): void {
  context = {}
  state = initialTimingState()
  internalErrors = 0
}

/** How many times recordTiming itself failed (counted, never reported). */
export function getTimingInternalErrors(): number {
  return internalErrors
}

/** Milliseconds from a monotonic clock: performance.now() where it exists, else Date.now(). */
export function monotonicMs(): number {
  const clock = context.monotonic
  if (clock) return clock()
  const perf = (globalThis as { performance?: { now?: () => number } }).performance
  return typeof perf?.now === 'function' ? perf.now() : Date.now()
}

const COMPONENTS = { 'config.fetch': 'remoteConfig', 'listings.fetch': 'listings', 'ad.firstLoad': 'banner' } as const

/**
 * Record how long `step` took. Logs `*.slow` when the step is over its budget
 * (not sampled by timing), then sends the sdkTiming event if this session is
 * sampled. Never throws.
 */
export function recordTiming(step: TimingStep, ms: number, zoneId?: string): void {
  try {
    const ctx = context
    if (isSlow(step, ms, ctx.remote)) {
      const slowStep = step as keyof typeof SLOW_CODES
      logFailure({
        code: SLOW_CODES[slowStep] as FailureCode,
        component: COMPONENTS[slowStep],
        severity: 'warn',
        message: `${step} took ${Math.round(ms)} ms`,
        zoneId,
        context: { ms: Math.round(ms), budgetMs: budgetFor(step, ctx.remote) as number },
      })
    }
    const report = getReportContext()
    const decision = decideTiming(state, { step, ms, zoneId }, {
      ...report,
      timingEnabled: ctx.timingEnabled,
      timingSampleRate: ctx.timingSampleRate,
    }, (ctx.uid ?? (() => eventQueue.getUid()))(), (ctx.now ?? Date.now)())
    state = decision.state
    if (decision.event) (ctx.push ?? ((event) => eventQueue.push(event)))(decision.event)
    // eslint-disable-next-line sellwild/catch-reports-failure -- FAILURES.md 3.4 and 18.1: timing's own failure is counted (getTimingInternalErrors), like logFailure's; reporting it could recurse through logFailure
  } catch {
    internalErrors += 1
  }
}

/** Starts a timer; the function it returns records the step once and gives the ms. */
export function startTiming(step: TimingStep, zoneId?: string): () => number {
  const started = monotonicMs()
  return () => {
    const ms = monotonicMs() - started
    recordTiming(step, ms, zoneId)
    return ms
  }
}
