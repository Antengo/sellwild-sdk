// Records what logFailure emits in React Native tests, through an injected
// sink (core/test/support/failures.ts) instead of the shared events queue,
// which would try the network. React Native JS reports through core's
// logFailure (src/failures.ts), so core's recorder sees every report.
//
// A test file that makes the SDK report failures calls recordFailures() once
// at the top. Each test then starts with logFailure reset and recording, and
// must drain what it expects with takeFailureEvents(). One left over fails
// the test.

import { afterEach, beforeEach, vi } from 'vitest'
import { setFailureContext } from '@sellwild/sdk-core'
import { recordingSink, resetFailures, takeRecordedFailures } from '../../../core/test/support/failures'

export {
  countLogFailureCalls,
  recordingSink,
  takeFailureCodes,
  takeFailureEvents,
  takeRecordedFailures,
} from '../../../core/test/support/failures'

/** The events queue uid and clock the recorded events carry. */
export const TEST_UID = '8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11'
export const TEST_NOW = 1790000000000

/** Reset and record logFailure around every test of the calling file. */
export function recordFailures(): void {
  beforeEach(() => {
    resetFailures()
    // The reset clears the whole context, so this puts back the client that
    // src/failures.ts set when it loaded. test/failures.test.ts checks that
    // load itself, on a fresh module graph.
    setFailureContext({ client: 'react-native', uid: () => TEST_UID, now: () => TEST_NOW })
  })

  afterEach(() => {
    const left = takeRecordedFailures()
    if (left.length) {
      throw new Error(
        `this test reported failures it did not check: ${left.map((r) => r.event.action).join(', ')}. ` +
          'Drain them with takeFailureEvents() and assert on them.',
      )
    }
  })
}

/**
 * A fresh module graph (vi.resetModules) whose copy of core records into the
 * same test record, as React Native sets it up. For a test that re-imports a
 * module that reads the React Native stub when it loads (SellwildBanner,
 * SellwildFeed, commands). Returns that copy of core; import the module under
 * test after this.
 */
export async function freshModulesRecording(): Promise<typeof import('@sellwild/sdk-core')> {
  vi.resetModules()
  const core = await import('@sellwild/sdk-core')
  core.resetFailuresForTests()
  core.setFailureContext({ client: 'react-native', sink: recordingSink, uid: () => TEST_UID, now: () => TEST_NOW })
  return core
}

/**
 * countLogFailureCalls for a given copy of core (freshModulesRecording): how
 * many times logFailure ran per code while `run` ran, dropped calls included,
 * read from the debug echo of that copy.
 */
export async function countLogFailureCallsIn(
  core: typeof import('@sellwild/sdk-core'),
  run: () => unknown,
): Promise<Record<string, number>> {
  const lines: string[] = []
  const log = vi.spyOn(console, 'log').mockImplementation((line: unknown) => {
    lines.push(String(line))
  })
  core.setFailureContext({ debug: true })
  try {
    await run()
  } finally {
    core.setFailureContext({ debug: false })
    log.mockRestore()
  }
  const counts: Record<string, number> = {}
  for (const line of lines) {
    const code = /^\[Sellwild\] failure (\S+) /.exec(line)?.[1]
    if (code) counts[code] = (counts[code] ?? 0) + 1
  }
  return counts
}
