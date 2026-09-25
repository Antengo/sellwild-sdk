// logFailure shell (contracts/FAILURES.md section 3).
//
// Holds the context (partner, client, flags, injectable clock/uid/sink) and
// the gate state, turns a call into the pure-core input, and pushes what
// decideFailure emits into the SDK's existing events queue. All decisions
// live in ./core.
//
// Every failure path in the SDK is a try/catch that calls logFailure with a
// registry code (./codes). logFailure never throws, never awaits and returns
// nothing. This file and ../debug-log.ts are the only core files allowed to
// print, and this one prints only the debug echo, only when debug is on.

import { SDK_VERSION } from '../config'
import { isDebugLogging, setDebugLogging } from '../debug-log'
import { eventQueue } from '../event-queue'
import type { FailureCode } from './codes'
import {
  coerceFlag,
  coerceRate,
  decideFailure,
  initialState,
  messageFull,
  normalizeCode,
  normalizeComponent,
  normalizeSeverity,
  truncateUnicode,
  LIMITS,
  type ClientFailureEvent,
  type CoreFailureInput,
  type FailureComponent,
  type FailureDecision,
  type FailureSeverity,
  type FailureState,
} from './core'

export { FAILURE_CODES, type FailureCode } from './codes'
export type {
  ClientFailureEvent,
  FailureAttributeKey,
  FailureComponent,
  FailureDropReason,
  FailureSeverity,
} from './core'

/** One failure, as a call site reports it (FAILURES.md 3.1). */
export interface LogFailureInput {
  /** Registry code, `<area>.<operation>.<reason>`. */
  code: FailureCode
  /** What failed, e.g. `listings` or `remoteConfig`. */
  component: FailureComponent
  /** `fatal` (could not render), `error` (fallback used, the default) or `warn` (degraded). */
  severity?: FailureSeverity
  /** The caught error. An Error gives name, message and stack; a string gives the message. */
  error?: unknown
  /** Short text about what failed. Never listing text, keywords or other PII. */
  message?: string
  httpStatus?: number | string
  /** The request URL. Only its host is sent. */
  url?: string
  zoneId?: number | string
}

/** Where emitted events go. The default is the SDK's shared eventQueue. */
export interface FailureSink {
  push(event: ClientFailureEvent): void
  flushNow(): void
}

/**
 * What setFailureContext accepts. A field set to `undefined` goes back to its
 * default: unset partner and flags (unset flags mean on, rate 1), client
 * `core`, clientVersion SDK_VERSION, and the eventQueue clock, uid and sink.
 */
export interface FailureContextInput {
  partnerCode?: string
  /** `core` by default; React Native sets `react-native`. */
  client?: string
  clientVersion?: string
  /** Turns the debug echo (and debugLog) on. Stored in ../debug-log. */
  debug?: boolean
  /** Raw or coerced EVENTS_ENABLED; the core coerces it. */
  eventsEnabled?: unknown
  /** Raw or coerced FAILURES_ENABLED; the core coerces it. */
  failuresEnabled?: unknown
  /** Raw or coerced FAILURES_SAMPLE_RATE; the core coerces it. */
  failuresSampleRate?: unknown
  /** `react-native` or `flutter` when the SDK runs under a wrapper. */
  wrapper?: string
  now?: () => number
  uid?: () => string
  sink?: FailureSink
}

type StoredContext = Omit<FailureContextInput, 'debug'>

const DEFAULT_CLIENT = 'core'

// Input cap (FAILURES.md 3.3 item 4): the longest message, error message and
// stack text (UTF-16 units) handed to the pure core. Its sanitizer patterns
// backtrack superlinearly on long runs of letters and digits (10,000
// characters take about 0.35 s in V8, more on Hermes), and logFailure must
// never block the thread (FAILURES.md 3.4). Only 200 code points of message
// and 5 stack frames are ever sent, so the cut changes nothing but
// pathological input.
const MESSAGE_INPUT_MAX = 1000
const STACK_INPUT_MAX = 2000

