// Records what recordTiming sends in tests, instead of the shared events
// queue. setup.ts installs it before every test. Timing is sampled (10% by
// default), so tests that check it set the rate to 1 and drain the record
// with takeTimingEvents(); the rest is cleared before each test.

import { resetTimingForTests, setTimingContext, type SdkTimingEvent } from '../../src/timing'

const RECORD = Symbol.for('sellwild.test.timingEvents')

function record(): SdkTimingEvent[] {
  const g = globalThis as { [RECORD]?: SdkTimingEvent[] }
  return (g[RECORD] ??= [])
}

/** Reset timing and record what it sends. */
export function resetTiming(): void {
  record().splice(0)
  resetTimingForTests()
  setTimingContext({ push: (event) => record().push(event) })
}

/** The timing events recorded since the last drain, and clears them. */
export function takeTimingEvents(): SdkTimingEvent[] {
  return record().splice(0)
}
