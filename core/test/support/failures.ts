// Records what logFailure emits in tests, instead of sending it to the shared
// events queue (which would try the network). setup.ts installs the recorder
// before every test and fails a test that leaves recorded failures unchecked,
// the same way it fails a test that tried the network.
//
// A test that expects a failure drains it with takeFailureEvents() and
// checks it. A test that needs the real queue path sets its own sink or
// `setFailureContext({ sink: undefined })`.

import { resetFailuresForTests, setFailureContext, type ClientFailureEvent, type FailureSink } from '../../src/failures'

export interface RecordedFailure {
  event: ClientFailureEvent
  /** Whether logFailure asked for an immediate flush after this event. */
  flushed: boolean
}

// On globalThis so a second evaluation of this file (vi.resetModules)
// still shares one record.
const RECORD = Symbol.for('sellwild.test.failureEvents')

function record(): RecordedFailure[] {
  const g = globalThis as { [RECORD]?: RecordedFailure[] }
  return (g[RECORD] ??= [])
}

/** A sink that records into the shared test record. */
export const recordingSink: FailureSink = {
  push(event) {
    record().push({ event, flushed: false })
  },
  flushNow() {
    const all = record()
    if (all.length) all[all.length - 1].flushed = true
  },
}

/** Reset logFailure (state, context, debug) and install the recording sink. */
export function resetFailures(): void {
  resetFailuresForTests()
  setFailureContext({ sink: recordingSink })
}

/** The failures recorded since the last drain, with their flush flag, and clears them. */
export function takeRecordedFailures(): RecordedFailure[] {
  return record().splice(0)
}

/** The failure events recorded since the last drain, and clears them. */
export function takeFailureEvents(): ClientFailureEvent[] {
  return takeRecordedFailures().map((r) => r.event)
}

/** `action` of each recorded event, and clears them: the quick check. */
export function takeFailureCodes(): string[] {
  return takeFailureEvents().map((e) => e.action)
}
