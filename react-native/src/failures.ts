// logFailure for React Native JS (contracts/FAILURES.md sections 2 and 3.1):
// core's shell, with every clientFailure event marked client `react-native`.
// Loading this module sets that client in core's failure context; index.ts
// imports it, and so does every file that reports a failure.
//
// Log once, at the lowest layer that sees the failure (FAILURES.md 9). Core
// already reports listings and remote-config failures, and the native SDKs
// report their own (the native bridges mark those with wrapper
// `react-native`). So React Native JS reports only what fails in React Native
// JS or its WebView, and never re-reports an error a native view or a core
// call hands it.

import { setFailureContext } from '@sellwild/sdk-core'

setFailureContext({ client: 'react-native' })

export { logFailure, FAILURE_CODES } from '@sellwild/sdk-core'
export type {
  ClientFailureEvent,
  FailureCode,
  FailureComponent,
  FailureSeverity,
  LogFailureInput,
} from '@sellwild/sdk-core'