// The shared queue, pushed as FAILURES.md 8.1 says: push, then flush for the
// first event of the session and for fatal ones.
const queueSink: FailureSink = {
  push: (event) => eventQueue.push(event),
  flushNow: () => eventQueue.flush(),
}

let context: StoredContext = {}
let state: FailureState = initialState()
let reentrant = false
let internalErrors = 0

/** Merge `partial` into the failure context. */
export function setFailureContext(partial: FailureContextInput): void {
  const { debug, ...rest } = partial
  if ('debug' in partial) setDebugLogging(debug === true)
  context = { ...context, ...rest }
}

/**
 * Clear the gate state, the internal error count and the whole context
 * (debug included). For tests.
 */
export function resetFailuresForTests(): void {
  context = {}
  state = initialState()
  reentrant = false
  internalErrors = 0
  setDebugLogging(false)
}

/**
 * How many times logFailure itself failed (a throwing clock, sink or error
 * getter). Those are counted instead of reported, since reporting them would
 * recurse (FAILURES.md 3.4).
 */
export function getFailureInternalErrors(): number {
  return internalErrors
}

// Read one caller-supplied value. A throwing getter counts as an internal
// error and gives undefined, so the rest of the report still goes out.
function read<T>(get: () => T): T | undefined {
  try {
    return get()
  } catch {
    internalErrors += 1
    return undefined
  }
}

function bounded(value: unknown, max: number): unknown {
  return typeof value === 'string' && value.length > max ? value.slice(0, max) : value
}

// V8 starts error.stack with the header `<name>: <message>` (`<name>` alone
// when the message is empty). When the stack is over the cap, that header is
// removed before the cut, so a long message cannot push every frame out of it.
// Under the cap the pure core drops the header itself (FAILURES.md 7.4).
function boundedStack(stack: unknown, name: unknown, message: unknown): unknown {
  if (typeof stack !== 'string' || stack.length <= STACK_INPUT_MAX) return stack
  let rest = stack
  if (typeof name === 'string') {
    const header = typeof message === 'string' && message !== '' ? `${name}: ${message}` : name
    if (stack.startsWith(header) && (stack.length === header.length || stack[header.length] === '\n')) rest = stack.slice(header.length)
  }
  return bounded(rest, STACK_INPUT_MAX)
}

// FAILURES.md 3.3: an Error gives name, message and stack; a string gives the
// message; anything else is ignored. Other inputs pass through as given, long
// text cut to the input cap above.
function toCoreInput(input: LogFailureInput): CoreFailureInput {
  const src: Partial<LogFailureInput> = input !== null && typeof input === 'object' ? input : {}
  const error = read(() => src.error)
  const out: CoreFailureInput = {
    code: read(() => src.code),
    component: read(() => src.component),
    severity: read(() => src.severity),
    message: bounded(read(() => src.message), MESSAGE_INPUT_MAX),
    httpStatus: read(() => src.httpStatus),
    url: read(() => src.url),
    zoneId: read(() => src.zoneId),
  }
  if (read(() => error instanceof Error)) {
    const err = error as Error
    const name = read(() => err.name)
    const message = read(() => err.message)
    out.errName = name
    out.errMessage = bounded(message, MESSAGE_INPUT_MAX)
    out.stack = boundedStack(read(() => err.stack), name, message)
  } else if (typeof error === 'string') {
    out.errMessage = bounded(error, MESSAGE_INPUT_MAX)
  }
  return out
}

// `[Sellwild] failure <action> <label> <severity> <reason or "sent"> <msg>`,
// with the sanitized message only (FAILURES.md 2).
function echoLine(input: CoreFailureInput, decision: FailureDecision): string {
  const msg = truncateUnicode(messageFull(input), LIMITS.msg)
  return [
    '[Sellwild] failure',
    normalizeCode(input.code),
    normalizeComponent(input.component),
    normalizeSeverity(input.severity),
    decision.reason ?? 'sent',
    ...(msg === '' ? [] : [msg]),
  ].join(' ')
}

