import { afterAll, afterEach, beforeEach, vi } from 'vitest'
import { eventQueue } from '../src/event-queue'
import { resetFailures, takeRecordedFailures } from './support/failures'

// Contract A8: tests never touch the network. fetch, XMLHttpRequest,
// WebSocket and navigator.sendBeacon (when present) are replaced with
// versions that fail with `network blocked in tests: <url>`. fetch returns a
// rejected promise, as a real failed fetch does, so a caller's .catch runs.
// The others throw.
//
// A test that needs one installs its own with vi.stubGlobal(...) inside the
// test or a beforeEach. The afterEach below puts the blockers back.
//
// Source code often catches that error (fetchRemoteConfig falls back to
// defaults, for one), so every blocked call is also recorded and the test
// that made it fails in afterEach. A test that means to hit the blocker
// drains the record with takeBlockedNetworkCalls().
//
// react-native/test/setup.ts carries the same blocker. Keep the two in step.

// On globalThis so a second evaluation of this file (vi.resetModules)
// still shares one record.
const RECORD = Symbol.for('sellwild.test.blockedNetworkCalls')

function record(): string[] {
  const g = globalThis as { [RECORD]?: string[] }
  return (g[RECORD] ??= [])
}

function urlOf(input: unknown): string {
  if (typeof input === 'string') return input
  if (input instanceof URL) return input.href
  if (input && typeof input === 'object' && 'url' in input) {
    return String((input as { url: unknown }).url)
  }
  return String(input)
}

function blocked(api: string, url: string): Error {
  record().push(`${api} ${url}`)
  return new Error(`network blocked in tests: ${url}`)
}

function block(api: string, url: string): never {
  throw blocked(api, url)
}

class BlockedXMLHttpRequest {
  open(_method: string, url: string | URL): void {
    block('XMLHttpRequest', urlOf(url))
  }

  send(): void {
    block('XMLHttpRequest', '(not opened)')
  }
}

class BlockedWebSocket {
  constructor(url: string | URL) {
    block('WebSocket', urlOf(url))
  }
}

function define(target: object, key: string, value: unknown): void {
  Object.defineProperty(target, key, { value, writable: true, configurable: true })
}

export function installNetworkBlock(): void {
  define(globalThis, 'fetch', (input: unknown) => Promise.reject(blocked('fetch', urlOf(input))))
  define(globalThis, 'XMLHttpRequest', BlockedXMLHttpRequest)
  define(globalThis, 'WebSocket', BlockedWebSocket)
  const nav = (globalThis as { navigator?: { sendBeacon?: unknown } }).navigator
  if (nav && typeof nav.sendBeacon === 'function') {
    define(nav, 'sendBeacon', (url: unknown) => block('sendBeacon', urlOf(url)))
  }
}

/** Returns the blocked calls recorded since the last drain, and clears them. */
export function takeBlockedNetworkCalls(): string[] {
  return record().splice(0)
}

function failOnBlockedCalls(when: string): void {
  const calls = takeBlockedNetworkCalls()
  if (calls.length) {
    throw new Error(
      `${when} tried to reach the network: ${calls.join(', ')}. ` +
        'Stub it with vi.stubGlobal, or drain it with takeBlockedNetworkCalls() if the block is the point.',
    )
  }
}

// logFailure (contracts/FAILURES.md) sends to the shared events queue, which
// would try the network. Every test starts with logFailure reset and
// recording into test/support/failures.ts instead. A test that makes the SDK
// report a failure must check it: drain it with takeFailureEvents() (or
// takeFailureCodes()). One left over fails the test, like a blocked call.
function failOnUncheckedFailures(when: string): void {
  const left = takeRecordedFailures()
  if (left.length) {
    throw new Error(
      `${when} reported failures it did not check: ${left.map((r) => r.event.action).join(', ')}. ` +
        'Drain them with takeFailureEvents() and assert on them.',
    )
  }
}

// Runs both checks, so both records are drained even when the first fails.
function failOnLeftovers(when: string): void {
  const messages: string[] = []
  for (const check of [failOnBlockedCalls, failOnUncheckedFailures]) {
    try {
      check(when)
    } catch (error) {
      messages.push((error as Error).message)
    }
  }
  if (messages.length) throw new Error(messages.join('\n'))
}

installNetworkBlock()

beforeEach(() => {
  resetFailures()
})

// After every test: real timers, mocks reset to their original
// implementations, spies and stubbed globals and env restored, blockers back.
// So set fake timers, stubs and spies up in beforeEach or the test itself,
// not in beforeAll. configure() sets the shared queue's kill switch and
// partner code, so those go back to their defaults too.
afterEach(() => {
  vi.useRealTimers()
  vi.resetAllMocks()
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
  vi.unstubAllEnvs()
  installNetworkBlock()
  eventQueue.setEnabled(true)
  eventQueue.setPartnerCode('')
  failOnLeftovers('this test')
})

// Catches a call made after the last test finished, e.g. from a timer.
afterAll(() => {
  failOnLeftovers('a timer or promise left over from this file')
})
