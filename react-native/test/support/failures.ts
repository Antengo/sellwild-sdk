// Records what logFailure emits in React Native tests, through an injected
// sink (core/test/support/failures.ts) instead of the shared events queue,
// which would try the network. React Native JS reports through core's
// logFailure (src/failures.ts), so core's recorder sees every report.
//
// A test file that makes the SDK report failures calls recordFailures() once
// at the top. Each test then starts with logFailure reset and recording, and
// must drain what it expects with takeFailureEvents(). One left over fails
// the test.

import { afterEach, beforeEach } from 'vitest'
import { setFailureContext } from '@sellwild/sdk-core'
import { resetFailures, takeRecordedFailures } from '../../../core/test/support/failures'

export {
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