function echoInternalError(error: unknown): void {
  try {
    const name = error instanceof Error ? error.name : typeof error
    console.log(`[Sellwild] failure internal-error ${name}`)
  } catch {
    internalErrors += 1
  }
}

/** The kill switches a config sets: raw or coerced EVENTS_ENABLED, FAILURES_ENABLED and FAILURES_SAMPLE_RATE. */
export interface FailureFlags {
  eventsEnabled?: unknown
  failuresEnabled?: unknown
  failuresSampleRate?: unknown
}

/**
 * The stricter of two sets of kill switches: each switch on only when both
 * are on, and the lower sample rate. Unset means on and rate 1
 * (FAILURES.md 3.2). Pure.
 */
export function strictestFailureFlags(a: FailureFlags, b: FailureFlags): Required<FailureFlags> {
  return {
    eventsEnabled: coerceFlag(a.eventsEnabled, true) && coerceFlag(b.eventsEnabled, true),
    failuresEnabled: coerceFlag(a.failuresEnabled, true) && coerceFlag(b.failuresEnabled, true),
    failuresSampleRate: Math.min(coerceRate(a.failuresSampleRate), coerceRate(b.failuresSampleRate)),
  }
}

/**
 * Report `inputs` under `flags` as well as the context's own kill switches:
 * each goes out only when both allow it, at the lower sample rate
 * (strictestFailureFlags). The context is left as it was, so `flags` never
 * reach a later report. For reports about a config that is not the active
 * one: they honor that config's switches (FAILURES.md 10.1) without undoing
 * the active config or a host override (FAILURES.md 3.2).
 */
export function logFailuresWithFlags(flags: FailureFlags, inputs: readonly LogFailureInput[]): void {
  const saved: FailureFlags = {
    eventsEnabled: context.eventsEnabled,
    failuresEnabled: context.failuresEnabled,
    failuresSampleRate: context.failuresSampleRate,
  }
  context = { ...context, ...strictestFailureFlags(saved, flags) }
  try {
    for (const input of inputs) logFailure(input)
  } finally {
    context = { ...context, ...saved }
  }
}

/**
 * Report one failure (FAILURES.md 3.4). Never throws and never blocks: the
 * event rides the events queue, flushed at once for the first failure of the
 * session and for fatal ones. A nested call from inside logFailure (a sink or
 * clock that fails) is ignored.
 */
export function logFailure(input: LogFailureInput): void {
  if (reentrant) return
  reentrant = true
  try {
    const ctx = context
    const coreInput = toCoreInput(input)
    const uid = (ctx.uid ?? (() => eventQueue.getUid()))()
    const now = (ctx.now ?? Date.now)()
    const decision = decideFailure(state, coreInput, {
      partnerCode: ctx.partnerCode,
      client: ctx.client ?? DEFAULT_CLIENT,
      clientVersion: ctx.clientVersion ?? SDK_VERSION,
      wrapper: ctx.wrapper,
      eventsEnabled: ctx.eventsEnabled,
      failuresEnabled: ctx.failuresEnabled,
      failuresSampleRate: ctx.failuresSampleRate,
    }, uid, now)
    state = decision.state
    if (isDebugLogging()) console.log(echoLine(coreInput, decision))
    if (decision.event) {
      const sink = ctx.sink ?? queueSink
      sink.push(decision.event)
      if (decision.flushNow) sink.flushNow()
    }
  } catch (error) {
    // The one failure that is not reported: reporting it would recurse. It is
    // counted for tests, and echoed when debug is on.
    internalErrors += 1
    if (isDebugLogging()) echoInternalError(error)
  } finally {
    reentrant = false
  }
}
